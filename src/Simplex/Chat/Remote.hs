{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
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
import Crypto.Random (getRandomBytes)
import qualified Data.Aeson as J
import qualified Data.Aeson.Types as JT
import Data.Bifunctor (second)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64.URL as B64U
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Char8 as B
import Data.Functor (($>))
import Data.List.NonEmpty (nonEmpty)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Word (Word32)
import qualified Network.HTTP.Types as N
import Network.HTTP2.Server (responseStreaming)
import qualified Paths_simplex_chat as SC
import Simplex.Chat.Archive (archiveFilesFolder)
import Simplex.Chat.Controller
import Simplex.Chat.Files
import Simplex.Chat.Messages (chatNameStr)
import Simplex.Chat.Remote.AppVersion
import Simplex.Chat.Remote.Protocol
import Simplex.Chat.Remote.RevHTTP (attachHTTP2Server, attachRevHTTP2Client)
import Simplex.Chat.Remote.Transport
import Simplex.Chat.Remote.Types
import Simplex.Chat.Store.Files
import Simplex.Chat.Store.Remote
import Simplex.Chat.Store.Shared
import Simplex.Chat.Types
import Simplex.Chat.Util (encryptFile)
import Simplex.FileTransfer.Description (FileDigest (..))
import Simplex.Messaging.Agent
import Simplex.Messaging.Agent.Protocol (AgentErrorType (RCP))
import Simplex.Messaging.Crypto.File (CryptoFile (..), CryptoFileArgs (..))
import qualified Simplex.Messaging.Crypto.File as CF
import Simplex.Messaging.Encoding.String (StrEncoding (..))
import qualified Simplex.Messaging.TMap as TM
import Simplex.Messaging.Transport (TLS, closeConnection, tlsUniq)
import Simplex.Messaging.Transport.HTTP2.Client (HTTP2ClientError, closeHTTP2Client)
import Simplex.Messaging.Transport.HTTP2.Server (HTTP2Request (..))
import Simplex.Messaging.Util
import Simplex.RemoteControl.Client
import Simplex.RemoteControl.Invitation (RCInvitation (..), RCSignedInvitation (..), RCVerifiedInvitation (..), verifySignedInvitation)
import Simplex.RemoteControl.Types
import System.FilePath (takeFileName, (</>))
import UnliftIO
import UnliftIO.Concurrent (forkIO)
import UnliftIO.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, removeDirectoryRecursive, renameFile)

-- when acting as host
minRemoteCtrlVersion :: AppVersion
minRemoteCtrlVersion = AppVersion [5, 4, 0, 3]

-- when acting as controller
minRemoteHostVersion :: AppVersion
minRemoteHostVersion = AppVersion [5, 4, 0, 3]

currentAppVersion :: AppVersion
currentAppVersion = AppVersion SC.version

ctrlAppVersionRange :: AppVersionRange
ctrlAppVersionRange = mkAppVersionRange minRemoteHostVersion currentAppVersion

hostAppVersionRange :: AppVersionRange
hostAppVersionRange = mkAppVersionRange minRemoteCtrlVersion currentAppVersion

networkIOTimeout :: Int
networkIOTimeout = 15000000

discoveryTimeout :: Int
discoveryTimeout = 60000000

-- * Desktop side

getRemoteHostClient :: ChatMonad m => RemoteHostId -> m RemoteHostClient
getRemoteHostClient rhId = do
  sessions <- asks remoteHostSessions
  liftIOEither . atomically $ TM.lookup rhKey sessions >>= \case
    Just (_, RHSessionConnected {rhClient}) -> pure $ Right rhClient
    Just _ -> pure . Left $ ChatErrorRemoteHost rhKey RHEBadState
    Nothing -> pure . Left $ ChatErrorRemoteHost rhKey RHEMissing
  where
    rhKey = RHId rhId

-- | Transition session state with a 'RHNew' ID to an assigned 'RemoteHostId'
-- XXX: Old RHStateKey becomes invalid
setNewRemoteHostId :: ChatMonad m => RHStateKey -> RemoteHostId -> m ()
setNewRemoteHostId (sessionSeq, rhKey) rhId = do
  unless (rhKey == RHNew) $ throwChatError $ CEInternalError "setNewRemoteHostId key must be RHNew"
  sessions <- asks remoteHostSessions
  liftIOEither . atomically $ do
    TM.lookup RHNew sessions >>= \case
      Nothing -> err RHEMissing
      Just (stateSeq, _) | stateSeq /= sessionSeq -> err RHEBadState -- RHEGhostSession
      Just session -> Right () <$ modifyTVar' sessions (M.insert (RHId rhId) session . M.delete RHNew)
  where
    err = pure . Left . ChatErrorRemoteHost rhKey

startRemoteHostSession :: ChatMonad m => RHKey -> m RHStateKey
startRemoteHostSession rhKey = do
  sessions <- asks remoteHostSessions
  nextSessionSeq <- asks remoteSessionSeq
  liftIOEither . atomically $
    TM.lookup rhKey sessions >>= \case
      Just _ -> pure . Left $ ChatErrorRemoteHost rhKey RHEBusy
      Nothing -> do
        sessionSeq <- stateTVar nextSessionSeq $ \s -> (s, s + 1)
        Right (sessionSeq, rhKey) <$ TM.insert rhKey (sessionSeq, RHSessionStarting) sessions

remoteHostSessionState :: ChatMonad m => RHStateKey -> (RemoteHostSession -> Maybe (a, RemoteHostSession)) -> m a
remoteHostSessionState (sseq, rhKey) f = do
  sessions <- asks remoteHostSessions
  liftIOEither . atomically $
    TM.lookup rhKey sessions >>= \case
      Nothing -> err RHEMissing
      Just (oldSeq, _) | oldSeq /= sseq -> err RHEBadState -- XXX: RHEGhostSession or something like that?
      Just (_, oldState) -> case f oldState of
        Nothing -> err RHEBadState
        Just (r, newState) -> Right r <$ TM.insert rhKey (sseq, newState) sessions
  where
    err = pure . Left . ChatErrorRemoteHost rhKey

startRemoteHost :: ChatMonad m => Maybe (RemoteHostId, Bool) -> m (Maybe RemoteHostInfo, RCSignedInvitation)
startRemoteHost rh_ = do
  (rhKey, multicast, remoteHost_, pairing) <- case rh_ of
    Just (rhId, multicast) -> do
      rh@RemoteHost {hostPairing} <- withStore $ \db -> getRemoteHost db rhId
      pure (RHId rhId, multicast, Just $ remoteHostInfo rh $ Just RHSStarting, hostPairing) -- get from the database, start multicast if requested
    Nothing -> (RHNew,False,Nothing,) <$> rcNewHostPairing
  stKey <- startRemoteHostSession rhKey
  ctrlAppInfo <- mkCtrlAppInfo
  (invitation, rchClient, vars) <- withAgent $ \a -> rcConnectHost a pairing (J.toJSON ctrlAppInfo) multicast
  cmdOk <- newEmptyTMVarIO
  rhsWaitSession <- async $ do
    rhKeyVar <- newTVarIO rhKey
    atomically $ takeTMVar cmdOk
    handleHostError (fst stKey) rhKeyVar $ waitForHostSession remoteHost_ stKey rhKeyVar vars
  let rhs = RHPendingSession {rhKey, rchClient, rhsWaitSession, remoteHost_}
  remoteHostSessionState stKey $ \case
    RHSessionStarting -> Just ((), RHSessionConnecting inv rhs)
      where inv = decodeLatin1 $ strEncode invitation
    _ -> Nothing
  (remoteHost_, invitation) <$ atomically (putTMVar cmdOk ())
  where
    mkCtrlAppInfo = do
      deviceName <- chatReadVar localDeviceName
      pure CtrlAppInfo {appVersionRange = ctrlAppVersionRange, deviceName}
    parseHostAppInfo :: RCHostHello -> ExceptT RemoteHostError IO HostAppInfo
    parseHostAppInfo RCHostHello {app = hostAppInfo} = do
      hostInfo@HostAppInfo {appVersion, encoding} <-
        liftEitherWith (RHEProtocolError . RPEInvalidJSON) $ JT.parseEither J.parseJSON hostAppInfo
      unless (isAppCompatible appVersion ctrlAppVersionRange) $ throwError $ RHEBadVersion appVersion
      when (encoding == PEKotlin && localEncoding == PESwift) $ throwError $ RHEProtocolError RPEIncompatibleEncoding
      pure hostInfo
    handleHostError :: ChatMonad m => SessionSeq -> TVar RHKey -> m () -> m ()
    handleHostError sessSeq rhKeyVar action = action `catchChatError` \err -> do
      logError $ "startRemoteHost.waitForHostSession crashed: " <> tshow err
      readTVarIO rhKeyVar >>= cancelRemoteHostSession (Just sessSeq)
    waitForHostSession :: ChatMonad m => Maybe RemoteHostInfo -> RHStateKey -> TVar RHKey -> RCStepTMVar (ByteString, TLS, RCStepTMVar (RCHostSession, RCHostHello, RCHostPairing)) -> m ()
    waitForHostSession remoteHost_ stateKey@(_, rhKey) rhKeyVar vars = do
      (sessId, tls, vars') <- timeoutThrow (ChatErrorRemoteHost rhKey RHETimeout) 60000000 $ takeRCStep vars
      let sessionCode = verificationCode sessId
      remoteHostSessionState stateKey $ \case
        RHSessionConnecting _inv rhs' -> Just ((), RHSessionPendingConfirmation sessionCode tls rhs')
        _ -> Nothing
      let rh_' = (\rh -> (rh :: RemoteHostInfo) {sessionState = Just RHSPendingConfirmation {sessionCode}}) <$> remoteHost_
      toView $ CRRemoteHostSessionCode {remoteHost_ = rh_', sessionCode}
      (RCHostSession {sessionKeys}, rhHello, pairing') <- timeoutThrow (ChatErrorRemoteHost rhKey RHETimeout) 60000000 $ takeRCStep vars'
      hostInfo@HostAppInfo {deviceName = hostDeviceName} <-
        liftError (ChatErrorRemoteHost rhKey) $ parseHostAppInfo rhHello
      remoteHostSessionState stateKey $ \case
        RHSessionPendingConfirmation _ tls' rhs' -> Just ((), RHSessionConfirmed tls' rhs')
        _ -> Nothing
      rhi@RemoteHostInfo {remoteHostId, storePath} <- upsertRemoteHost pairing' rh_' hostDeviceName stateKey RHSConfirmed {sessionCode}
      let rhKey' = RHId remoteHostId -- rhKey may be invalid after upserting on RHNew
      when (rhKey' /= rhKey) $ do
        atomically $ writeTVar rhKeyVar rhKey'
        toView $ CRNewRemoteHost rhi
      let stateKey' = rhKey' <$ stateKey
      -- set up HTTP transport and remote profile protocol
      disconnected <- toIO $ onDisconnected stateKey'
      httpClient <- liftEitherError (httpError remoteHostId) $ attachRevHTTP2Client disconnected tls
      rhClient <- mkRemoteHostClient httpClient sessionKeys sessId storePath hostInfo
      pollAction <- async $ pollEvents remoteHostId rhClient
      remoteHostSessionState stateKey' $ \case
        RHSessionConfirmed _ RHPendingSession {rchClient} -> Just ((), RHSessionConnected {rchClient, tls, rhClient, pollAction, storePath})
        _ -> Nothing
      chatWriteVar currentRemoteHost $ Just remoteHostId -- this is required for commands to be passed to remote host
      toView $ CRRemoteHostConnected rhi {sessionState = Just RHSConnected {sessionCode}}
    upsertRemoteHost :: ChatMonad m => RCHostPairing -> Maybe RemoteHostInfo -> Text -> RHStateKey -> RemoteHostSessionState -> m RemoteHostInfo
    upsertRemoteHost pairing'@RCHostPairing {knownHost = kh_} rhi_ hostDeviceName stKey state = do
      KnownHostPairing {hostDhPubKey = hostDhPubKey'} <- maybe (throwError . ChatError $ CEInternalError "KnownHost is known after verification") pure kh_
      case rhi_ of
        Nothing -> do
          storePath <- liftIO randomStorePath
          rh@RemoteHost {remoteHostId} <- withStore $ \db -> insertRemoteHost db hostDeviceName storePath pairing' >>= getRemoteHost db
          setNewRemoteHostId stKey remoteHostId
          pure $ remoteHostInfo rh $ Just state
        Just rhi@RemoteHostInfo {remoteHostId} -> do
          withStore' $ \db -> updateHostPairing db remoteHostId hostDeviceName hostDhPubKey'
          pure (rhi :: RemoteHostInfo) {sessionState = Just state}
    onDisconnected :: ChatMonad m => RHStateKey -> m ()
    onDisconnected stKey@(sseq, rhKey) = do
      logDebug $ "HTTP2 client disconnected: " <> tshow stKey
      cancelRemoteHostSession (Just sseq) rhKey
    pollEvents :: ChatMonad m => RemoteHostId -> RemoteHostClient -> m ()
    pollEvents rhId rhClient = do
      oq <- asks outputQ
      forever $ do
        r_ <- liftRH rhId $ remoteRecv rhClient 10000000
        forM r_ $ \r -> atomically $ writeTBQueue oq (Nothing, Just rhId, r)
    httpError :: RemoteHostId -> HTTP2ClientError -> ChatError
    httpError rhId = ChatErrorRemoteHost (RHId rhId) . RHEProtocolError . RPEHTTP2 . tshow

closeRemoteHost :: ChatMonad m => RHKey -> m ()
closeRemoteHost rhKey = do
  logNote $ "Closing remote host session for " <> tshow rhKey
  cancelRemoteHostSession Nothing rhKey
  -- cancelRemoteHostSession False rhKey

cancelRemoteHostSession :: ChatMonad m => Maybe SessionSeq -> RHKey -> m ()
cancelRemoteHostSession sseq_ rhKey = do
  sessions <- asks remoteHostSessions
  crh <- asks currentRemoteHost
  deregistered <- atomically $
    TM.lookup rhKey sessions >>= \case
      Nothing -> pure Nothing
      Just (sessSeq, _) | maybe False (/= sessSeq) sseq_ -> pure Nothing -- ignore cancel from a ghost session handler
      Just (_, rhs) -> do
        TM.delete rhKey sessions
        modifyTVar' crh $ \cur -> if (RHId <$> cur) == Just rhKey then Nothing else cur -- only wipe the closing RH
        pure $ Just rhs
  forM_ deregistered $ \session -> do
    liftIO $ cancelRemoteHost handlingError session `catchAny` (logError . tshow)
    when handlingError $ toView $ CRRemoteHostStopped rhId_
  where
    handlingError = isJust sseq_
    rhId_ = case rhKey of
      RHNew -> Nothing
      RHId rhId -> Just rhId

cancelRemoteHost :: Bool -> RemoteHostSession -> IO ()
cancelRemoteHost handlingError = \case
  RHSessionStarting -> pure ()
  RHSessionConnecting _inv rhs -> cancelPendingSession rhs
  RHSessionPendingConfirmation _sessCode tls rhs -> do
    cancelPendingSession rhs
    closeConnection tls
  RHSessionConfirmed tls rhs -> do
    cancelPendingSession rhs
    closeConnection tls
  RHSessionConnected {rchClient, tls, rhClient = RemoteHostClient {httpClient}, pollAction} -> do
    uninterruptibleCancel pollAction
    cancelHostClient rchClient `catchAny` (logError . tshow)
    closeConnection tls `catchAny` (logError . tshow)
    unless handlingError $ closeHTTP2Client httpClient `catchAny` (logError . tshow)
  where
    cancelPendingSession RHPendingSession {rchClient, rhsWaitSession} = do
      unless handlingError $ uninterruptibleCancel rhsWaitSession `catchAny` (logError . tshow)
      cancelHostClient rchClient `catchAny` (logError . tshow)

-- | Generate a random 16-char filepath without / in it by using base64url encoding.
randomStorePath :: IO FilePath
randomStorePath = B.unpack . B64U.encode <$> getRandomBytes 12

listRemoteHosts :: ChatMonad m => m [RemoteHostInfo]
listRemoteHosts = do
  sessions <- chatReadVar remoteHostSessions
  map (rhInfo sessions) <$> withStore' getRemoteHosts
  where
    rhInfo sessions rh@RemoteHost {remoteHostId} =
      remoteHostInfo rh $ rhsSessionState . snd <$> M.lookup (RHId remoteHostId) sessions

switchRemoteHost :: ChatMonad m => Maybe RemoteHostId -> m (Maybe RemoteHostInfo)
switchRemoteHost rhId_ = do
  rhi_ <- forM rhId_ $ \rhId -> do
    let rhKey = RHId rhId
    rh <- withStore (`getRemoteHost` rhId)
    sessions <- chatReadVar remoteHostSessions
    case M.lookup rhKey sessions of
      Just (_, RHSessionConnected {tls}) -> pure $ remoteHostInfo rh $ Just RHSConnected {sessionCode = tlsSessionCode tls}
      _ -> throwError $ ChatErrorRemoteHost rhKey RHEInactive
  rhi_ <$ chatWriteVar currentRemoteHost rhId_

remoteHostInfo :: RemoteHost -> Maybe RemoteHostSessionState -> RemoteHostInfo
remoteHostInfo RemoteHost {remoteHostId, storePath, hostDeviceName} sessionState =
  RemoteHostInfo {remoteHostId, storePath, hostDeviceName, sessionState}

deleteRemoteHost :: ChatMonad m => RemoteHostId -> m ()
deleteRemoteHost rhId = do
  RemoteHost {storePath} <- withStore (`getRemoteHost` rhId)
  chatReadVar remoteHostsFolder >>= \case
    Just baseDir -> do
      let hostStore = baseDir </> storePath
      logInfo $ "removing host store at " <> tshow hostStore
      whenM (doesDirectoryExist hostStore) $ removeDirectoryRecursive hostStore
    Nothing -> logWarn "Local file store not available while deleting remote host"
  withStore' (`deleteRemoteHostRecord` rhId)

storeRemoteFile :: forall m. ChatMonad m => RemoteHostId -> Maybe Bool -> FilePath -> m CryptoFile
storeRemoteFile rhId encrypted_ localPath = do
  c@RemoteHostClient {encryptHostFiles, storePath} <- getRemoteHostClient rhId
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
  c@RemoteHostClient {storePath} <- getRemoteHostClient rhId
  dir <- (</> storePath </> archiveFilesFolder) <$> (maybe getDefaultFilesFolder pure =<< chatReadVar remoteHostsFolder)
  createDirectoryIfMissing True dir
  liftRH rhId $ remoteGetFile c dir rf

processRemoteCommand :: ChatMonad m => RemoteHostId -> RemoteHostClient -> ChatCommand -> ByteString -> m ChatResponse
processRemoteCommand remoteHostId c cmd s = case cmd of
  SendFile chatName f -> sendFile "/f" chatName f
  SendImage chatName f -> sendFile "/img" chatName f
  _ -> liftRH remoteHostId $ remoteSend c s
  where
    sendFile cmdName chatName (CryptoFile path cfArgs) = do
      -- don't encrypt in host if already encrypted locally
      CryptoFile path' cfArgs' <- storeRemoteFile remoteHostId (cfArgs $> False) path
      let f = CryptoFile path' (cfArgs <|> cfArgs') -- use local or host encryption
      liftRH remoteHostId $ remoteSend c $ B.unwords [cmdName, B.pack (chatNameStr chatName), cryptoFileStr f]
    cryptoFileStr CryptoFile {filePath, cryptoArgs} =
      maybe "" (\(CFArgs key nonce) -> "key=" <> strEncode key <> " nonce=" <> strEncode nonce <> " ") cryptoArgs
        <> encodeUtf8 (T.pack filePath)

liftRH :: ChatMonad m => RemoteHostId -> ExceptT RemoteProtocolError IO a -> m a
liftRH rhId = liftError (ChatErrorRemoteHost (RHId rhId) . RHEProtocolError)

-- * Mobile side

-- ** QR/link

-- | Use provided OOB link as an annouce
connectRemoteCtrlURI :: ChatMonad m => RCSignedInvitation -> m (Maybe RemoteCtrlInfo, CtrlAppInfo)
connectRemoteCtrlURI signedInv = handleCtrlError "connectRemoteCtrl" $ do
  verifiedInv <- maybe (throwError $ ChatErrorRemoteCtrl RCEBadInvitation) pure $ verifySignedInvitation signedInv
  withRemoteCtrlSession_ $ maybe (Right ((), Just RCSessionStarting)) (\_ -> Left $ ChatErrorRemoteCtrl RCEBusy)
  connectRemoteCtrl verifiedInv

-- ** Multicast

findKnownRemoteCtrl :: ChatMonad m => m ()
findKnownRemoteCtrl = handleCtrlError "findKnownRemoteCtrl" $ do
  knownCtrls <- withStore' getRemoteCtrls
  pairings <- case nonEmpty knownCtrls of
    Nothing -> throwError $ ChatErrorRemoteCtrl RCENoKnownControllers
    Just ne -> pure $ fmap (\RemoteCtrl {ctrlPairing} -> ctrlPairing) ne
  withRemoteCtrlSession_ $ maybe (Right ((), Just RCSessionStarting)) (\_ -> Left $ ChatErrorRemoteCtrl RCEBusy)
  foundCtrl <- newEmptyTMVarIO
  cmdOk <- newEmptyTMVarIO
  action <- async $ handleCtrlError "findKnownRemoteCtrl.discover" $ do
    atomically $ takeTMVar cmdOk
    (RCCtrlPairing {ctrlFingerprint}, inv) <- timeoutThrow (ChatErrorRemoteCtrl RCETimeout) discoveryTimeout . withAgent $ \a -> rcDiscoverCtrl a pairings
    rc <- withStore' (`getRemoteCtrlByFingerprint` ctrlFingerprint) >>= \case
      Nothing -> throwChatError $ CEInternalError "connecting with a stored ctrl"
      Just rc  -> pure rc
    atomically $ putTMVar foundCtrl (rc, inv)
    toView CRRemoteCtrlFound {remoteCtrl = remoteCtrlInfo rc (Just RCSSearching)}
  withRemoteCtrlSession $ \case
    RCSessionStarting -> Right ((), RCSessionSearching {action, foundCtrl})
    _ -> Left $ ChatErrorRemoteCtrl RCEBadState
  atomically $ putTMVar cmdOk ()

confirmRemoteCtrl :: ChatMonad m => RemoteCtrlId -> m (RemoteCtrlInfo, CtrlAppInfo)
confirmRemoteCtrl rcId = do
  (listener, found) <- withRemoteCtrlSession $ \case
    RCSessionSearching {action, foundCtrl} -> Right ((action, foundCtrl), RCSessionStarting) -- drop intermediate "Searching" state so connectRemoteCtrl can proceed
    _ -> throwError $ ChatErrorRemoteCtrl RCEBadState
  uninterruptibleCancel listener
  (RemoteCtrl{remoteCtrlId = foundRcId}, verifiedInv) <- atomically $ takeTMVar found
  unless (rcId == foundRcId) $ throwError $ ChatErrorRemoteCtrl RCEBadController
  connectRemoteCtrl verifiedInv >>= \case
    (Nothing, _) -> throwChatError $ CEInternalError "connecting with a stored ctrl"
    (Just rci, appInfo) -> pure (rci, appInfo)

-- ** Common

connectRemoteCtrl :: ChatMonad m => RCVerifiedInvitation -> m (Maybe RemoteCtrlInfo, CtrlAppInfo)
connectRemoteCtrl verifiedInv@(RCVerifiedInvitation inv@RCInvitation {ca, app}) = handleCtrlError "connectRemoteCtrl" $ do
  (ctrlInfo@CtrlAppInfo {deviceName = ctrlDeviceName}, v) <- parseCtrlAppInfo app
  rc_ <- withStore' $ \db -> getRemoteCtrlByFingerprint db ca
  mapM_ (validateRemoteCtrl inv) rc_
  hostAppInfo <- getHostAppInfo v
  (rcsClient, vars) <- timeoutThrow (ChatErrorRemoteCtrl RCETimeout) networkIOTimeout . withAgent $ \a ->
    rcConnectCtrl a verifiedInv (ctrlPairing <$> rc_) (J.toJSON hostAppInfo)
  cmdOk <- newEmptyTMVarIO
  rcsWaitSession <- async $ do
    atomically $ takeTMVar cmdOk
    handleCtrlError "waitForCtrlSession" $ waitForCtrlSession rc_ ctrlDeviceName rcsClient vars
  updateRemoteCtrlSession $ \case
    RCSessionStarting -> Right RCSessionConnecting {remoteCtrlId_ = remoteCtrlId' <$> rc_, rcsClient, rcsWaitSession}
    _ -> Left $ ChatErrorRemoteCtrl RCEBadState
  atomically $ putTMVar cmdOk ()
  pure ((`remoteCtrlInfo` Just RCSConnecting) <$> rc_, ctrlInfo)
  where
    validateRemoteCtrl RCInvitation {idkey} RemoteCtrl {ctrlPairing = RCCtrlPairing {idPubKey}} =
      unless (idkey == idPubKey) $ throwError $ ChatErrorRemoteCtrl $ RCEProtocolError $ PRERemoteControl RCEIdentity
    waitForCtrlSession :: ChatMonad m => Maybe RemoteCtrl -> Text -> RCCtrlClient -> RCStepTMVar (ByteString, TLS, RCStepTMVar (RCCtrlSession, RCCtrlPairing)) -> m ()
    waitForCtrlSession rc_ ctrlName rcsClient vars = do
      (uniq, tls, rcsWaitConfirmation) <- timeoutThrow (ChatErrorRemoteCtrl RCETimeout) networkIOTimeout $ takeRCStep vars
      let sessionCode = verificationCode uniq
      updateRemoteCtrlSession $ \case
        RCSessionConnecting {rcsWaitSession} ->
          let remoteCtrlId_ = remoteCtrlId' <$> rc_
           in Right RCSessionPendingConfirmation {remoteCtrlId_, ctrlDeviceName = ctrlName, rcsClient, tls, sessionCode, rcsWaitSession, rcsWaitConfirmation}
        _ -> Left $ ChatErrorRemoteCtrl RCEBadState
      toView CRRemoteCtrlSessionCode {remoteCtrl_ = (`remoteCtrlInfo` Just RCSPendingConfirmation {sessionCode}) <$> rc_, sessionCode}
    parseCtrlAppInfo ctrlAppInfo = do
      ctrlInfo@CtrlAppInfo {appVersionRange} <-
        liftEitherWith (const $ ChatErrorRemoteCtrl RCEBadInvitation) $ JT.parseEither J.parseJSON ctrlAppInfo
      v <- case compatibleAppVersion hostAppVersionRange appVersionRange of
        Just (AppCompatible v) -> pure v
        Nothing -> throwError $ ChatErrorRemoteCtrl $ RCEBadVersion $ maxVersion appVersionRange
      pure (ctrlInfo, v)
    getHostAppInfo appVersion = do
      hostDeviceName <- chatReadVar localDeviceName
      encryptFiles <- chatReadVar encryptLocalFiles
      pure HostAppInfo {appVersion, deviceName = hostDeviceName, encoding = localEncoding, encryptFiles}

handleRemoteCommand :: forall m. ChatMonad m => (ByteString -> m ChatResponse) -> RemoteCrypto -> TBQueue ChatResponse -> HTTP2Request -> m ()
handleRemoteCommand execChatCommand encryption remoteOutputQ HTTP2Request {request, reqBody, sendResponse} = do
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
      (header, getNext) <- parseDecryptHTTP2Body encryption request reqBody
      (getNext,) <$> liftEitherWith RPEInvalidJSON (J.eitherDecode header)
    replyError = reply . RRChatResponse . CRChatCmdError Nothing
    processCommand :: User -> GetChunk -> RemoteCommand -> m ()
    processCommand user getNext = \case
      RCSend {command} -> handleSend execChatCommand command >>= reply
      RCRecv {wait = time} -> handleRecv time remoteOutputQ >>= reply
      RCStoreFile {fileName, fileSize, fileDigest} -> handleStoreFile encryption fileName fileSize fileDigest getNext >>= reply
      RCGetFile {file} -> handleGetFile encryption user file replyWith
    reply :: RemoteResponse -> m ()
    reply = (`replyWith` \_ -> pure ())
    replyWith :: Respond m
    replyWith rr attach = do
      resp <- liftRC $ encryptEncodeHTTP2Body encryption $ J.encode rr
      liftIO . sendResponse . responseStreaming N.status200 [] $ \send flush -> do
        send resp
        attach send
        flush

takeRCStep :: ChatMonad m => RCStepTMVar a -> m a
takeRCStep = liftEitherError (\e -> ChatErrorAgent {agentError = RCP e, connectionEntity_ = Nothing}) . atomically . takeTMVar

type GetChunk = Int -> IO ByteString

type SendChunk = Builder -> IO ()

type Respond m = RemoteResponse -> (SendChunk -> IO ()) -> m ()

liftRC :: ChatMonad m => ExceptT RemoteProtocolError IO a -> m a
liftRC = liftError (ChatErrorRemoteCtrl . RCEProtocolError)

tryRemoteError :: ExceptT RemoteProtocolError IO a -> ExceptT RemoteProtocolError IO (Either RemoteProtocolError a)
tryRemoteError = tryAllErrors (RPEException . tshow)
{-# INLINE tryRemoteError #-}

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
handleStoreFile :: forall m. ChatMonad m => RemoteCrypto -> FilePath -> Word32 -> FileDigest -> GetChunk -> m RemoteResponse
handleStoreFile encryption fileName fileSize fileDigest getChunk =
  either RRProtocolError RRFileStored <$> (chatReadVar filesFolder >>= storeFile)
  where
    storeFile :: Maybe FilePath -> m (Either RemoteProtocolError FilePath)
    storeFile = \case
      Just ff -> takeFileName <$$> storeFileTo ff
      Nothing -> storeFileTo =<< getDefaultFilesFolder
    storeFileTo :: FilePath -> m (Either RemoteProtocolError FilePath)
    storeFileTo dir = liftRC . tryRemoteError $ do
      filePath <- dir `uniqueCombine` fileName
      receiveEncryptedFile encryption getChunk fileSize fileDigest filePath
      pure filePath

handleGetFile :: ChatMonad m => RemoteCrypto -> User -> RemoteFile -> Respond m -> m ()
handleGetFile encryption User {userId} RemoteFile {userId = commandUserId, fileId, sent, fileSource = cf'@CryptoFile {filePath}} reply = do
  logDebug $ "GetFile: " <> tshow filePath
  unless (userId == commandUserId) $ throwChatError $ CEDifferentActiveUser {commandUserId, activeUserId = userId}
  path <- maybe filePath (</> filePath) <$> chatReadVar filesFolder
  withStore $ \db -> do
    cf <- getLocalCryptoFile db commandUserId fileId sent
    unless (cf == cf') $ throwError $ SEFileNotFound fileId
  liftRC (tryRemoteError $ getFileInfo path) >>= \case
    Left e -> reply (RRProtocolError e) $ \_ -> pure ()
    Right (fileSize, fileDigest) ->
      withFile path ReadMode $ \h -> do
        encFile <- liftRC $ prepareEncryptedFile encryption (h, fileSize)
        reply RRFile {fileSize, fileDigest} $ sendEncryptedFile encFile

listRemoteCtrls :: ChatMonad m => m [RemoteCtrlInfo]
listRemoteCtrls = do
  session <- chatReadVar remoteCtrlSession
  let rcId = sessionRcId =<< session
      sessState = rcsSessionState <$> session
  map (rcInfo rcId sessState) <$> withStore' getRemoteCtrls
  where
    rcInfo :: Maybe RemoteCtrlId -> Maybe RemoteCtrlSessionState -> RemoteCtrl -> RemoteCtrlInfo
    rcInfo rcId sessState rc@RemoteCtrl {remoteCtrlId} =
      remoteCtrlInfo rc $ if rcId == Just remoteCtrlId then sessState else Nothing
    sessionRcId = \case
      RCSessionConnecting {remoteCtrlId_} -> remoteCtrlId_
      RCSessionPendingConfirmation {remoteCtrlId_} -> remoteCtrlId_
      RCSessionConnected {remoteCtrlId} -> Just remoteCtrlId
      _ -> Nothing

remoteCtrlInfo :: RemoteCtrl -> Maybe RemoteCtrlSessionState -> RemoteCtrlInfo
remoteCtrlInfo RemoteCtrl {remoteCtrlId, ctrlDeviceName} sessionState =
  RemoteCtrlInfo {remoteCtrlId, ctrlDeviceName, sessionState}

-- | Take a look at emoji of tlsunique, commit pairing, and start session server
verifyRemoteCtrlSession :: ChatMonad m => (ByteString -> m ChatResponse) -> Text -> m RemoteCtrlInfo
verifyRemoteCtrlSession execChatCommand sessCode' = handleCtrlError "verifyRemoteCtrlSession" $ do
  (client, ctrlName, sessionCode, vars) <-
    getRemoteCtrlSession >>= \case
      RCSessionPendingConfirmation {rcsClient, ctrlDeviceName = ctrlName, sessionCode, rcsWaitConfirmation} -> pure (rcsClient, ctrlName, sessionCode, rcsWaitConfirmation)
      _ -> throwError $ ChatErrorRemoteCtrl RCEBadState
  let verified = sameVerificationCode sessCode' sessionCode
  timeoutThrow (ChatErrorRemoteCtrl RCETimeout) networkIOTimeout . liftIO $ confirmCtrlSession client verified -- signal verification result before crashing
  unless verified $ throwError $ ChatErrorRemoteCtrl $ RCEProtocolError PRESessionCode
  (rcsSession@RCCtrlSession {tls, sessionKeys}, rcCtrlPairing) <- timeoutThrow (ChatErrorRemoteCtrl RCETimeout) networkIOTimeout $ takeRCStep vars
  rc@RemoteCtrl {remoteCtrlId} <- upsertRemoteCtrl ctrlName rcCtrlPairing
  remoteOutputQ <- asks (tbqSize . config) >>= newTBQueueIO
  encryption <- mkCtrlRemoteCrypto sessionKeys $ tlsUniq tls
  http2Server <- async $ attachHTTP2Server tls $ handleRemoteCommand execChatCommand encryption remoteOutputQ
  void . forkIO $ monitor http2Server
  withRemoteCtrlSession $ \case
    RCSessionPendingConfirmation {} -> Right ((), RCSessionConnected {remoteCtrlId, rcsClient = client, rcsSession, tls, http2Server, remoteOutputQ})
    _ -> Left $ ChatErrorRemoteCtrl RCEBadState
  pure $ remoteCtrlInfo rc $ Just RCSConnected {sessionCode = tlsSessionCode tls}
  where
    upsertRemoteCtrl :: ChatMonad m => Text -> RCCtrlPairing -> m RemoteCtrl
    upsertRemoteCtrl ctrlName rcCtrlPairing = withStore $ \db -> do
      rc_ <- liftIO $ getRemoteCtrlByFingerprint db (ctrlFingerprint rcCtrlPairing)
      case rc_ of
        Nothing -> insertRemoteCtrl db ctrlName rcCtrlPairing >>= getRemoteCtrl db
        Just rc@RemoteCtrl {ctrlPairing} -> do
          let dhPrivKey' = dhPrivKey rcCtrlPairing
          liftIO $ updateRemoteCtrl db rc ctrlName dhPrivKey'
          pure rc {ctrlDeviceName = ctrlName, ctrlPairing = ctrlPairing {dhPrivKey = dhPrivKey'}}
    monitor :: ChatMonad m => Async () -> m ()
    monitor server = do
      res <- waitCatch server
      logInfo $ "HTTP2 server stopped: " <> tshow res
      cancelActiveRemoteCtrl True

stopRemoteCtrl :: ChatMonad m => m ()
stopRemoteCtrl = cancelActiveRemoteCtrl False

handleCtrlError :: ChatMonad m => Text -> m a -> m a
handleCtrlError name action =
  action `catchChatError` \e -> do
    logError $ name <> " remote ctrl error: " <> tshow e
    cancelActiveRemoteCtrl True
    throwError e

cancelActiveRemoteCtrl :: ChatMonad m => Bool -> m ()
cancelActiveRemoteCtrl handlingError = handleAny (logError . tshow) $ do
  session_ <- withRemoteCtrlSession_ (\s -> pure (s, Nothing))
  forM_ session_ $ \session -> do
    liftIO $ cancelRemoteCtrl handlingError session
    when handlingError $ toView CRRemoteCtrlStopped

cancelRemoteCtrl :: Bool -> RemoteCtrlSession -> IO ()
cancelRemoteCtrl handlingError = \case
  RCSessionStarting -> pure ()
  RCSessionSearching {action} -> uninterruptibleCancel action
  RCSessionConnecting {rcsClient, rcsWaitSession} -> do
    unless handlingError $ uninterruptibleCancel rcsWaitSession
    cancelCtrlClient rcsClient
  RCSessionPendingConfirmation {rcsClient, tls, rcsWaitSession} -> do
    unless handlingError $ uninterruptibleCancel rcsWaitSession
    cancelCtrlClient rcsClient
    closeConnection tls
  RCSessionConnected {rcsClient, tls, http2Server} -> do
    unless handlingError $ uninterruptibleCancel http2Server
    cancelCtrlClient rcsClient
    closeConnection tls

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

withRemoteCtrlSession :: ChatMonad m => (RemoteCtrlSession -> Either ChatError (a, RemoteCtrlSession)) -> m a
withRemoteCtrlSession state = withRemoteCtrlSession_ $ maybe (Left $ ChatErrorRemoteCtrl RCEInactive) ((second . second) Just . state)

-- | Atomically process controller state wrt. specific remote ctrl session
withRemoteCtrlSession_ :: ChatMonad m => (Maybe RemoteCtrlSession -> Either ChatError (a, Maybe RemoteCtrlSession)) -> m a
withRemoteCtrlSession_ state = do
  session <- asks remoteCtrlSession
  r <-
    atomically $ stateTVar session $ \s ->
      case state s of
        Left e -> (Left e, s)
        Right (a, s') -> (Right a, s')
  liftEither r

updateRemoteCtrlSession :: ChatMonad m => (RemoteCtrlSession -> Either ChatError RemoteCtrlSession) -> m ()
updateRemoteCtrlSession state = withRemoteCtrlSession $ fmap ((),) . state

utf8String :: [Char] -> ByteString
utf8String = encodeUtf8 . T.pack
{-# INLINE utf8String #-}
