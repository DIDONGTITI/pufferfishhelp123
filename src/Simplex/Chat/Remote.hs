{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

{-# OPTIONS_GHC -fno-warn-ambiguous-fields #-}

module Simplex.Chat.Remote where

import Control.Applicative ((<|>))
import Control.Logger.Simple
import Control.Monad
import Control.Monad.Except
import Control.Monad.IO.Class
import Control.Monad.Reader
import Control.Monad.STM (retry)
import Crypto.Random (getRandomBytes)
import qualified Data.Aeson as J
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64.URL as B64U
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Char8 as B
import Data.Functor (($>))
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Word (Word16, Word32)
import qualified Network.HTTP.Types as N
import Network.HTTP2.Server (responseStreaming)
import Network.Socket (SockAddr (..), hostAddressToTuple)
import Simplex.Chat.Archive (archiveFilesFolder)
import Simplex.Chat.Controller
import Simplex.Chat.Files
import Simplex.Chat.Messages (chatNameStr)
import Simplex.Chat.Remote.Protocol
import Simplex.Chat.Remote.RevHTTP (announceRevHTTP2, connectRevHTTP2)
import Simplex.Chat.Remote.Transport
import Simplex.Chat.Remote.Types
import Simplex.Chat.Store.Files
import Simplex.Chat.Store.Remote
import Simplex.Chat.Store.Shared
import Simplex.Chat.Types (User (..))
import Simplex.Chat.Util (encryptFile)
import Simplex.FileTransfer.Description (FileDigest (..))
import qualified Simplex.Messaging.Crypto as C
import Simplex.Messaging.Crypto.File (CryptoFile (..), CryptoFileArgs (..))
import qualified Simplex.Messaging.Crypto.File as CF
import Simplex.Messaging.Encoding (smpDecode)
import Simplex.Messaging.Encoding.String (StrEncoding (..))
import qualified Simplex.Messaging.TMap as TM
import Simplex.Messaging.Transport.Client (TransportHost (..))
import Simplex.Messaging.Transport.Credentials (genCredentials, tlsCredentials)
import Simplex.Messaging.Transport.HTTP2.File (hSendFile)
import Simplex.Messaging.Transport.HTTP2.Server (HTTP2Request (..))
import Simplex.Messaging.Util (ifM, liftEitherError, liftEitherWith, liftError, liftIOEither, tryAllErrors, tshow, ($>>=), (<$$>))
import qualified Simplex.RemoteControl.Discovery as Discovery
import Simplex.RemoteControl.Types
import System.FilePath (takeFileName, (</>))
import UnliftIO
import UnliftIO.Directory (copyFile, createDirectoryIfMissing, renameFile)

-- * Desktop side

getRemoteHostSession :: ChatMonad m => RemoteHostId -> m RemoteHostSession
getRemoteHostSession rhId = withRemoteHostSession rhId $ \_ s -> pure $ Right s

withRemoteHostSession :: ChatMonad m => RemoteHostId -> (TM.TMap RemoteHostId RemoteHostSession -> RemoteHostSession -> STM (Either ChatError a)) -> m a
withRemoteHostSession rhId = withRemoteHostSession_ rhId missing
  where
    missing _ = pure . Left $ ChatErrorRemoteHost rhId RHMissing

withNoRemoteHostSession :: ChatMonad m => RemoteHostId -> (TM.TMap RemoteHostId RemoteHostSession -> STM (Either ChatError a)) -> m a
withNoRemoteHostSession rhId action = withRemoteHostSession_ rhId action busy
  where
    busy _ _ = pure . Left $ ChatErrorRemoteHost rhId RHBusy

-- | Atomically process controller state wrt. specific remote host session
withRemoteHostSession_ :: ChatMonad m => RemoteHostId -> (TM.TMap RemoteHostId RemoteHostSession -> STM (Either ChatError a)) -> (TM.TMap RemoteHostId RemoteHostSession -> RemoteHostSession -> STM (Either ChatError a)) -> m a
withRemoteHostSession_ rhId missing present = do
  sessions <- asks remoteHostSessions
  liftIOEither . atomically $ TM.lookup rhId sessions >>= maybe (missing sessions) (present sessions)

startRemoteHost :: ChatMonad m => RemoteHostId -> m ()
startRemoteHost rhId = do
  rh <- withStore (`getRemoteHost` rhId)
  tasks <- startRemoteHostSession rh
  logInfo $ "Remote host session starting for " <> tshow rhId
  asyncRegistered tasks $ run rh tasks `catchAny` \err -> do
    logError $ "Remote host session startup failed for " <> tshow rhId <> ": " <> tshow err
    cancelTasks tasks
    chatModifyVar remoteHostSessions $ M.delete rhId
    throwError $ fromMaybe (mkChatError err) $ fromException err
  -- logInfo $ "Remote host session starting for " <> tshow rhId
  where
    run :: ChatMonad m => RemoteHost -> Tasks -> m ()
    run rh@RemoteHost {storePath} tasks = do
      (fingerprint, credentials) <- liftIO $ genSessionCredentials rh
      cleanupIO <- toIO $ do
        logNote $ "Remote host session stopping for " <> tshow rhId
        cancelTasks tasks -- cancel our tasks anyway
        chatModifyVar currentRemoteHost $ \cur -> if cur == Just rhId then Nothing else cur -- only wipe the closing RH
        withRemoteHostSession rhId $ \sessions _ -> Right <$> TM.delete rhId sessions
        toView (CRRemoteHostStopped rhId) -- only signal "stopped" when the session is unregistered cleanly
      -- block until some client is connected or an error happens
      logInfo $ "Remote host session connecting for " <> tshow rhId
      rcName <- chatReadVar localDeviceName
      localAddr <- asks multicastSubscribers >>= Discovery.getLocalAddress >>= maybe (throwError . ChatError $ CEInternalError "unable to get local address") pure
      (dhKey, sigKey, ann, oob) <- Discovery.startSession (if rcName == "" then Nothing else Just rcName) (localAddr, read Discovery.DISCOVERY_PORT) fingerprint
      toView CRRemoteHostStarted {remoteHost = remoteHostInfo rh True, sessionOOB = decodeUtf8 $ strEncode oob}
      httpClient <- liftEitherError (ChatErrorRemoteCtrl . RCEHTTP2Error . show) $ announceRevHTTP2 tasks (sigKey, ann) credentials cleanupIO
      logInfo $ "Remote host session connected for " <> tshow rhId
      -- test connection and establish a protocol layer
      remoteHostClient <- liftRH rhId $ createRemoteHostClient httpClient dhKey rcName
      -- set up message polling
      oq <- asks outputQ
      asyncRegistered tasks . forever $ do
        liftRH rhId (remoteRecv remoteHostClient 1000000) >>= mapM_ (atomically . writeTBQueue oq . (Nothing,Just rhId,))
      -- update session state
      logInfo $ "Remote host session started for " <> tshow rhId
      chatModifyVar remoteHostSessions $ M.adjust (\rhs -> rhs {remoteHostClient = Just remoteHostClient}) rhId
      chatWriteVar currentRemoteHost $ Just rhId
      toView $ CRRemoteHostConnected RemoteHostInfo
        { remoteHostId = rhId,
          storePath = storePath,
          displayName = hostDeviceName remoteHostClient,
          sessionActive = True
        }

    genSessionCredentials RemoteHost {caKey, caCert} = do
      sessionCreds <- genCredentials (Just parent) (0, 24) "Session"
      pure . tlsCredentials $ sessionCreds :| [parent]
      where
        parent = (C.signatureKeyPair caKey, caCert)

-- | Atomically check/register session and prepare its task list
startRemoteHostSession :: ChatMonad m => RemoteHost -> m Tasks
startRemoteHostSession RemoteHost {remoteHostId, storePath} = withNoRemoteHostSession remoteHostId $ \sessions -> do
  remoteHostTasks <- newTVar []
  TM.insert remoteHostId RemoteHostSession {remoteHostTasks, storePath, remoteHostClient = Nothing} sessions
  pure $ Right remoteHostTasks

closeRemoteHostSession :: ChatMonad m => RemoteHostId -> m ()
closeRemoteHostSession rhId = do
  logNote $ "Closing remote host session for " <> tshow rhId
  chatModifyVar currentRemoteHost $ \cur -> if cur == Just rhId then Nothing else cur -- only wipe the closing RH
  session <- withRemoteHostSession rhId $ \sessions rhs -> Right rhs <$ TM.delete rhId sessions
  cancelRemoteHostSession session

cancelRemoteHostSession :: MonadUnliftIO m => RemoteHostSession -> m ()
cancelRemoteHostSession RemoteHostSession {remoteHostTasks, remoteHostClient} = do
  cancelTasks remoteHostTasks
  mapM_ closeRemoteHostClient remoteHostClient

createRemoteHost :: ChatMonad m => m RemoteHostInfo
createRemoteHost = do
  ((_, caKey), caCert) <- liftIO $ genCredentials Nothing (-25, 24 * 365) "Host"
  storePath <- liftIO randomStorePath
  let remoteName = "" -- will be passed from remote host in hello
  rhId <- withStore' $ \db -> insertRemoteHost db storePath remoteName caKey caCert
  rh <- withStore $ \db -> getRemoteHost db rhId
  pure $ remoteHostInfo rh False

-- | Generate a random 16-char filepath without / in it by using base64url encoding.
randomStorePath :: IO FilePath
randomStorePath = B.unpack . B64U.encode <$> getRandomBytes 12

listRemoteHosts :: ChatMonad m => m [RemoteHostInfo]
listRemoteHosts = do
  active <- chatReadVar remoteHostSessions
  map (rhInfo active) <$> withStore' getRemoteHosts
  where
    rhInfo active rh@RemoteHost {remoteHostId} =
      remoteHostInfo rh (M.member remoteHostId active)

remoteHostInfo :: RemoteHost -> Bool -> RemoteHostInfo
remoteHostInfo RemoteHost {remoteHostId, storePath, displayName} sessionActive =
  RemoteHostInfo {remoteHostId, storePath, displayName, sessionActive}

deleteRemoteHost :: ChatMonad m => RemoteHostId -> m ()
deleteRemoteHost rhId = do
  RemoteHost {storePath} <- withStore (`getRemoteHost` rhId)
  chatReadVar filesFolder >>= \case
    Just baseDir -> do
      let hostStore = baseDir </> storePath
      logError $ "TODO: remove " <> tshow hostStore
    Nothing -> logWarn "Local file store not available while deleting remote host"
  withStore' (`deleteRemoteHostRecord` rhId)

storeRemoteFile :: forall m. ChatMonad m => RemoteHostId -> Maybe Bool -> FilePath -> m CryptoFile
storeRemoteFile rhId encrypted_ localPath = do
  RemoteHostSession {remoteHostClient, storePath} <- getRemoteHostSession rhId
  case remoteHostClient of
    Nothing -> throwError $ ChatErrorRemoteHost rhId RHMissing
    Just c@RemoteHostClient {encryptHostFiles} -> do
      let encrypt = fromMaybe encryptHostFiles encrypted_
      cf@CryptoFile {filePath} <- if encrypt then encryptLocalFile else pure $ CF.plain localPath
      filePath' <- liftRH rhId $ remoteStoreFile c filePath (takeFileName localPath)
      hf_ <- chatReadVar remoteHostsFolder
      forM_ hf_ $ \hf -> do
        let rhf = hf </> storePath </> archiveFilesFolder
            hPath = rhf </> takeFileName filePath'
        createDirectoryIfMissing True rhf
        (if encrypt then renameFile else copyFile) filePath hPath
      pure (cf :: CryptoFile) {filePath = filePath'}
  where
    encryptLocalFile :: m CryptoFile
    encryptLocalFile = do
      tmpDir <- getChatTempDirectory
      createDirectoryIfMissing True tmpDir
      tmpFile <- tmpDir `uniqueCombine` takeFileName localPath
      cfArgs <- liftIO CF.randomArgs
      liftError (ChatError . CEFileWrite tmpFile) $ encryptFile localPath tmpFile cfArgs
      pure $ CryptoFile tmpFile $ Just cfArgs

getRemoteFile :: ChatMonad m => RemoteHostId -> RemoteFile -> m ()
getRemoteFile rhId rf = do
  RemoteHostSession {remoteHostClient, storePath} <- getRemoteHostSession rhId
  case remoteHostClient of
    Nothing -> throwError $ ChatErrorRemoteHost rhId RHMissing
    Just c -> do
      dir <- (</> storePath </> archiveFilesFolder) <$> (maybe getDefaultFilesFolder pure =<< chatReadVar remoteHostsFolder)
      createDirectoryIfMissing True dir
      liftRH rhId $ remoteGetFile c dir rf

processRemoteCommand :: ChatMonad m => RemoteHostId -> RemoteHostSession -> ChatCommand -> ByteString -> m ChatResponse
processRemoteCommand remoteHostId RemoteHostSession {remoteHostClient = Just rhc} cmd s = case cmd of
  SendFile chatName f -> sendFile "/f" chatName f
  SendImage chatName f -> sendFile "/img" chatName f
  _ -> liftRH remoteHostId $ remoteSend rhc s
  where
    sendFile cmdName chatName (CryptoFile path cfArgs) = do
      -- don't encrypt in host if already encrypted locally
      CryptoFile path' cfArgs' <- storeRemoteFile remoteHostId (cfArgs $> False) path
      let f = CryptoFile path' (cfArgs <|> cfArgs') -- use local or host encryption
      liftRH remoteHostId $ remoteSend rhc $ B.unwords [cmdName, B.pack (chatNameStr chatName), cryptoFileStr f]
    cryptoFileStr CryptoFile {filePath, cryptoArgs} =
      maybe "" (\(CFArgs key nonce) -> "key=" <> strEncode key <> " nonce=" <> strEncode nonce <> " ") cryptoArgs
        <> encodeUtf8 (T.pack filePath)
processRemoteCommand _ _ _ _ = pure $ chatCmdError Nothing "remote command sent before session started"

liftRH :: ChatMonad m => RemoteHostId -> ExceptT RemoteProtocolError IO a -> m a
liftRH rhId = liftError (ChatErrorRemoteHost rhId . RHProtocolError)

-- * Mobile side

startRemoteCtrl :: forall m . ChatMonad m => (ByteString -> m ChatResponse) -> m ()
startRemoteCtrl execChatCommand = do
  logInfo "Starting remote host"
  checkNoRemoteCtrlSession -- tiny race with the final @chatWriteVar@ until the setup finishes and supervisor spawned
  discovered <- newTVarIO mempty
  discoverer <- async $ discoverRemoteCtrls discovered -- TODO extract to a controller service singleton
  size <- asks $ tbqSize . config
  remoteOutputQ <- newTBQueueIO size
  accepted <- newEmptyTMVarIO
  supervisor <- async $ runHost discovered accepted $ handleRemoteCommand execChatCommand remoteOutputQ
  chatWriteVar remoteCtrlSession $ Just RemoteCtrlSession {discoverer, supervisor, hostServer = Nothing, discovered, accepted, remoteOutputQ}

-- | Track remote host lifecycle in controller session state and signal UI on its progress
runHost :: ChatMonad m => TM.TMap C.KeyHash (TransportHost, Word16) -> TMVar RemoteCtrlId -> (HTTP2Request -> m ()) -> m ()
runHost discovered accepted handleHttp = do
  remoteCtrlId <- atomically (readTMVar accepted) -- wait for ???
  rc@RemoteCtrl {fingerprint} <- withStore (`getRemoteCtrl` remoteCtrlId)
  serviceAddress <- atomically $ TM.lookup fingerprint discovered >>= maybe retry pure -- wait for location of the matching fingerprint
  toView $ CRRemoteCtrlConnecting $ remoteCtrlInfo rc False
  atomically $ writeTVar discovered mempty -- flush unused sources
  server <- async $ connectRevHTTP2 serviceAddress fingerprint handleHttp -- spawn server for remote protocol commands
  chatModifyVar remoteCtrlSession $ fmap $ \s -> s {hostServer = Just server}
  toView $ CRRemoteCtrlConnected $ remoteCtrlInfo rc True
  _ <- waitCatch server -- wait for the server to finish
  chatWriteVar remoteCtrlSession Nothing
  toView CRRemoteCtrlStopped

handleRemoteCommand :: forall m . ChatMonad m => (ByteString -> m ChatResponse) -> TBQueue ChatResponse -> HTTP2Request -> m ()
handleRemoteCommand execChatCommand remoteOutputQ HTTP2Request {request, reqBody, sendResponse} = do
  logDebug "handleRemoteCommand"
  liftRC (tryRemoteError parseRequest) >>= \case
    Right (getNext, rc) -> do
      chatReadVar currentUser >>= \case
        Nothing -> replyError $ ChatError CENoActiveUser
        Just user -> processCommand user getNext rc `catchChatError` replyError
    Left e -> reply $ RRProtocolError e
  where
    parseRequest :: ExceptT RemoteProtocolError IO (GetChunk, RemoteCommand)
    parseRequest = do
      (header, getNext) <- parseHTTP2Body request reqBody
      (getNext,) <$> liftEitherWith (RPEInvalidJSON . T.pack) (J.eitherDecodeStrict' header)
    replyError = reply . RRChatResponse . CRChatCmdError Nothing
    processCommand :: User -> GetChunk -> RemoteCommand -> m ()
    processCommand user getNext = \case
      RCHello {deviceName = desktopName} -> handleHello desktopName >>= reply
      RCSend {command} -> handleSend execChatCommand command >>= reply
      RCRecv {wait = time} -> handleRecv time remoteOutputQ >>= reply
      RCStoreFile {fileName, fileSize, fileDigest} -> handleStoreFile fileName fileSize fileDigest getNext >>= reply
      RCGetFile {file} -> handleGetFile user file replyWith
    reply :: RemoteResponse -> m ()
    reply = (`replyWith` \_ -> pure ())
    replyWith :: Respond m
    replyWith rr attach =
      liftIO . sendResponse . responseStreaming N.status200 [] $ \send flush -> do
        send $ sizePrefixedEncode rr
        attach send
        flush

type GetChunk = Int -> IO ByteString

type SendChunk = Builder -> IO ()

type Respond m = RemoteResponse -> (SendChunk -> IO ()) -> m ()

liftRC :: ChatMonad m => ExceptT RemoteProtocolError IO a -> m a
liftRC = liftError (ChatErrorRemoteCtrl . RCEProtocolError)

tryRemoteError :: ExceptT RemoteProtocolError IO a -> ExceptT RemoteProtocolError IO (Either RemoteProtocolError a)
tryRemoteError = tryAllErrors (RPEException . tshow)
{-# INLINE tryRemoteError #-}

handleHello :: ChatMonad m => Text -> m RemoteResponse
handleHello desktopName = do
  logInfo $ "Hello from " <> tshow desktopName
  mobileName <- chatReadVar localDeviceName
  encryptFiles <- chatReadVar encryptLocalFiles
  pure RRHello {encoding = localEncoding, deviceName = mobileName, encryptFiles}

handleSend :: ChatMonad m => (ByteString -> m ChatResponse) -> Text -> m RemoteResponse
handleSend execChatCommand command = do
  logDebug $ "Send: " <> tshow command
  -- execChatCommand checks for remote-allowed commands
  -- convert errors thrown in ChatMonad into error responses to prevent aborting the protocol wrapper
  RRChatResponse <$> execChatCommand (encodeUtf8 command) `catchError` (pure . CRChatError Nothing)

handleRecv :: MonadUnliftIO m => Int -> TBQueue ChatResponse -> m RemoteResponse
handleRecv time events = do
  logDebug $ "Recv: " <> tshow time
  RRChatEvent <$> (timeout time . atomically $ readTBQueue events)

-- TODO this command could remember stored files and return IDs to allow removing files that are not needed.
-- Also, there should be some process removing unused files uploaded to remote host (possibly, all unused files).
handleStoreFile :: forall m. ChatMonad m => FilePath -> Word32 -> FileDigest -> GetChunk -> m RemoteResponse
handleStoreFile fileName fileSize fileDigest getChunk =
  either RRProtocolError RRFileStored <$> (chatReadVar filesFolder >>= storeFile)
  where
    storeFile :: Maybe FilePath -> m (Either RemoteProtocolError FilePath)
    storeFile = \case
      Just ff -> takeFileName <$$> storeFileTo ff
      Nothing -> storeFileTo =<< getDefaultFilesFolder
    storeFileTo :: FilePath -> m (Either RemoteProtocolError FilePath)
    storeFileTo dir = liftRC . tryRemoteError $ do
      filePath <- dir `uniqueCombine` fileName
      receiveRemoteFile getChunk fileSize fileDigest filePath
      pure filePath

handleGetFile :: ChatMonad m => User -> RemoteFile -> Respond m -> m ()
handleGetFile User {userId} RemoteFile{userId = commandUserId, fileId, sent, fileSource = cf'@CryptoFile {filePath}} reply = do
  logDebug $ "GetFile: " <> tshow filePath
  unless (userId == commandUserId) $ throwChatError $ CEDifferentActiveUser {commandUserId, activeUserId = userId}
  path <- maybe filePath (</> filePath) <$> chatReadVar filesFolder
  withStore $ \db -> do
    cf <- getLocalCryptoFile db commandUserId fileId sent
    unless (cf == cf') $ throwError $ SEFileNotFound fileId
  liftRC (tryRemoteError $ getFileInfo path) >>= \case
    Left e -> reply (RRProtocolError e) $ \_ -> pure ()
    Right (fileSize, fileDigest) ->
      withFile path ReadMode $ \h ->
        reply RRFile {fileSize, fileDigest} $ \send -> hSendFile h send fileSize

discoverRemoteCtrls :: ChatMonad m => TM.TMap C.KeyHash (TransportHost, Word16) -> m ()
discoverRemoteCtrls discovered = do
  subscribers <- asks multicastSubscribers
  Discovery.withListener subscribers run
  where
    run sock = receive sock >>= process sock

    receive sock =
      Discovery.recvAnnounce sock >>= \case
        (SockAddrInet _sockPort sockAddr, sigAnnBytes) -> case smpDecode sigAnnBytes of
          Right (SignedAnnounce ann _sig) -> pure (sockAddr, ann)
          Left _ -> receive sock -- TODO it is probably better to report errors to view here
        _nonV4 -> receive sock

    process sock (sockAddr, Announce {caFingerprint, serviceAddress=(annAddr, port)}) = do
      unless (annAddr == sockAddr) $ logError "Announced address doesn't match socket address"
      let addr = THIPv4 (hostAddressToTuple sockAddr)
      ifM
        (atomically $ TM.member caFingerprint discovered)
        (logDebug $ "Fingerprint already known: " <> tshow (addr, caFingerprint))
        ( do
            logInfo $ "New fingerprint announced: " <> tshow (addr, caFingerprint)
            atomically $ TM.insert caFingerprint (addr, port) discovered
        )
      -- TODO we check fingerprint for duplicate where id doesn't matter - to prevent re-insert - and don't check to prevent duplicate events,
      -- so UI now will have to check for duplicates again
      withStore' (`getRemoteCtrlByFingerprint` caFingerprint) >>= \case
        Nothing -> toView $ CRRemoteCtrlAnnounce caFingerprint -- unknown controller, ui "register" action required
        -- TODO Maybe Bool is very confusing - the intent is very unclear here
        Just found@RemoteCtrl {remoteCtrlId, accepted = storedChoice} -> case storedChoice of
          Nothing -> toView $ CRRemoteCtrlFound $ remoteCtrlInfo found False -- first-time controller, ui "accept" action required
          Just False -> run sock -- restart, skipping a rejected item
          Just True ->
            chatReadVar remoteCtrlSession >>= \case
              Nothing -> toView . CRChatError Nothing . ChatError $ CEInternalError "Remote host found without running a session"
              Just RemoteCtrlSession {accepted} -> atomically $ void $ tryPutTMVar accepted remoteCtrlId -- previously accepted controller, connect automatically

listRemoteCtrls :: ChatMonad m => m [RemoteCtrlInfo]
listRemoteCtrls = do
  active <-
    chatReadVar remoteCtrlSession
      $>>= \RemoteCtrlSession {accepted} -> atomically $ tryReadTMVar accepted
  map (rcInfo active) <$> withStore' getRemoteCtrls
  where
    rcInfo activeRcId rc@RemoteCtrl {remoteCtrlId} =
      remoteCtrlInfo rc $ activeRcId == Just remoteCtrlId

remoteCtrlInfo :: RemoteCtrl -> Bool -> RemoteCtrlInfo
remoteCtrlInfo RemoteCtrl {remoteCtrlId, displayName, fingerprint, accepted} sessionActive =
  RemoteCtrlInfo {remoteCtrlId, displayName, fingerprint, accepted, sessionActive}

acceptRemoteCtrl :: ChatMonad m => RemoteCtrlId -> m ()
acceptRemoteCtrl rcId = do
  -- TODO check it exists, check the ID is the same as in session
  RemoteCtrlSession {accepted} <- getRemoteCtrlSession
  withStore' $ \db -> markRemoteCtrlResolution db rcId True
  atomically . void $ tryPutTMVar accepted rcId -- the remote host can now proceed with connection

rejectRemoteCtrl :: ChatMonad m => RemoteCtrlId -> m ()
rejectRemoteCtrl rcId = do
  withStore' $ \db -> markRemoteCtrlResolution db rcId False
  RemoteCtrlSession {discoverer, supervisor} <- getRemoteCtrlSession
  cancel discoverer
  cancel supervisor

stopRemoteCtrl :: ChatMonad m => m ()
stopRemoteCtrl = do
  rcs <- getRemoteCtrlSession
  cancelRemoteCtrlSession rcs $ chatWriteVar remoteCtrlSession Nothing

cancelRemoteCtrlSession_ :: MonadUnliftIO m => RemoteCtrlSession -> m ()
cancelRemoteCtrlSession_ rcs = cancelRemoteCtrlSession rcs $ pure ()

cancelRemoteCtrlSession :: MonadUnliftIO m => RemoteCtrlSession -> m () -> m ()
cancelRemoteCtrlSession RemoteCtrlSession {discoverer, supervisor, hostServer} cleanup = do
  cancel discoverer -- may be gone by now
  case hostServer of
    Just host -> cancel host -- supervisor will clean up
    Nothing -> do
      cancel supervisor -- supervisor is blocked until session progresses
      cleanup

deleteRemoteCtrl :: ChatMonad m => RemoteCtrlId -> m ()
deleteRemoteCtrl rcId = do
  checkNoRemoteCtrlSession
  -- TODO check it exists
  withStore' (`deleteRemoteCtrlRecord` rcId)

getRemoteCtrlSession :: ChatMonad m => m RemoteCtrlSession
getRemoteCtrlSession =
  chatReadVar remoteCtrlSession >>= maybe (throwError $ ChatErrorRemoteCtrl RCEInactive) pure

checkNoRemoteCtrlSession :: ChatMonad m => m ()
checkNoRemoteCtrlSession =
  chatReadVar remoteCtrlSession >>= maybe (pure ()) (\_ -> throwError $ ChatErrorRemoteCtrl RCEBusy)

utf8String :: [Char] -> ByteString
utf8String = encodeUtf8 . T.pack
{-# INLINE utf8String #-}
