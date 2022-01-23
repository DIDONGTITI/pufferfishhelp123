{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Simplex.Chat.Controller where

import Control.Exception
import Control.Monad.Except
import Control.Monad.IO.Unlift
import Control.Monad.Reader
import Crypto.Random (ChaChaDRG)
import Data.ByteString.Char8 (ByteString)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time.LocalTime (TimeZone)
import Numeric.Natural
import Simplex.Chat.Messages
import Simplex.Chat.Store (StoreError)
import Simplex.Chat.Styled
import Simplex.Chat.Types
import Simplex.Messaging.Agent (AgentClient)
import Simplex.Messaging.Agent.Env.SQLite (AgentConfig)
import Simplex.Messaging.Agent.Protocol
import Simplex.Messaging.Agent.Store.SQLite (SQLiteStore)
import Simplex.Messaging.Protocol (CorrId)
import System.IO (Handle)
import UnliftIO.STM

versionNumber :: String
versionNumber = "1.0.2"

versionStr :: String
versionStr = "SimpleX Chat v" <> versionNumber

updateStr :: String
updateStr = "To update run: curl -o- https://raw.githubusercontent.com/simplex-chat/simplex-chat/master/install.sh | bash"

data ChatConfig = ChatConfig
  { agentConfig :: AgentConfig,
    dbPoolSize :: Int,
    tbqSize :: Natural,
    fileChunkSize :: Integer
  }

data ActiveTo = ActiveNone | ActiveC ContactName | ActiveG GroupName
  deriving (Eq)

data ChatController = ChatController
  { currentUser :: TVar User,
    activeTo :: TVar ActiveTo,
    firstTime :: Bool,
    smpAgent :: AgentClient,
    chatStore :: SQLiteStore,
    idsDrg :: TVar ChaChaDRG,
    inputQ :: TBQueue String,
    outputQ :: TBQueue (CorrId, ChatResponse),
    notifyQ :: TBQueue Notification,
    sendNotification :: Notification -> IO (),
    chatLock :: TMVar (),
    sndFiles :: TVar (Map Int64 Handle),
    rcvFiles :: TVar (Map Int64 Handle),
    config :: ChatConfig
  }

data HelpSection = HSMain | HSFiles | HSGroups | HSMyAddress | HSMarkdown
  deriving (Show)

data ChatCommand
  = ChatHelp HelpSection
  | Welcome
  | AddContact
  | Connect (Maybe AConnectionRequestUri)
  | ConnectAdmin
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
  | ShowProfile
  | UpdateProfile Profile
  | QuitChat
  | ShowVersion
  deriving (Show)

data ChatResponse
  = ChatResponse [StyledString]
  | CRSentMessage ContactName TimeZone ChatUserMessage
  | CRSentGroupMessage GroupName TimeZone ChatUserMessage
  | CRReceivedMessage ContactName TimeZone ChatUserMessage MsgIntegrity
  | CRReceivedGroupMessage GroupName ContactName TimeZone ChatUserMessage MsgIntegrity
  | CRCommandAccepted CorrId
  | CRChatHelp HelpSection
  | CRWelcome User
  | CRContactsList [Contact]
  | CRUserContactLink ConnReqContact
  | CRContactRequestRejected ContactName
  | CRGroupCreated Group
  | CRGroupMembers Group
  | CRGroupsList [GroupInfo]
  | CRSentGroupInvitation GroupName ContactName
  | CRFileTransferStatus (FileTransfer, [Integer])
  | CRUserProfile Profile
  | CRUserProfileNoChange
  | CRVersionInfo
  | CRInvitation ConnReqInvitation
  | CRSentConfirmation
  | CRSentInvitation
  | CRContactDeleted ContactName
  | CRUserContactLinkCreated ConnReqContact
  | CRUserContactLinkDeleted
  | CRReceivedContactRequest ContactName Profile
  | CRAcceptingContactRequest ContactName
  | CRLeftMemberUser GroupName
  | CRGroupDeletedUser GroupName
  | CRRcvFileAccepted RcvFileTransfer FilePath
  | CRRcvFileSndCancelled RcvFileTransfer
  | CRRcvFileStart RcvFileTransfer
  | CRRcvFileComplete RcvFileTransfer
  | CRRcvFileCancelled RcvFileTransfer
  | CRSndFileStart SndFileTransfer
  | CRSndFileComplete SndFileTransfer
  | CRSndFileCancelled SndFileTransfer
  | CRSndFileRcvCancelled SndFileTransfer
  | CRSndGroupFileCancelled [SndFileTransfer]
  | CRUserProfileUpdated {from :: Profile, to :: Profile}
  | CRContactConnected Contact
  | CRContactAnotherClient ContactName
  | CRContactDisconnected ContactName
  | CRContactSubscribed ContactName
  | CRContactSubError ContactName ChatError
  | CRGroupInvitation Group
  | CRUserJoinedGroup GroupName
  | CRJoinedGroupMember GroupName GroupMember
  | CRJoinedGroupMemberConnecting {group :: GroupName, hostMember :: GroupMember, member :: GroupMember}
  | CRConnectedToGroupMember GroupName GroupMember
  | CRDeletedMember {group :: GroupName, byMember :: Maybe GroupMember, deletedMember :: Maybe GroupMember}
  | CRDeletedMemberUser GroupName GroupMember
  | CRLeftMember GroupName GroupMember
  | CRGroupEmpty Group
  | CRGroupRemoved Group
  | CRMemberSubError GroupName ContactName ChatError
  | CRGroupSubscribed Group
  | CRSndFileSubError SndFileTransfer ChatError
  | CRRcvFileSubError RcvFileTransfer ChatError
  | CRUserContactLinkSubscribed
  | CRUserContactLinkSubError ChatError
  | CRMessageError Text Text
  | CRChatCmdError ChatError
  | CRChatError ChatError
  deriving (Show)

data ChatError
  = ChatError ChatErrorType
  | ChatErrorMessage String
  | ChatErrorAgent AgentErrorType
  | ChatErrorStore StoreError
  deriving (Show, Exception)

data ChatErrorType
  = CEGroupUserRole
  | CEInvalidConnReq
  | CEContactGroups ContactName [GroupName]
  | CEGroupContactRole ContactName
  | CEGroupDuplicateMember ContactName
  | CEGroupDuplicateMemberId
  | CEGroupNotJoined GroupName
  | CEGroupMemberNotActive
  | CEGroupMemberUserRemoved
  | CEGroupMemberNotFound ContactName
  | CEGroupCantResendInvitation GroupName ContactName
  | CEGroupInternal String
  | CEFileNotFound String
  | CEFileAlreadyReceiving String
  | CEFileAlreadyExists FilePath
  | CEFileRead FilePath SomeException
  | CEFileWrite FilePath SomeException
  | CEFileSend Int64 AgentErrorType
  | CEFileRcvChunk String
  | CEFileInternal String
  | CEAgentVersion
  | CECommandError String
  deriving (Show, Exception)

type ChatMonad m = (MonadUnliftIO m, MonadReader ChatController m, MonadError ChatError m)

setActive :: (MonadUnliftIO m, MonadReader ChatController m) => ActiveTo -> m ()
setActive to = asks activeTo >>= atomically . (`writeTVar` to)

unsetActive :: (MonadUnliftIO m, MonadReader ChatController m) => ActiveTo -> m ()
unsetActive a = asks activeTo >>= atomically . (`modifyTVar` unset)
  where
    unset a' = if a == a' then ActiveNone else a'
