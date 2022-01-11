{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}

module Simplex.Chat where

import Control.Applicative (optional, (<|>))
import Control.Concurrent.STM (stateTVar)
import Control.Logger.Simple
import Control.Monad.Except
import Control.Monad.IO.Unlift
import Control.Monad.Reader
import Crypto.Random (drgNew)
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.Bifunctor (first)
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Char (isSpace)
import Data.Functor (($>))
import Data.Int (Int64)
import Data.List (find)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word32)
import Simplex.Chat.Controller
import Simplex.Chat.Help
import Simplex.Chat.Input
import Simplex.Chat.Notification
import Simplex.Chat.Options (ChatOpts (..))
import Simplex.Chat.Protocol
import Simplex.Chat.Store
import Simplex.Chat.Styled (plain)
import Simplex.Chat.Terminal
import Simplex.Chat.Types
import Simplex.Chat.Util (ifM, unlessM, whenM)
import Simplex.Chat.View
import Simplex.Messaging.Agent
import Simplex.Messaging.Agent.Env.SQLite (AgentConfig (..), defaultAgentConfig)
import Simplex.Messaging.Agent.Protocol
import qualified Simplex.Messaging.Crypto as C
import Simplex.Messaging.Encoding
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Parsers (parseAll)
import Simplex.Messaging.Protocol (MsgBody)
import qualified Simplex.Messaging.Protocol as SMP
import Simplex.Messaging.Util (raceAny_, tryError)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (combine, splitExtensions, takeFileName)
import System.IO (Handle, IOMode (..), SeekMode (..), hFlush, openFile, stdout)
import Text.Read (readMaybe)
import UnliftIO.Async (race_)
import UnliftIO.Concurrent (forkIO, threadDelay)
import UnliftIO.Directory (doesDirectoryExist, doesFileExist, getFileSize, getHomeDirectory, getTemporaryDirectory)
import qualified UnliftIO.Exception as E
import UnliftIO.IO (hClose, hSeek, hTell)
import UnliftIO.STM

data ChatCommand
  = ChatHelp
  | FilesHelp
  | GroupsHelp
  | MyAddressHelp
  | MarkdownHelp
  | Welcome
  | AddContact
  | Connect (Maybe AConnectionRequestUri)
  | --   |   ConnectAdmin
    SendAdminWelcome ContactName
  | DeleteContact ContactName
  | ListContacts
  | CreateMyAddress
  | DeleteMyAddress
  | ShowMyAddress
  | AcceptContact ContactName
  | RejectContact ContactName
  | SendMessage ContactName ByteString
  | NewGroup GroupProfile
  | AddMember GroupName ContactName GroupMemberRole
  | JoinGroup GroupName
  | RemoveMember GroupName ContactName
  | MemberRole GroupName ContactName GroupMemberRole
  | LeaveGroup GroupName
  | DeleteGroup GroupName
  | ListMembers GroupName
  | ListGroups
  | SendGroupMessage GroupName ByteString
  | SendFile ContactName FilePath
  | SendGroupFile GroupName FilePath
  | ReceiveFile Int64 (Maybe FilePath)
  | CancelFile Int64
  | FileStatus Int64
  | UpdateProfile Profile
  | ShowProfile
  | QuitChat
  | ShowVersion
  deriving (Show)

defaultChatConfig :: ChatConfig
defaultChatConfig =
  ChatConfig
    { agentConfig =
        defaultAgentConfig
          { tcpPort = undefined, -- agent does not listen to TCP
            smpServers = undefined, -- filled in from options
            dbFile = undefined, -- filled in from options
            dbPoolSize = 1
          },
      dbPoolSize = 1,
      tbqSize = 16,
      fileChunkSize = 15000
    }

logCfg :: LogConfig
logCfg = LogConfig {lc_file = Nothing, lc_stderr = True}

simplexChat :: WithTerminal t => ChatConfig -> ChatOpts -> t -> IO ()
simplexChat cfg opts t =
  -- setLogLevel LogInfo -- LogError
  -- withGlobalLogging logCfg $ do
  initializeNotifications
    >>= newChatController cfg opts t
    >>= runSimplexChat

newChatController :: WithTerminal t => ChatConfig -> ChatOpts -> t -> (Notification -> IO ()) -> IO ChatController
newChatController config@ChatConfig {agentConfig = cfg, dbPoolSize, tbqSize} ChatOpts {dbFile, smpServers} t sendNotification = do
  let f = chatStoreFile dbFile
  firstTime <- not <$> doesFileExist f
  chatStore <- createStore f dbPoolSize
  currentUser <- newTVarIO =<< getCreateActiveUser chatStore
  chatTerminal <- newChatTerminal t
  smpAgent <- getSMPAgentClient cfg {dbFile = dbFile <> ".agent.db", smpServers}
  idsDrg <- newTVarIO =<< drgNew
  inputQ <- newTBQueueIO tbqSize
  notifyQ <- newTBQueueIO tbqSize
  chatLock <- newTMVarIO ()
  sndFiles <- newTVarIO M.empty
  rcvFiles <- newTVarIO M.empty
  pure ChatController {..}

runSimplexChat :: ChatController -> IO ()
runSimplexChat = runReaderT $ do
  user <- readTVarIO =<< asks currentUser
  whenM (asks firstTime) . printToView . chatWelcome user $ Onboarding 0 0 0 0 0
  race_ runTerminalInput runChatController

runChatController :: (MonadUnliftIO m, MonadReader ChatController m, MonadFail m) => m ()
runChatController =
  raceAny_
    [ inputSubscriber,
      agentSubscriber,
      notificationSubscriber
    ]

withLock :: MonadUnliftIO m => TMVar () -> m () -> m ()
withLock lock =
  E.bracket_
    (void . atomically $ takeTMVar lock)
    (atomically $ putTMVar lock ())

inputSubscriber :: (MonadUnliftIO m, MonadReader ChatController m, MonadFail m) => m ()
inputSubscriber = do
  q <- asks inputQ
  l <- asks chatLock
  a <- asks smpAgent
  forever $
    atomically (readTBQueue q) >>= \case
      InputControl _ -> pure ()
      InputCommand s ->
        case parseAll chatCommandP . B.dropWhileEnd isSpace . encodeUtf8 $ T.pack s of
          Left e -> printToView [plain s, "invalid input: " <> plain e]
          Right cmd -> do
            case cmd of
              SendMessage c msg -> showSentMessage c msg
              SendGroupMessage g msg -> showSentGroupMessage g msg
              SendFile c f -> showSentFileInvitation c f
              SendGroupFile g f -> showSentGroupFileInvitation g f
              SendAdminWelcome c -> forM_ adminWelcomeMessages $ showSentMessage c
              _ -> printToView [plain s]
            user <- readTVarIO =<< asks currentUser
            withAgentLock a . withLock l . void . runExceptT $
              processChatCommand user cmd `catchError` showChatError

processChatCommand :: forall m. ChatMonad m => User -> ChatCommand -> m ()
processChatCommand user@User {userId, profile} = \case
  ChatHelp -> printToView chatHelpInfo
  FilesHelp -> printToView filesHelpInfo
  GroupsHelp -> printToView groupsHelpInfo
  MyAddressHelp -> printToView myAddressHelpInfo
  MarkdownHelp -> printToView markdownInfo
  Welcome -> do
    ob <- withStore (`getOnboarding` userId)
    printToView $ chatWelcome user ob
  AddContact -> do
    (connId, cReq) <- withAgent (`createConnection` SCMInvitation)
    withStore $ \st -> createDirectConnection st userId connId
    showInvitation cReq
  Connect (Just (ACR SCMInvitation cReq)) -> connect cReq (XInfo profile) >> showSentConfirmation
  Connect (Just (ACR SCMContact cReq)) -> connect cReq (XContact profile Nothing) >> showSentInvitation
  Connect Nothing -> showInvalidConnReq
  -- ConnectAdmin -> connect adminContactReq (XContact profile Nothing) >> showSentInvitation
  SendAdminWelcome cName -> forM_ adminWelcomeMessages $ sendMessageCmd cName
  DeleteContact cName ->
    withStore (\st -> getContactGroupNames st userId cName) >>= \case
      [] -> do
        conns <- withStore $ \st -> getContactConnections st userId cName
        withAgent $ \a -> forM_ conns $ \Connection {agentConnId} ->
          deleteConnection a agentConnId `catchError` \(_ :: AgentErrorType) -> pure ()
        withStore $ \st -> deleteContact st userId cName
        unsetActive $ ActiveC cName
        showContactDeleted cName
      gs -> showContactGroups cName gs
  ListContacts -> withStore (`getUserContacts` user) >>= showContactsList
  CreateMyAddress -> do
    (connId, cReq) <- withAgent (`createConnection` SCMContact)
    withStore $ \st -> createUserContactLink st userId connId cReq
    showUserContactLinkCreated cReq
  DeleteMyAddress -> do
    conns <- withStore $ \st -> getUserContactLinkConnections st userId
    withAgent $ \a -> forM_ conns $ \Connection {agentConnId} ->
      deleteConnection a agentConnId `catchError` \(_ :: AgentErrorType) -> pure ()
    withStore $ \st -> deleteUserContactLink st userId
    showUserContactLinkDeleted
  ShowMyAddress -> do
    cReq <- withStore $ \st -> getUserContactLink st userId
    showUserContactLink cReq
  AcceptContact cName -> do
    UserContactRequest {agentInvitationId, profileId} <- withStore $ \st ->
      getContactRequest st userId cName
    connId <- withAgent $ \a -> acceptContact a agentInvitationId . directMessage $ XInfo profile
    withStore $ \st -> createAcceptedContact st userId connId cName profileId
    showAcceptingContactRequest cName
  RejectContact cName -> do
    UserContactRequest {agentContactConnId, agentInvitationId} <- withStore $ \st ->
      getContactRequest st userId cName
        `E.finally` deleteContactRequest st userId cName
    withAgent $ \a -> rejectContact a agentContactConnId agentInvitationId
    showContactRequestRejected cName
  SendMessage cName msg -> sendMessageCmd cName msg
  NewGroup gProfile -> do
    gVar <- asks idsDrg
    group <- withStore $ \st -> createNewGroup st gVar user gProfile
    showGroupCreated group
  AddMember gName cName memRole -> do
    (group, contact) <- withStore $ \st -> (,) <$> getGroup st user gName <*> getContact st userId cName
    let Group {groupId, groupProfile, membership, members} = group
        GroupMember {memberRole = userRole, memberId = userMemberId} = membership
    when (userRole < GRAdmin || userRole < memRole) $ chatError CEGroupUserRole
    when (memberStatus membership == GSMemInvited) $ chatError (CEGroupNotJoined gName)
    unless (memberActive membership) $ chatError CEGroupMemberNotActive
    let sendInvitation memberId cReq = do
          sendDirectMessage (contactConn contact) $
            XGrpInv $ GroupInvitation (MemberIdRole userMemberId userRole) (MemberIdRole memberId memRole) cReq groupProfile
          showSentGroupInvitation gName cName
          setActive $ ActiveG gName
    case contactMember contact members of
      Nothing -> do
        gVar <- asks idsDrg
        (agentConnId, cReq) <- withAgent (`createConnection` SCMInvitation)
        GroupMember {memberId} <- withStore $ \st -> createContactMember st gVar user groupId contact memRole agentConnId cReq
        sendInvitation memberId cReq
      Just GroupMember {groupMemberId, memberId, memberStatus}
        | memberStatus == GSMemInvited ->
          withStore (\st -> getMemberInvitation st user groupMemberId) >>= \case
            Just cReq -> sendInvitation memberId cReq
            Nothing -> showCannotResendInvitation gName cName
        | otherwise -> chatError (CEGroupDuplicateMember cName)
  JoinGroup gName -> do
    ReceivedGroupInvitation {fromMember, userMember, connRequest} <- withStore $ \st -> getGroupInvitation st user gName
    agentConnId <- withAgent $ \a -> joinConnection a connRequest . directMessage . XGrpAcpt $ memberId (userMember :: GroupMember)
    withStore $ \st -> do
      createMemberConnection st userId fromMember agentConnId
      updateGroupMemberStatus st userId fromMember GSMemAccepted
      updateGroupMemberStatus st userId userMember GSMemAccepted
  MemberRole _gName _cName _mRole -> pure ()
  RemoveMember gName cName -> do
    Group {membership, members} <- withStore $ \st -> getGroup st user gName
    case find ((== cName) . (localDisplayName :: GroupMember -> ContactName)) members of
      Nothing -> chatError $ CEGroupMemberNotFound cName
      Just m@GroupMember {memberId = mId, memberRole = mRole, memberStatus = mStatus} -> do
        let userRole = memberRole (membership :: GroupMember)
        when (userRole < GRAdmin || userRole < mRole) $ chatError CEGroupUserRole
        when (mStatus /= GSMemInvited) . sendGroupMessage members $ XGrpMemDel mId
        deleteMemberConnection m
        withStore $ \st -> updateGroupMemberStatus st userId m GSMemRemoved
        showDeletedMember gName Nothing (Just m)
  LeaveGroup gName -> do
    Group {membership, members} <- withStore $ \st -> getGroup st user gName
    sendGroupMessage members XGrpLeave
    mapM_ deleteMemberConnection members
    withStore $ \st -> updateGroupMemberStatus st userId membership GSMemLeft
    showLeftMemberUser gName
  DeleteGroup gName -> do
    g@Group {membership, members} <- withStore $ \st -> getGroup st user gName
    let s = memberStatus membership
        canDelete =
          memberRole (membership :: GroupMember) == GROwner
            || (s == GSMemRemoved || s == GSMemLeft || s == GSMemGroupDeleted || s == GSMemInvited)
    unless canDelete $ chatError CEGroupUserRole
    when (memberActive membership) $ sendGroupMessage members XGrpDel
    mapM_ deleteMemberConnection members
    withStore $ \st -> deleteGroup st user g
    showGroupDeletedUser gName
  ListMembers gName -> do
    group <- withStore $ \st -> getGroup st user gName
    showGroupMembers group
  ListGroups -> withStore (`getUserGroupDetails` userId) >>= showGroupsList
  SendGroupMessage gName msg -> do
    -- TODO save pending message delivery for members without connections
    Group {members, membership} <- withStore $ \st -> getGroup st user gName
    unless (memberActive membership) $ chatError CEGroupMemberUserRemoved
    let msgEvent = XMsgNew . MCText $ safeDecodeUtf8 msg
    sendGroupMessage members msgEvent
    setActive $ ActiveG gName
  SendFile cName f -> do
    (fileSize, chSize) <- checkSndFile f
    contact <- withStore $ \st -> getContact st userId cName
    (agentConnId, fileConnReq) <- withAgent (`createConnection` SCMInvitation)
    let fileInv = FileInvitation {fileName = takeFileName f, fileSize, fileConnReq}
    SndFileTransfer {fileId} <- withStore $ \st ->
      createSndFileTransfer st userId contact f fileInv agentConnId chSize
    sendDirectMessage (contactConn contact) $ XFile fileInv
    showSentFileInfo fileId
    setActive $ ActiveC cName
  SendGroupFile gName f -> do
    (fileSize, chSize) <- checkSndFile f
    group@Group {members, membership} <- withStore $ \st -> getGroup st user gName
    unless (memberActive membership) $ chatError CEGroupMemberUserRemoved
    let fileName = takeFileName f
    ms <- forM (filter memberActive members) $ \m -> do
      (connId, fileConnReq) <- withAgent (`createConnection` SCMInvitation)
      pure (m, connId, FileInvitation {fileName, fileSize, fileConnReq})
    fileId <- withStore $ \st -> createSndGroupFileTransfer st userId group ms f fileSize chSize
    -- TODO sendGroupMessage - same file invitation to all
    forM_ ms $ \(m, _, fileInv) ->
      traverse (`sendDirectMessage` XFile fileInv) $ memberConn m
    showSentFileInfo fileId
    setActive $ ActiveG gName
  ReceiveFile fileId filePath_ -> do
    ft@RcvFileTransfer {fileInvitation = FileInvitation {fileName, fileConnReq}, fileStatus} <- withStore $ \st -> getRcvFileTransfer st userId fileId
    unless (fileStatus == RFSNew) . chatError $ CEFileAlreadyReceiving fileName
    tryError (withAgent $ \a -> joinConnection a fileConnReq . directMessage $ XFileAcpt fileName) >>= \case
      Right agentConnId -> do
        filePath <- getRcvFilePath fileId filePath_ fileName
        withStore $ \st -> acceptRcvFileTransfer st userId fileId agentConnId filePath
        showRcvFileAccepted ft filePath
      Left (ChatErrorAgent (SMP SMP.AUTH)) -> showRcvFileSndCancelled ft
      Left (ChatErrorAgent (CONN DUPLICATE)) -> showRcvFileSndCancelled ft
      Left e -> throwError e
  CancelFile fileId ->
    withStore (\st -> getFileTransfer st userId fileId) >>= \case
      FTSnd fts -> do
        forM_ fts $ \ft -> cancelSndFileTransfer ft
        showSndGroupFileCancelled fts
      FTRcv ft -> do
        cancelRcvFileTransfer ft
        showRcvFileCancelled ft
  FileStatus fileId ->
    withStore (\st -> getFileTransferProgress st userId fileId) >>= showFileTransferStatus
  UpdateProfile p -> unless (p == profile) $ do
    user' <- withStore $ \st -> updateUserProfile st user p
    asks currentUser >>= atomically . (`writeTVar` user')
    contacts <- withStore (`getUserContacts` user)
    forM_ contacts $ \ct -> sendDirectMessage (contactConn ct) $ XInfo p
    showUserProfileUpdated user user'
  ShowProfile -> showUserProfile profile
  QuitChat -> liftIO exitSuccess
  ShowVersion -> printToView clientVersionInfo
  where
    connect :: ConnectionRequestUri c -> ChatMsgEvent -> m ()
    connect cReq msg = do
      connId <- withAgent $ \a -> joinConnection a cReq $ directMessage msg
      withStore $ \st -> createDirectConnection st userId connId
    sendMessageCmd :: ContactName -> ByteString -> m ()
    sendMessageCmd cName msg = do
      contact <- withStore $ \st -> getContact st userId cName
      let msgEvent = XMsgNew . MCText $ safeDecodeUtf8 msg
      sendDirectMessage (contactConn contact) msgEvent
      setActive $ ActiveC cName
    contactMember :: Contact -> [GroupMember] -> Maybe GroupMember
    contactMember Contact {contactId} =
      find $ \GroupMember {memberContactId = cId, memberStatus = s} ->
        cId == Just contactId && s /= GSMemRemoved && s /= GSMemLeft
    checkSndFile :: FilePath -> m (Integer, Integer)
    checkSndFile f = do
      unlessM (doesFileExist f) . chatError $ CEFileNotFound f
      (,) <$> getFileSize f <*> asks (fileChunkSize . config)
    getRcvFilePath :: Int64 -> Maybe FilePath -> String -> m FilePath
    getRcvFilePath fileId filePath fileName = case filePath of
      Nothing -> do
        dir <- (`combine` "Downloads") <$> getHomeDirectory
        ifM (doesDirectoryExist dir) (pure dir) getTemporaryDirectory
          >>= (`uniqueCombine` fileName)
          >>= createEmptyFile
      Just fPath ->
        ifM
          (doesDirectoryExist fPath)
          (fPath `uniqueCombine` fileName >>= createEmptyFile)
          $ ifM
            (doesFileExist fPath)
            (chatError $ CEFileAlreadyExists fPath)
            (createEmptyFile fPath)
      where
        createEmptyFile :: FilePath -> m FilePath
        createEmptyFile fPath = emptyFile fPath `E.catch` (chatError . CEFileWrite fPath)
        emptyFile :: FilePath -> m FilePath
        emptyFile fPath = do
          h <- getFileHandle fileId fPath rcvFiles AppendMode
          liftIO $ B.hPut h "" >> hFlush h
          pure fPath
    uniqueCombine :: FilePath -> String -> m FilePath
    uniqueCombine filePath fileName = tryCombine (0 :: Int)
      where
        tryCombine n =
          let (name, ext) = splitExtensions fileName
              suffix = if n == 0 then "" else "_" <> show n
              f = filePath `combine` (name <> suffix <> ext)
           in ifM (doesFileExist f) (tryCombine $ n + 1) (pure f)

agentSubscriber :: (MonadUnliftIO m, MonadReader ChatController m, MonadFail m) => m ()
agentSubscriber = do
  q <- asks $ subQ . smpAgent
  l <- asks chatLock
  subscribeUserConnections
  forever $ do
    (_, connId, msg) <- atomically $ readTBQueue q
    user <- readTVarIO =<< asks currentUser
    withLock l . void . runExceptT $
      processAgentMessage user connId msg `catchError` showChatError

subscribeUserConnections :: (MonadUnliftIO m, MonadReader ChatController m, MonadFail m) => m ()
subscribeUserConnections = void . runExceptT $ do
  user <- readTVarIO =<< asks currentUser
  subscribeContacts user
  subscribeGroups user
  subscribeFiles user
  subscribePendingConnections user
  subscribeUserContactLink user
  where
    subscribeContacts user = do
      contacts <- withStore (`getUserContacts` user)
      forM_ contacts $ \ct@Contact {localDisplayName = c} ->
        (subscribe (contactConnId ct) >> showContactSubscribed c) `catchError` showContactSubError c
    subscribeGroups user = do
      groups <- withStore (`getUserGroups` user)
      forM_ groups $ \g@Group {members, membership, localDisplayName = gn} -> do
        let connectedMembers = mapMaybe (\m -> (m,) <$> memberConnId m) members
        if memberStatus membership == GSMemInvited
          then showGroupInvitation g
          else
            if null connectedMembers
              then
                if memberActive membership
                  then showGroupEmpty g
                  else showGroupRemoved g
              else do
                forM_ connectedMembers $ \(GroupMember {localDisplayName = c}, cId) ->
                  subscribe cId `catchError` showMemberSubError gn c
                showGroupSubscribed g
    subscribeFiles user = do
      withStore (`getLiveSndFileTransfers` user) >>= mapM_ subscribeSndFile
      withStore (`getLiveRcvFileTransfers` user) >>= mapM_ subscribeRcvFile
      where
        subscribeSndFile ft@SndFileTransfer {fileId, fileStatus, agentConnId} = do
          subscribe agentConnId `catchError` showSndFileSubError ft
          void . forkIO $ do
            threadDelay 1000000
            l <- asks chatLock
            a <- asks smpAgent
            unless (fileStatus == FSNew) . unlessM (isFileActive fileId sndFiles) $
              withAgentLock a . withLock l $
                sendFileChunk ft
        subscribeRcvFile ft@RcvFileTransfer {fileStatus} =
          case fileStatus of
            RFSAccepted fInfo -> resume fInfo
            RFSConnected fInfo -> resume fInfo
            _ -> pure ()
          where
            resume RcvFileInfo {agentConnId} =
              subscribe agentConnId `catchError` showRcvFileSubError ft
    subscribePendingConnections user = do
      cs <- withStore (`getPendingConnections` user)
      subscribeConns cs `catchError` \_ -> pure ()
    subscribeUserContactLink User {userId} = do
      cs <- withStore (`getUserContactLinkConnections` userId)
      (subscribeConns cs >> showUserContactLinkSubscribed)
        `catchError` showUserContactLinkSubError
    subscribe cId = withAgent (`subscribeConnection` cId)
    subscribeConns conns =
      withAgent $ \a ->
        forM_ conns $ \Connection {agentConnId} ->
          subscribeConnection a agentConnId

processAgentMessage :: forall m. ChatMonad m => User -> ConnId -> ACommand 'Agent -> m ()
processAgentMessage user@User {userId, profile} agentConnId agentMessage = do
  chatDirection <- withStore $ \st -> getConnectionChatDirection st user agentConnId
  forM_ (agentMsgConnStatus agentMessage) $ \status ->
    withStore $ \st -> updateConnectionStatus st (fromConnection chatDirection) status
  case chatDirection of
    ReceivedDirectMessage conn maybeContact ->
      processDirectMessage agentMessage conn maybeContact
    ReceivedGroupMessage conn gName m ->
      processGroupMessage agentMessage conn gName m
    RcvFileConnection conn ft ->
      processRcvFileConn agentMessage conn ft
    SndFileConnection conn ft ->
      processSndFileConn agentMessage conn ft
    UserContactConnection conn uc ->
      processUserContactRequest agentMessage conn uc
  where
    isMember :: MemberId -> Group -> Bool
    isMember memId Group {membership, members} =
      sameMemberId memId membership || isJust (find (sameMemberId memId) members)

    contactIsReady :: Contact -> Bool
    contactIsReady Contact {activeConn} = connStatus activeConn == ConnReady

    memberIsReady :: GroupMember -> Bool
    memberIsReady GroupMember {activeConn} = maybe False ((== ConnReady) . connStatus) activeConn

    agentMsgConnStatus :: ACommand 'Agent -> Maybe ConnStatus
    agentMsgConnStatus = \case
      CONF {} -> Just ConnRequested
      INFO _ -> Just ConnSndReady
      CON -> Just ConnReady
      _ -> Nothing

    processDirectMessage :: ACommand 'Agent -> Connection -> Maybe Contact -> m ()
    processDirectMessage agentMsg conn = \case
      Nothing -> case agentMsg of
        CONF confId connInfo -> do
          saveConnInfo conn connInfo
          allowAgentConnection conn confId $ XInfo profile
        INFO connInfo ->
          saveConnInfo conn connInfo
        MSG meta msgBody -> do
          _ <- saveRcvMSG conn meta msgBody
          withAckMessage agentConnId meta $ pure ()
          ackMsgDeliveryEvent conn meta
        SENT msgId ->
          sentMsgDeliveryEvent conn msgId
        _ -> pure ()
      Just ct@Contact {localDisplayName = c} -> case agentMsg of
        MSG meta msgBody -> do
          chatMsgEvent <- saveRcvMSG conn meta msgBody
          withAckMessage agentConnId meta $
            case chatMsgEvent of
              XMsgNew (MCText text) -> newTextMessage c meta text
              XFile fInv -> processFileInvitation ct meta fInv
              XInfo p -> xInfo ct p
              XGrpInv gInv -> processGroupInvitation ct gInv
              XInfoProbe probe -> xInfoProbe ct probe
              XInfoProbeCheck probeHash -> xInfoProbeCheck ct probeHash
              XInfoProbeOk probe -> xInfoProbeOk ct probe
              _ -> pure ()
          ackMsgDeliveryEvent conn meta
        CONF confId connInfo -> do
          -- confirming direct connection with a member
          ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
          case chatMsgEvent of
            XGrpMemInfo _memId _memProfile -> do
              -- TODO check member ID
              -- TODO update member profile
              allowAgentConnection conn confId XOk
            _ -> messageError "CONF from member must have x.grp.mem.info"
        INFO connInfo -> do
          ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
          case chatMsgEvent of
            XGrpMemInfo _memId _memProfile -> do
              -- TODO check member ID
              -- TODO update member profile
              pure ()
            XInfo _profile -> do
              -- TODO update contact profile
              pure ()
            XOk -> pure ()
            _ -> messageError "INFO for existing contact must have x.grp.mem.info, x.info or x.ok"
        CON ->
          withStore (\st -> getViaGroupMember st user ct) >>= \case
            Nothing -> do
              showContactConnected ct
              setActive $ ActiveC c
              showToast (c <> "> ") "connected"
            Just (gName, m) ->
              when (memberIsReady m) $ do
                notifyMemberConnected gName m
                when (memberCategory m == GCPreMember) $ probeMatchingContacts ct
        SENT msgId ->
          sentMsgDeliveryEvent conn msgId
        END -> do
          showContactAnotherClient c
          showToast (c <> "> ") "connected to another client"
          unsetActive $ ActiveC c
        DOWN -> do
          showContactDisconnected c
          showToast (c <> "> ") "disconnected"
        UP -> do
          showContactSubscribed c
          showToast (c <> "> ") "is active"
          setActive $ ActiveC c
        _ -> pure ()

    processGroupMessage :: ACommand 'Agent -> Connection -> GroupName -> GroupMember -> m ()
    processGroupMessage agentMsg conn gName m = case agentMsg of
      CONF confId connInfo -> do
        ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
        case memberCategory m of
          GCInviteeMember ->
            case chatMsgEvent of
              XGrpAcpt memId
                | sameMemberId memId m -> do
                  withStore $ \st -> updateGroupMemberStatus st userId m GSMemAccepted
                  allowAgentConnection conn confId XOk
                | otherwise -> messageError "x.grp.acpt: memberId is different from expected"
              _ -> messageError "CONF from invited member must have x.grp.acpt"
          _ ->
            case chatMsgEvent of
              XGrpMemInfo memId _memProfile
                | sameMemberId memId m -> do
                  -- TODO update member profile
                  Group {membership} <- withStore $ \st -> getGroup st user gName
                  allowAgentConnection conn confId $ XGrpMemInfo (memberId (membership :: GroupMember)) profile
                | otherwise -> messageError "x.grp.mem.info: memberId is different from expected"
              _ -> messageError "CONF from member must have x.grp.mem.info"
      INFO connInfo -> do
        ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
        case chatMsgEvent of
          XGrpMemInfo memId _memProfile
            | sameMemberId memId m -> do
              -- TODO update member profile
              pure ()
            | otherwise -> messageError "x.grp.mem.info: memberId is different from expected"
          XOk -> pure ()
          _ -> messageError "INFO from member must have x.grp.mem.info"
        pure ()
      CON -> do
        group@Group {members, membership} <- withStore $ \st -> getGroup st user gName
        withStore $ \st -> do
          updateGroupMemberStatus st userId m GSMemConnected
          unless (memberActive membership) $
            updateGroupMemberStatus st userId membership GSMemConnected
        -- TODO forward any pending (GMIntroInvReceived) introductions
        case memberCategory m of
          GCHostMember -> do
            showUserJoinedGroup gName
            setActive $ ActiveG gName
            showToast ("#" <> gName) "you are connected to group"
          GCInviteeMember -> do
            showJoinedGroupMember gName m
            setActive $ ActiveG gName
            showToast ("#" <> gName) $ "member " <> localDisplayName (m :: GroupMember) <> " is connected"
            intros <- withStore $ \st -> createIntroductions st group m
            sendGroupMessage members . XGrpMemNew $ memberInfo m
            forM_ intros $ \intro -> do
              sendDirectMessage conn . XGrpMemIntro . memberInfo $ reMember intro
              withStore $ \st -> updateIntroStatus st intro GMIntroSent
          _ -> do
            -- TODO send probe and decide whether to use existing contact connection or the new contact connection
            -- TODO notify member who forwarded introduction - question - where it is stored? There is via_contact but probably there should be via_member in group_members table
            withStore (\st -> getViaGroupContact st user m) >>= \case
              Nothing -> do
                notifyMemberConnected gName m
                messageError "implementation error: connected member does not have contact"
              Just ct ->
                when (contactIsReady ct) $ do
                  notifyMemberConnected gName m
                  when (memberCategory m == GCPreMember) $ probeMatchingContacts ct
      MSG meta msgBody -> do
        chatMsgEvent <- saveRcvMSG conn meta msgBody
        withAckMessage agentConnId meta $
          case chatMsgEvent of
            XMsgNew (MCText text) -> newGroupTextMessage gName m meta text
            XFile fInv -> processGroupFileInvitation gName m meta fInv
            XGrpMemNew memInfo -> xGrpMemNew gName m memInfo
            XGrpMemIntro memInfo -> xGrpMemIntro conn gName m memInfo
            XGrpMemInv memId introInv -> xGrpMemInv gName m memId introInv
            XGrpMemFwd memInfo introInv -> xGrpMemFwd gName m memInfo introInv
            XGrpMemDel memId -> xGrpMemDel gName m memId
            XGrpLeave -> xGrpLeave gName m
            XGrpDel -> xGrpDel gName m
            _ -> messageError $ "unsupported message: " <> T.pack (show chatMsgEvent)
        ackMsgDeliveryEvent conn meta
      SENT msgId ->
        sentMsgDeliveryEvent conn msgId
      _ -> pure ()

    processSndFileConn :: ACommand 'Agent -> Connection -> SndFileTransfer -> m ()
    processSndFileConn agentMsg conn ft@SndFileTransfer {fileId, fileName, fileStatus} =
      case agentMsg of
        CONF confId connInfo -> do
          ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
          case chatMsgEvent of
            -- TODO save XFileAcpt message
            XFileAcpt name
              | name == fileName -> do
                withStore $ \st -> updateSndFileStatus st ft FSAccepted
                allowAgentConnection conn confId XOk
              | otherwise -> messageError "x.file.acpt: fileName is different from expected"
            _ -> messageError "CONF from file connection must have x.file.acpt"
        CON -> do
          withStore $ \st -> updateSndFileStatus st ft FSConnected
          showSndFileStart ft
          sendFileChunk ft
        SENT msgId -> do
          withStore $ \st -> updateSndFileChunkSent st ft msgId
          unless (fileStatus == FSCancelled) $ sendFileChunk ft
        MERR _ err -> do
          cancelSndFileTransfer ft
          case err of
            SMP SMP.AUTH -> unless (fileStatus == FSCancelled) $ showSndFileRcvCancelled ft
            _ -> chatError $ CEFileSend fileId err
        MSG meta _ ->
          withAckMessage agentConnId meta $ pure ()
        _ -> pure ()

    processRcvFileConn :: ACommand 'Agent -> Connection -> RcvFileTransfer -> m ()
    processRcvFileConn agentMsg _conn ft@RcvFileTransfer {fileId, chunkSize} =
      case agentMsg of
        CON -> do
          withStore $ \st -> updateRcvFileStatus st ft FSConnected
          showRcvFileStart ft
        MSG meta@MsgMeta {recipient = (msgId, _), integrity} msgBody -> withAckMessage agentConnId meta $ do
          parseFileChunk msgBody >>= \case
            FileChunkCancel -> do
              cancelRcvFileTransfer ft
              showRcvFileSndCancelled ft
            FileChunk {chunkNo, chunkBytes = chunk} -> do
              case integrity of
                MsgOk -> pure ()
                MsgError MsgDuplicate -> pure () -- TODO remove once agent removes duplicates
                MsgError e ->
                  badRcvFileChunk ft $ "invalid file chunk number " <> show chunkNo <> ": " <> show e
              withStore (\st -> createRcvFileChunk st ft chunkNo msgId) >>= \case
                RcvChunkOk ->
                  if B.length chunk /= fromInteger chunkSize
                    then badRcvFileChunk ft "incorrect chunk size"
                    else appendFileChunk ft chunkNo chunk
                RcvChunkFinal ->
                  if B.length chunk > fromInteger chunkSize
                    then badRcvFileChunk ft "incorrect chunk size"
                    else do
                      appendFileChunk ft chunkNo chunk
                      withStore $ \st -> do
                        updateRcvFileStatus st ft FSComplete
                        deleteRcvFileChunks st ft
                      showRcvFileComplete ft
                      closeFileHandle fileId rcvFiles
                      withAgent (`deleteConnection` agentConnId)
                RcvChunkDuplicate -> pure ()
                RcvChunkError -> badRcvFileChunk ft $ "incorrect chunk number " <> show chunkNo
        _ -> pure ()

    processUserContactRequest :: ACommand 'Agent -> Connection -> UserContact -> m ()
    processUserContactRequest agentMsg _conn UserContact {userContactLinkId} = case agentMsg of
      REQ invId connInfo -> do
        ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
        case chatMsgEvent of
          XContact p _ -> profileContactRequest invId p
          XInfo p -> profileContactRequest invId p
          -- TODO show/log error, other events in contact request
          _ -> pure ()
      _ -> pure ()
      where
        profileContactRequest :: InvitationId -> Profile -> m ()
        profileContactRequest invId p = do
          cName <- withStore $ \st -> createContactRequest st userId userContactLinkId invId p
          showReceivedContactRequest cName p

    withAckMessage :: ConnId -> MsgMeta -> m () -> m ()
    withAckMessage cId MsgMeta {recipient = (msgId, _)} action =
      action `E.finally` withAgent (\a -> ackMessage a cId msgId `catchError` \_ -> pure ())

    ackMsgDeliveryEvent :: Connection -> MsgMeta -> m ()
    ackMsgDeliveryEvent Connection {connId} MsgMeta {recipient = (msgId, _)} =
      withStore $ \st -> createRcvMsgDeliveryEvent st connId msgId MDSRcvAcknowledged

    sentMsgDeliveryEvent :: Connection -> AgentMsgId -> m ()
    sentMsgDeliveryEvent Connection {connId} msgId =
      withStore $ \st -> createSndMsgDeliveryEvent st connId msgId MDSSndSent

    badRcvFileChunk :: RcvFileTransfer -> String -> m ()
    badRcvFileChunk ft@RcvFileTransfer {fileStatus} err =
      case fileStatus of
        RFSCancelled _ -> pure ()
        _ -> do
          cancelRcvFileTransfer ft
          chatError $ CEFileRcvChunk err

    notifyMemberConnected :: GroupName -> GroupMember -> m ()
    notifyMemberConnected gName m@GroupMember {localDisplayName} = do
      showConnectedToGroupMember gName m
      setActive $ ActiveG gName
      showToast ("#" <> gName) $ "member " <> localDisplayName <> " is connected"

    probeMatchingContacts :: Contact -> m ()
    probeMatchingContacts ct = do
      gVar <- asks idsDrg
      (probe, probeId) <- withStore $ \st -> createSentProbe st gVar userId ct
      sendDirectMessage (contactConn ct) $ XInfoProbe probe
      cs <- withStore (\st -> getMatchingContacts st userId ct)
      let probeHash = ProbeHash $ C.sha256Hash (unProbe probe)
      forM_ cs $ \c -> sendProbeHash c probeHash probeId `catchError` const (pure ())
      where
        sendProbeHash c probeHash probeId = do
          sendDirectMessage (contactConn c) $ XInfoProbeCheck probeHash
          withStore $ \st -> createSentProbeHash st userId probeId c

    messageWarning :: Text -> m ()
    messageWarning = showMessageError "warning"

    messageError :: Text -> m ()
    messageError = showMessageError "error"

    newTextMessage :: ContactName -> MsgMeta -> Text -> m ()
    newTextMessage c meta text = do
      showReceivedMessage c (snd $ broker meta) (msgPlain text) (integrity (meta :: MsgMeta))
      showToast (c <> "> ") text
      setActive $ ActiveC c

    newGroupTextMessage :: GroupName -> GroupMember -> MsgMeta -> Text -> m ()
    newGroupTextMessage gName GroupMember {localDisplayName = c} meta text = do
      showReceivedGroupMessage gName c (snd $ broker meta) (msgPlain text) (integrity (meta :: MsgMeta))
      showToast ("#" <> gName <> " " <> c <> "> ") text
      setActive $ ActiveG gName

    processFileInvitation :: Contact -> MsgMeta -> FileInvitation -> m ()
    processFileInvitation contact@Contact {localDisplayName = c} meta fInv = do
      -- TODO chunk size has to be sent as part of invitation
      chSize <- asks $ fileChunkSize . config
      ft <- withStore $ \st -> createRcvFileTransfer st userId contact fInv chSize
      showReceivedMessage c (snd $ broker meta) (receivedFileInvitation ft) (integrity (meta :: MsgMeta))
      setActive $ ActiveC c

    processGroupFileInvitation :: GroupName -> GroupMember -> MsgMeta -> FileInvitation -> m ()
    processGroupFileInvitation gName m@GroupMember {localDisplayName = c} meta fInv = do
      chSize <- asks $ fileChunkSize . config
      ft <- withStore $ \st -> createRcvGroupFileTransfer st userId m fInv chSize
      showReceivedGroupMessage gName c (snd $ broker meta) (receivedFileInvitation ft) (integrity (meta :: MsgMeta))
      setActive $ ActiveG gName

    processGroupInvitation :: Contact -> GroupInvitation -> m ()
    processGroupInvitation ct@Contact {localDisplayName} inv@(GroupInvitation (MemberIdRole fromMemId fromRole) (MemberIdRole memId memRole) _ _) = do
      when (fromRole < GRAdmin || fromRole < memRole) $ chatError (CEGroupContactRole localDisplayName)
      when (fromMemId == memId) $ chatError CEGroupDuplicateMemberId
      group <- withStore $ \st -> createGroupInvitation st user ct inv
      showReceivedGroupInvitation group localDisplayName memRole

    xInfo :: Contact -> Profile -> m ()
    xInfo c@Contact {profile = p} p' = unless (p == p') $ do
      c' <- withStore $ \st -> updateContactProfile st userId c p'
      showContactUpdated c c'

    xInfoProbe :: Contact -> Probe -> m ()
    xInfoProbe c2 probe = do
      r <- withStore $ \st -> matchReceivedProbe st userId c2 probe
      forM_ r $ \c1 -> probeMatch c1 c2 probe

    xInfoProbeCheck :: Contact -> ProbeHash -> m ()
    xInfoProbeCheck c1 probeHash = do
      r <- withStore $ \st -> matchReceivedProbeHash st userId c1 probeHash
      forM_ r . uncurry $ probeMatch c1

    probeMatch :: Contact -> Contact -> Probe -> m ()
    probeMatch c1@Contact {profile = p1} c2@Contact {profile = p2} probe =
      when (p1 == p2) $ do
        sendDirectMessage (contactConn c1) $ XInfoProbeOk probe
        mergeContacts c1 c2

    xInfoProbeOk :: Contact -> Probe -> m ()
    xInfoProbeOk c1 probe = do
      r <- withStore $ \st -> matchSentProbe st userId c1 probe
      forM_ r $ \c2 -> mergeContacts c1 c2

    mergeContacts :: Contact -> Contact -> m ()
    mergeContacts to from = do
      withStore $ \st -> mergeContactRecords st userId to from
      showContactsMerged to from

    saveConnInfo :: Connection -> ConnInfo -> m ()
    saveConnInfo activeConn connInfo = do
      ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage connInfo
      case chatMsgEvent of
        XInfo p ->
          withStore $ \st -> createDirectContact st userId activeConn p
        -- TODO show/log error, other events in SMP confirmation
        _ -> pure ()

    xGrpMemNew :: GroupName -> GroupMember -> MemberInfo -> m ()
    xGrpMemNew gName m memInfo@(MemberInfo memId _ _) = do
      group@Group {membership} <- withStore $ \st -> getGroup st user gName
      unless (sameMemberId memId membership) $
        if isMember memId group
          then messageError "x.grp.mem.new error: member already exists"
          else do
            newMember <- withStore $ \st -> createNewGroupMember st user group memInfo GCPostMember GSMemAnnounced
            showJoinedGroupMemberConnecting gName m newMember

    xGrpMemIntro :: Connection -> GroupName -> GroupMember -> MemberInfo -> m ()
    xGrpMemIntro conn gName m memInfo@(MemberInfo memId _ _) =
      case memberCategory m of
        GCHostMember -> do
          group <- withStore $ \st -> getGroup st user gName
          if isMember memId group
            then messageWarning "x.grp.mem.intro ignored: member already exists"
            else do
              (groupConnId, groupConnReq) <- withAgent (`createConnection` SCMInvitation)
              (directConnId, directConnReq) <- withAgent (`createConnection` SCMInvitation)
              newMember <- withStore $ \st -> createIntroReMember st user group m memInfo groupConnId directConnId
              let msg = XGrpMemInv memId IntroInvitation {groupConnReq, directConnReq}
              sendDirectMessage conn msg
              withStore $ \st -> updateGroupMemberStatus st userId newMember GSMemIntroInvited
        _ -> messageError "x.grp.mem.intro can be only sent by host member"

    xGrpMemInv :: GroupName -> GroupMember -> MemberId -> IntroInvitation -> m ()
    xGrpMemInv gName m memId introInv =
      case memberCategory m of
        GCInviteeMember -> do
          group <- withStore $ \st -> getGroup st user gName
          case find (sameMemberId memId) $ members group of
            Nothing -> messageError "x.grp.mem.inv error: referenced member does not exists"
            Just reMember -> do
              intro <- withStore $ \st -> saveIntroInvitation st reMember m introInv
              case activeConn (reMember :: GroupMember) of
                Nothing -> pure () -- this is not an error, introduction will be forwarded once the member is connected
                Just reConn -> do
                  sendDirectMessage reConn $ XGrpMemFwd (memberInfo m) introInv
                  withStore $ \st -> updateIntroStatus st intro GMIntroInvForwarded
        _ -> messageError "x.grp.mem.inv can be only sent by invitee member"

    xGrpMemFwd :: GroupName -> GroupMember -> MemberInfo -> IntroInvitation -> m ()
    xGrpMemFwd gName m memInfo@(MemberInfo memId _ _) introInv@IntroInvitation {groupConnReq, directConnReq} = do
      group@Group {membership} <- withStore $ \st -> getGroup st user gName
      toMember <- case find (sameMemberId memId) $ members group of
        -- TODO if the missed messages are correctly sent as soon as there is connection before anything else is sent
        -- the situation when member does not exist is an error
        -- member receiving x.grp.mem.fwd should have also received x.grp.mem.new prior to that.
        -- For now, this branch compensates for the lack of delayed message delivery.
        Nothing -> withStore $ \st -> createNewGroupMember st user group memInfo GCPostMember GSMemAnnounced
        Just m' -> pure m'
      withStore $ \st -> saveMemberInvitation st toMember introInv
      let msg = XGrpMemInfo (memberId (membership :: GroupMember)) profile
      groupConnId <- withAgent $ \a -> joinConnection a groupConnReq $ directMessage msg
      directConnId <- withAgent $ \a -> joinConnection a directConnReq $ directMessage msg
      withStore $ \st -> createIntroToMemberContact st userId m toMember groupConnId directConnId

    xGrpMemDel :: GroupName -> GroupMember -> MemberId -> m ()
    xGrpMemDel gName m memId = do
      Group {membership, members} <- withStore $ \st -> getGroup st user gName
      if memberId (membership :: GroupMember) == memId
        then do
          mapM_ deleteMemberConnection members
          withStore $ \st -> updateGroupMemberStatus st userId membership GSMemRemoved
          showDeletedMemberUser gName m
        else case find (sameMemberId memId) members of
          Nothing -> messageError "x.grp.mem.del with unknown member ID"
          Just member -> do
            let mRole = memberRole (m :: GroupMember)
            if mRole < GRAdmin || mRole < memberRole (member :: GroupMember)
              then messageError "x.grp.mem.del with insufficient member permissions"
              else do
                deleteMemberConnection member
                withStore $ \st -> updateGroupMemberStatus st userId member GSMemRemoved
                showDeletedMember gName (Just m) (Just member)

    sameMemberId :: MemberId -> GroupMember -> Bool
    sameMemberId memId GroupMember {memberId} = memId == memberId

    xGrpLeave :: GroupName -> GroupMember -> m ()
    xGrpLeave gName m = do
      deleteMemberConnection m
      withStore $ \st -> updateGroupMemberStatus st userId m GSMemLeft
      showLeftMember gName m

    xGrpDel :: GroupName -> GroupMember -> m ()
    xGrpDel gName m@GroupMember {memberRole} = do
      when (memberRole /= GROwner) $ chatError CEGroupUserRole
      ms <- withStore $ \st -> do
        Group {members, membership} <- getGroup st user gName
        updateGroupMemberStatus st userId membership GSMemGroupDeleted
        pure members
      mapM_ deleteMemberConnection ms
      showGroupDeleted gName m

parseChatMessage :: ByteString -> Either ChatError ChatMessage
parseChatMessage = first ChatErrorMessage . strDecode

sendFileChunk :: ChatMonad m => SndFileTransfer -> m ()
sendFileChunk ft@SndFileTransfer {fileId, fileStatus, agentConnId} =
  unless (fileStatus == FSComplete || fileStatus == FSCancelled) $
    withStore (`createSndFileChunk` ft) >>= \case
      Just chunkNo -> sendFileChunkNo ft chunkNo
      Nothing -> do
        withStore $ \st -> do
          updateSndFileStatus st ft FSComplete
          deleteSndFileChunks st ft
        showSndFileComplete ft
        closeFileHandle fileId sndFiles
        withAgent (`deleteConnection` agentConnId)

sendFileChunkNo :: ChatMonad m => SndFileTransfer -> Integer -> m ()
sendFileChunkNo ft@SndFileTransfer {agentConnId} chunkNo = do
  chunkBytes <- readFileChunk ft chunkNo
  msgId <- withAgent $ \a -> sendMessage a agentConnId $ smpEncode FileChunk {chunkNo, chunkBytes}
  withStore $ \st -> updateSndFileChunkMsg st ft chunkNo msgId

readFileChunk :: ChatMonad m => SndFileTransfer -> Integer -> m ByteString
readFileChunk SndFileTransfer {fileId, filePath, chunkSize} chunkNo =
  read_ `E.catch` (chatError . CEFileRead filePath)
  where
    read_ = do
      h <- getFileHandle fileId filePath sndFiles ReadMode
      pos <- hTell h
      let pos' = (chunkNo - 1) * chunkSize
      when (pos /= pos') $ hSeek h AbsoluteSeek pos'
      liftIO . B.hGet h $ fromInteger chunkSize

data FileChunk = FileChunk {chunkNo :: Integer, chunkBytes :: ByteString} | FileChunkCancel

instance Encoding FileChunk where
  smpEncode = \case
    FileChunk {chunkNo, chunkBytes} -> smpEncode ('F', fromIntegral chunkNo :: Word32, Tail chunkBytes)
    FileChunkCancel -> smpEncode 'C'
  smpP =
    smpP >>= \case
      'F' -> do
        chunkNo <- fromIntegral <$> smpP @Word32
        Tail chunkBytes <- smpP
        pure FileChunk {chunkNo, chunkBytes}
      'C' -> pure FileChunkCancel
      _ -> fail "bad FileChunk"

parseFileChunk :: ChatMonad m => ByteString -> m FileChunk
parseFileChunk msg =
  liftEither . first (ChatError . CEFileRcvChunk) $ parseAll smpP msg

appendFileChunk :: ChatMonad m => RcvFileTransfer -> Integer -> ByteString -> m ()
appendFileChunk ft@RcvFileTransfer {fileId, fileStatus} chunkNo chunk =
  case fileStatus of
    RFSConnected RcvFileInfo {filePath} -> append_ filePath
    RFSCancelled _ -> pure ()
    _ -> chatError $ CEFileInternal "receiving file transfer not in progress"
  where
    append_ fPath = do
      h <- getFileHandle fileId fPath rcvFiles AppendMode
      E.try (liftIO $ B.hPut h chunk >> hFlush h) >>= \case
        Left e -> chatError $ CEFileWrite fPath e
        Right () -> withStore $ \st -> updatedRcvFileChunkStored st ft chunkNo

getFileHandle :: ChatMonad m => Int64 -> FilePath -> (ChatController -> TVar (Map Int64 Handle)) -> IOMode -> m Handle
getFileHandle fileId filePath files ioMode = do
  fs <- asks files
  h_ <- M.lookup fileId <$> readTVarIO fs
  maybe (newHandle fs) pure h_
  where
    newHandle fs = do
      -- TODO handle errors
      h <- liftIO (openFile filePath ioMode)
      atomically . modifyTVar fs $ M.insert fileId h
      pure h

isFileActive :: ChatMonad m => Int64 -> (ChatController -> TVar (Map Int64 Handle)) -> m Bool
isFileActive fileId files = do
  fs <- asks files
  isJust . M.lookup fileId <$> readTVarIO fs

cancelRcvFileTransfer :: ChatMonad m => RcvFileTransfer -> m ()
cancelRcvFileTransfer ft@RcvFileTransfer {fileId, fileStatus} = do
  closeFileHandle fileId rcvFiles
  withStore $ \st -> do
    updateRcvFileStatus st ft FSCancelled
    deleteRcvFileChunks st ft
  case fileStatus of
    RFSAccepted RcvFileInfo {agentConnId} -> withAgent (`suspendConnection` agentConnId)
    RFSConnected RcvFileInfo {agentConnId} -> withAgent (`suspendConnection` agentConnId)
    _ -> pure ()

cancelSndFileTransfer :: ChatMonad m => SndFileTransfer -> m ()
cancelSndFileTransfer ft@SndFileTransfer {agentConnId, fileStatus} =
  unless (fileStatus == FSCancelled || fileStatus == FSComplete) $ do
    withStore $ \st -> do
      updateSndFileStatus st ft FSCancelled
      deleteSndFileChunks st ft
    withAgent $ \a -> do
      void (sendMessage a agentConnId $ smpEncode FileChunkCancel) `catchError` \_ -> pure ()
      suspendConnection a agentConnId

closeFileHandle :: ChatMonad m => Int64 -> (ChatController -> TVar (Map Int64 Handle)) -> m ()
closeFileHandle fileId files = do
  fs <- asks files
  h_ <- atomically . stateTVar fs $ \m -> (M.lookup fileId m, M.delete fileId m)
  mapM_ hClose h_ `E.catch` \(_ :: E.SomeException) -> pure ()

chatError :: ChatMonad m => ChatErrorType -> m a
chatError = throwError . ChatError

deleteMemberConnection :: ChatMonad m => GroupMember -> m ()
deleteMemberConnection m@GroupMember {activeConn} = do
  -- User {userId} <- asks currentUser
  withAgent $ forM_ (memberConnId m) . suspendConnection
  -- withStore $ \st -> deleteGroupMemberConnection st userId m
  forM_ activeConn $ \conn -> withStore $ \st -> updateConnectionStatus st conn ConnDeleted

sendDirectMessage :: ChatMonad m => Connection -> ChatMsgEvent -> m ()
sendDirectMessage conn chatMsgEvent = do
  let msgBody = directMessage chatMsgEvent
      newMsg = NewMessage {direction = MDSnd, chatMsgEventType = toChatEventTag chatMsgEvent, msgBody}
  -- can be done in transaction after sendMessage, probably shouldn't
  msgId <- withStore $ \st -> createNewMessage st newMsg
  deliverMessage conn msgBody msgId

directMessage :: ChatMsgEvent -> ByteString
directMessage chatMsgEvent = strEncode ChatMessage {chatMsgEvent}

deliverMessage :: ChatMonad m => Connection -> MsgBody -> MessageId -> m ()
deliverMessage Connection {connId, agentConnId} msgBody msgId = do
  agentMsgId <- withAgent $ \a -> sendMessage a agentConnId msgBody
  let sndMsgDelivery = SndMsgDelivery {connId, agentMsgId}
  withStore $ \st -> createSndMsgDelivery st sndMsgDelivery msgId

sendGroupMessage :: ChatMonad m => [GroupMember] -> ChatMsgEvent -> m ()
sendGroupMessage members chatMsgEvent = do
  let msgBody = directMessage chatMsgEvent
      newMsg = NewMessage {direction = MDSnd, chatMsgEventType = toChatEventTag chatMsgEvent, msgBody}
  msgId <- withStore $ \st -> createNewMessage st newMsg
  -- TODO once scheduled delivery is implemented memberActive should be changed to memberCurrent
  forM_ (map memberConn $ filter memberActive members) $
    traverse (\conn -> deliverMessage conn msgBody msgId)

saveRcvMSG :: ChatMonad m => Connection -> MsgMeta -> MsgBody -> m ChatMsgEvent
saveRcvMSG Connection {connId} agentMsgMeta msgBody = do
  ChatMessage {chatMsgEvent} <- liftEither $ parseChatMessage msgBody
  let newMsg = NewMessage {direction = MDRcv, chatMsgEventType = toChatEventTag chatMsgEvent, msgBody}
      agentMsgId = fst $ recipient agentMsgMeta
      rcvMsgDelivery = RcvMsgDelivery {connId, agentMsgId, agentMsgMeta}
  withStore $ \st -> createNewMessageAndRcvMsgDelivery st newMsg rcvMsgDelivery
  pure chatMsgEvent

allowAgentConnection :: ChatMonad m => Connection -> ConfirmationId -> ChatMsgEvent -> m ()
allowAgentConnection conn@Connection {agentConnId} confId msg = do
  withAgent $ \a -> allowConnection a agentConnId confId $ directMessage msg
  withStore $ \st -> updateConnectionStatus st conn ConnAccepted

getCreateActiveUser :: SQLiteStore -> IO User
getCreateActiveUser st = do
  user <-
    getUsers st >>= \case
      [] -> newUser
      users -> maybe (selectUser users) pure (find activeUser users)
  putStrLn $ "Current user: " <> userStr user
  pure user
  where
    newUser :: IO User
    newUser = do
      putStrLn
        "No user profiles found, it will be created now.\n\
        \Please choose your display name and your full name.\n\
        \They will be sent to your contacts when you connect.\n\
        \They are only stored on your device and you can change them later."
      loop
      where
        loop = do
          displayName <- getContactName
          fullName <- T.pack <$> getWithPrompt "full name (optional)"
          liftIO (runExceptT $ createUser st Profile {displayName, fullName} True) >>= \case
            Left SEDuplicateName -> do
              putStrLn "chosen display name is already used by another profile on this device, choose another one"
              loop
            Left e -> putStrLn ("database error " <> show e) >> exitFailure
            Right user -> pure user
    selectUser :: [User] -> IO User
    selectUser [user] = do
      liftIO $ setActiveUser st (userId user)
      pure user
    selectUser users = do
      putStrLn "Select user profile:"
      forM_ (zip [1 ..] users) $ \(n :: Int, user) -> putStrLn $ show n <> " - " <> userStr user
      loop
      where
        loop = do
          nStr <- getWithPrompt $ "user profile number (1 .. " <> show (length users) <> ")"
          case readMaybe nStr :: Maybe Int of
            Nothing -> putStrLn "invalid user number" >> loop
            Just n
              | n <= 0 || n > length users -> putStrLn "invalid user number" >> loop
              | otherwise -> do
                let user = users !! (n - 1)
                liftIO $ setActiveUser st (userId user)
                pure user
    userStr :: User -> String
    userStr User {localDisplayName, profile = Profile {fullName}} =
      T.unpack $ localDisplayName <> if T.null fullName || localDisplayName == fullName then "" else " (" <> fullName <> ")"
    getContactName :: IO ContactName
    getContactName = do
      displayName <- getWithPrompt "display name (no spaces)"
      if null displayName || isJust (find (== ' ') displayName)
        then putStrLn "display name has space(s), choose another one" >> getContactName
        else pure $ T.pack displayName
    getWithPrompt :: String -> IO String
    getWithPrompt s = putStr (s <> ": ") >> hFlush stdout >> getLine

showToast :: (MonadUnliftIO m, MonadReader ChatController m) => Text -> Text -> m ()
showToast title text = atomically . (`writeTBQueue` Notification {title, text}) =<< asks notifyQ

notificationSubscriber :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
notificationSubscriber = do
  ChatController {notifyQ, sendNotification} <- ask
  forever $ atomically (readTBQueue notifyQ) >>= liftIO . sendNotification

withAgent :: ChatMonad m => (AgentClient -> ExceptT AgentErrorType m a) -> m a
withAgent action =
  asks smpAgent
    >>= runExceptT . action
    >>= liftEither . first ChatErrorAgent

withStore ::
  ChatMonad m =>
  (forall m'. (MonadUnliftIO m', MonadError StoreError m') => SQLiteStore -> m' a) ->
  m a
withStore action =
  asks chatStore
    >>= runExceptT . action
    >>= liftEither . first ChatErrorStore

chatCommandP :: Parser ChatCommand
chatCommandP =
  ("/help files" <|> "/help file" <|> "/hf") $> FilesHelp
    <|> ("/help groups" <|> "/help group" <|> "/hg") $> GroupsHelp
    <|> ("/help address" <|> "/ha") $> MyAddressHelp
    <|> ("/help" <|> "/h") $> ChatHelp
    <|> ("/group #" <|> "/group " <|> "/g #" <|> "/g ") *> (NewGroup <$> groupProfile)
    <|> ("/add #" <|> "/add " <|> "/a #" <|> "/a ") *> (AddMember <$> displayName <* A.space <*> displayName <*> memberRole)
    <|> ("/join #" <|> "/join " <|> "/j #" <|> "/j ") *> (JoinGroup <$> displayName)
    <|> ("/remove #" <|> "/remove " <|> "/rm #" <|> "/rm ") *> (RemoveMember <$> displayName <* A.space <*> displayName)
    <|> ("/leave #" <|> "/leave " <|> "/l #" <|> "/l ") *> (LeaveGroup <$> displayName)
    <|> ("/delete #" <|> "/d #") *> (DeleteGroup <$> displayName)
    <|> ("/members #" <|> "/members " <|> "/ms #" <|> "/ms ") *> (ListMembers <$> displayName)
    <|> ("/groups" <|> "/gs") $> ListGroups
    <|> A.char '#' *> (SendGroupMessage <$> displayName <* A.space <*> A.takeByteString)
    <|> ("/contacts" <|> "/cs") $> ListContacts
    <|> ("/connect " <|> "/c ") *> (Connect <$> ((Just <$> strP) <|> A.takeByteString $> Nothing))
    <|> ("/connect" <|> "/c") $> AddContact
    <|> ("/delete @" <|> "/delete " <|> "/d @" <|> "/d ") *> (DeleteContact <$> displayName)
    <|> A.char '@' *> (SendMessage <$> displayName <*> (A.space *> A.takeByteString))
    <|> ("/file #" <|> "/f #") *> (SendGroupFile <$> displayName <* A.space <*> filePath)
    <|> ("/file @" <|> "/file " <|> "/f @" <|> "/f ") *> (SendFile <$> displayName <* A.space <*> filePath)
    <|> ("/freceive " <|> "/fr ") *> (ReceiveFile <$> A.decimal <*> optional (A.space *> filePath))
    <|> ("/fcancel " <|> "/fc ") *> (CancelFile <$> A.decimal)
    <|> ("/fstatus " <|> "/fs ") *> (FileStatus <$> A.decimal)
    <|> "/admin_welcome " *> (SendAdminWelcome <$> displayName)
    -- <|> "/admin" $> ConnectAdmin
    <|> ("/address" <|> "/ad") $> CreateMyAddress
    <|> ("/delete_address" <|> "/da") $> DeleteMyAddress
    <|> ("/show_address" <|> "/sa") $> ShowMyAddress
    <|> ("/accept @" <|> "/accept " <|> "/ac @" <|> "/ac ") *> (AcceptContact <$> displayName)
    <|> ("/reject @" <|> "/reject " <|> "/rc @" <|> "/rc ") *> (RejectContact <$> displayName)
    <|> ("/markdown" <|> "/m") $> MarkdownHelp
    <|> ("/welcome" <|> "/w") $> Welcome
    <|> ("/profile " <|> "/p ") *> (UpdateProfile <$> userProfile)
    <|> ("/profile" <|> "/p") $> ShowProfile
    <|> ("/quit" <|> "/q" <|> "/exit") $> QuitChat
    <|> ("/version" <|> "/v") $> ShowVersion
  where
    displayName = safeDecodeUtf8 <$> (B.cons <$> A.satisfy refChar <*> A.takeTill (== ' '))
    refChar c = c > ' ' && c /= '#' && c /= '@'
    userProfile = do
      cName <- displayName
      fullName <- fullNameP cName
      pure Profile {displayName = cName, fullName}
    groupProfile = do
      gName <- displayName
      fullName <- fullNameP gName
      pure GroupProfile {displayName = gName, fullName}
    fullNameP name = do
      n <- (A.space *> A.takeByteString) <|> pure ""
      pure $ if B.null n then name else safeDecodeUtf8 n
    filePath = T.unpack . safeDecodeUtf8 <$> A.takeByteString
    memberRole =
      (" owner" $> GROwner)
        <|> (" admin" $> GRAdmin)
        <|> (" member" $> GRMember)
        <|> pure GRAdmin

-- adminContactReq :: ConnReqContact
-- adminContactReq =
--   either error id $ parseAll connReqP' "https://simplex.chat/contact#/?smp=smp%3A%2F%2Fnxc7HnrnM8dOKgkMp008ub_9o9LXJlxlMrMpR-mfMQw%3D%40smp3.simplex.im%2F-TXnePw5eH5-4L7B%23&e2e=rsa%3AMIIBoDANBgkqhkiG9w0BAQEFAAOCAY0AMIIBiAKCAQEA6vpcsZggnYL38Qa2G5YU0W5uqnV8WAq_S3flIFU2kx4qW-aokVT8fo0CLJXv9aagdHObFfhc9SXcZPcm4T2NLnafKTgQa_HYFfj764l6cHkbSI-4JBE1gyhtaapsvrDGIdoiGDLgsF3AJVjqs8gavkuTsmw035aWMH-pkpc4qGlEWpNWp1Nn-7O4sdIIQ7yN48jsdCfeIY-BIk3kFR6s4oQOgiOcnir8e3x5tTuRMX1KWSiuzuqLHqgmcI1IqcPJPrBoTQLbXXEMGG1RsvIudxR03jejXXbQvlxXlNNrxwkniEe-P0rApGuCyv2NRMb4n0Wd3ZwewH7X-xtr16XNbQKBgDouGUHD1C55jB-w8W8VJRhFZS2xIYka9gJH1jjCFxHFzgjo69A_sObIamND1pF_JOzj_XCoA1fDICF95XbfS0rq9iS6xvX6M8Muq8QiJsfD5bRt5nh-Y3GK5rAFXS0ZtyOeh07iMLAMJ_EFxBQuKKDRu9_9KAvLL_plU0PuaMH3"
