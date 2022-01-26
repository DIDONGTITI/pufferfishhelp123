{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}

module Simplex.Chat.Messages where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as J
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeLatin1)
import Data.Time.Clock (UTCTime)
import Data.Time.LocalTime (ZonedTime)
import Data.Type.Equality
import Data.Typeable (Typeable)
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))
import GHC.Generics (Generic)
import Simplex.Chat.Protocol
import Simplex.Chat.Types
import Simplex.Messaging.Agent.Protocol (AgentMsgId, MsgIntegrity, MsgMeta (..))
import Simplex.Messaging.Agent.Store.SQLite (fromTextField_)
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Parsers (dropPrefix, sumTypeJSON)
import Simplex.Messaging.Protocol (MsgBody)

data ChatType = CTDirect | CTGroup
  deriving (Show)

data ChatInfo (c :: ChatType) where
  DirectChat :: Contact -> ChatInfo 'CTDirect
  GroupChat :: GroupInfo -> ChatInfo 'CTGroup

deriving instance Show (ChatInfo c)

data JSONChatInfo
  = JCInfoDirect {contact :: Contact}
  | JCInfoGroup {groupInfo :: GroupInfo}
  deriving (Generic)

instance ToJSON JSONChatInfo where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCInfo"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCInfo"

instance ToJSON (ChatInfo c) where
  toJSON = J.toJSON . jsonChatInfo
  toEncoding = J.toEncoding . jsonChatInfo

jsonChatInfo :: ChatInfo c -> JSONChatInfo
jsonChatInfo = \case
  DirectChat c -> JCInfoDirect c
  GroupChat g -> JCInfoGroup g

type ChatItemData d = (CIMeta d, CIContent d)

data ChatItem (c :: ChatType) (d :: MsgDirection) where
  DirectChatItem :: CIMeta d -> CIContent d -> ChatItem 'CTDirect d
  SndGroupChatItem :: CIMeta 'MDSnd -> CIContent 'MDSnd -> ChatItem 'CTGroup 'MDSnd
  RcvGroupChatItem :: GroupMember -> CIMeta 'MDRcv -> CIContent 'MDRcv -> ChatItem 'CTGroup 'MDRcv

deriving instance Show (ChatItem c d)

data JSONChatItem d
  = JCItemDirect {meta :: CIMeta d, content :: CIContent d}
  | JCItemSndGroup {meta :: CIMeta d, content :: CIContent d}
  | JCItemRcvGroup {member :: GroupMember, meta :: CIMeta d, content :: CIContent d}
  deriving (Generic)

instance ToJSON (JSONChatItem d) where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCItem"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCItem"

instance ToJSON (ChatItem c d) where
  toJSON = J.toJSON . jsonChatItem
  toEncoding = J.toEncoding . jsonChatItem

jsonChatItem :: ChatItem c d -> JSONChatItem d
jsonChatItem = \case
  DirectChatItem meta cic -> JCItemDirect meta cic
  SndGroupChatItem meta cic -> JCItemSndGroup meta cic
  RcvGroupChatItem m meta cic -> JCItemRcvGroup m meta cic

data CChatItem c = forall d. CChatItem (SMsgDirection d) (ChatItem c d)

deriving instance Show (CChatItem c)

chatItemId :: ChatItem c d -> ChatItemId
chatItemId = \case
  DirectChatItem (CISndMeta CIMetaProps {itemId}) _ -> itemId
  DirectChatItem (CIRcvMeta CIMetaProps {itemId} _) _ -> itemId
  SndGroupChatItem (CISndMeta CIMetaProps {itemId}) _ -> itemId
  RcvGroupChatItem _ (CIRcvMeta CIMetaProps {itemId} _) _ -> itemId

data ChatDirection (c :: ChatType) (d :: MsgDirection) where
  CDDirect :: Contact -> ChatDirection 'CTDirect d
  CDSndGroup :: GroupInfo -> ChatDirection 'CTGroup 'MDSnd
  CDRcvGroup :: GroupInfo -> GroupMember -> ChatDirection 'CTGroup 'MDRcv

data NewChatItem d = NewChatItem
  { createdByMsgId_ :: Maybe MessageId,
    itemSent :: MsgDirection,
    itemTs :: ChatItemTs,
    itemContent :: CIContent d,
    itemText :: Text,
    createdAt :: UTCTime
  }
  deriving (Show)

-- | type to show one chat with messages
data Chat c = Chat (ChatInfo c) [CChatItem c]
  deriving (Show)

-- | type to show the list of chats, with one last message in each
data AChatPreview = forall c. AChatPreview (SChatType c) (ChatInfo c) (Maybe (CChatItem c))

deriving instance Show AChatPreview

-- | type to show a mix of messages from multiple chats
data AChatItem = forall c d. AChatItem (SChatType c) (SMsgDirection d) (ChatInfo c) (ChatItem c d)

deriving instance Show AChatItem

instance ToJSON AChatItem where
  toJSON (AChatItem _ _ chat item) = J.toJSON $ JSONAnyChatItem chat item
  toEncoding (AChatItem _ _ chat item) = J.toEncoding $ JSONAnyChatItem chat item

data JSONAnyChatItem c d = JSONAnyChatItem {chatInfo :: ChatInfo c, chatItem :: ChatItem c d}
  deriving (Generic)

instance ToJSON (JSONAnyChatItem c d) where
  toJSON = J.genericToJSON J.defaultOptions
  toEncoding = J.genericToEncoding J.defaultOptions

data CIMeta (d :: MsgDirection) where
  CISndMeta :: CIMetaProps -> CIMeta 'MDSnd
  CIRcvMeta :: CIMetaProps -> MsgIntegrity -> CIMeta 'MDRcv

deriving instance Show (CIMeta d)

instance ToJSON (CIMeta d) where
  toJSON = J.toJSON . jsonCIMeta
  toEncoding = J.toEncoding . jsonCIMeta

data JSONCIMeta
  = JCIMetaSnd {meta :: CIMetaProps}
  | JCIMetaRcv {meta :: CIMetaProps, integrity :: MsgIntegrity}
  deriving (Generic)

instance ToJSON JSONCIMeta where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCIMeta"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCIMeta"

jsonCIMeta :: CIMeta d -> JSONCIMeta
jsonCIMeta = \case
  CISndMeta meta -> JCIMetaSnd meta
  CIRcvMeta meta integrity -> JCIMetaRcv meta integrity

data CIMetaProps = CIMetaProps
  { itemId :: ChatItemId,
    itemTs :: ChatItemTs,
    localItemTs :: ZonedTime,
    createdAt :: UTCTime
  }
  deriving (Show, Generic, FromJSON)

instance ToJSON CIMetaProps where toEncoding = J.genericToEncoding J.defaultOptions

type ChatItemId = Int64

type ChatItemTs = UTCTime

data CIContent (d :: MsgDirection) where
  CIMsgContent :: MsgContent -> CIContent d
  CISndFileInvitation :: FileTransferId -> FilePath -> CIContent 'MDSnd
  CIRcvFileInvitation :: RcvFileTransfer -> CIContent 'MDRcv

deriving instance Show (CIContent d)

instance ToField (CIContent d) where toField = toField . decodeLatin1 . LB.toStrict . J.encode

instance ToJSON (CIContent d) where
  toJSON = J.toJSON . jsonCIContent
  toEncoding = J.toEncoding . jsonCIContent

data JSONCIContent
  = JCIMsgContent {msgContent :: MsgContent}
  | JCISndFileInvitation {fileId :: FileTransferId, filePath :: FilePath}
  | JCIRcvFileInvitation {rcvFileTransfer :: RcvFileTransfer}
  deriving (Generic)

instance ToJSON JSONCIContent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCI"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCI"

jsonCIContent :: CIContent d -> JSONCIContent
jsonCIContent = \case
  CIMsgContent mc -> JCIMsgContent mc
  CISndFileInvitation fId fPath -> JCISndFileInvitation fId fPath
  CIRcvFileInvitation ft -> JCIRcvFileInvitation ft

ciContentToText :: CIContent d -> Text
ciContentToText = \case
  CIMsgContent mc -> msgContentText mc
  CISndFileInvitation fId fPath -> "you sent file #" <> T.pack (show fId) <> ": " <> T.pack fPath
  CIRcvFileInvitation RcvFileTransfer {fileInvitation = FileInvitation {fileName}} -> "file " <> T.pack fileName

data SChatType (c :: ChatType) where
  SCTDirect :: SChatType 'CTDirect
  SCTGroup :: SChatType 'CTGroup

deriving instance Show (SChatType c)

instance TestEquality SChatType where
  testEquality SCTDirect SCTDirect = Just Refl
  testEquality SCTGroup SCTGroup = Just Refl
  testEquality _ _ = Nothing

class ChatTypeI (c :: ChatType) where
  chatType :: SChatType c

instance ChatTypeI 'CTDirect where chatType = SCTDirect

instance ChatTypeI 'CTGroup where chatType = SCTGroup

data NewMessage = NewMessage
  { direction :: MsgDirection,
    cmEventTag :: CMEventTag,
    msgBody :: MsgBody
  }
  deriving (Show)

data PendingGroupMessage = PendingGroupMessage
  { msgId :: MessageId,
    cmEventTag :: CMEventTag,
    msgBody :: MsgBody,
    introId_ :: Maybe Int64
  }

type MessageId = Int64

data MsgDirection = MDRcv | MDSnd
  deriving (Show)

data SMsgDirection (d :: MsgDirection) where
  SMDRcv :: SMsgDirection 'MDRcv
  SMDSnd :: SMsgDirection 'MDSnd

deriving instance Show (SMsgDirection d)

instance TestEquality SMsgDirection where
  testEquality SMDRcv SMDRcv = Just Refl
  testEquality SMDSnd SMDSnd = Just Refl
  testEquality _ _ = Nothing

class MsgDirectionI (d :: MsgDirection) where
  msgDirection :: SMsgDirection d

instance MsgDirectionI 'MDRcv where msgDirection = SMDRcv

instance MsgDirectionI 'MDSnd where msgDirection = SMDSnd

instance ToField MsgDirection where toField = toField . msgDirectionInt

msgDirectionInt :: MsgDirection -> Int
msgDirectionInt = \case
  MDRcv -> 0
  MDSnd -> 1

msgDirectionIntP :: Int -> Maybe MsgDirection
msgDirectionIntP = \case
  0 -> Just MDRcv
  1 -> Just MDSnd
  _ -> Nothing

data SndMsgDelivery = SndMsgDelivery
  { connId :: Int64,
    agentMsgId :: AgentMsgId
  }

data RcvMsgDelivery = RcvMsgDelivery
  { connId :: Int64,
    agentMsgId :: AgentMsgId,
    agentMsgMeta :: MsgMeta
  }

data MsgMetaJSON = MsgMetaJSON
  { integrity :: Text,
    rcvId :: Int64,
    rcvTs :: UTCTime,
    serverId :: Text,
    serverTs :: UTCTime,
    sndId :: Int64
  }
  deriving (Eq, Show, FromJSON, Generic)

instance ToJSON MsgMetaJSON where toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

msgMetaToJson :: MsgMeta -> MsgMetaJSON
msgMetaToJson MsgMeta {integrity, recipient = (rcvId, rcvTs), broker = (serverId, serverTs), sndMsgId = sndId} =
  MsgMetaJSON
    { integrity = (decodeLatin1 . strEncode) integrity,
      rcvId,
      rcvTs,
      serverId = (decodeLatin1 . B64.encode) serverId,
      serverTs,
      sndId
    }

msgMetaJson :: MsgMeta -> Text
msgMetaJson = decodeLatin1 . LB.toStrict . J.encode . msgMetaToJson

data MsgDeliveryStatus (d :: MsgDirection) where
  MDSRcvAgent :: MsgDeliveryStatus 'MDRcv
  MDSRcvAcknowledged :: MsgDeliveryStatus 'MDRcv
  MDSSndPending :: MsgDeliveryStatus 'MDSnd
  MDSSndAgent :: MsgDeliveryStatus 'MDSnd
  MDSSndSent :: MsgDeliveryStatus 'MDSnd
  MDSSndReceived :: MsgDeliveryStatus 'MDSnd
  MDSSndRead :: MsgDeliveryStatus 'MDSnd

data AMsgDeliveryStatus = forall d. AMDS (SMsgDirection d) (MsgDeliveryStatus d)

instance (Typeable d, MsgDirectionI d) => FromField (MsgDeliveryStatus d) where
  fromField = fromTextField_ msgDeliveryStatusT'

instance ToField (MsgDeliveryStatus d) where toField = toField . serializeMsgDeliveryStatus

serializeMsgDeliveryStatus :: MsgDeliveryStatus d -> Text
serializeMsgDeliveryStatus = \case
  MDSRcvAgent -> "rcv_agent"
  MDSRcvAcknowledged -> "rcv_acknowledged"
  MDSSndPending -> "snd_pending"
  MDSSndAgent -> "snd_agent"
  MDSSndSent -> "snd_sent"
  MDSSndReceived -> "snd_received"
  MDSSndRead -> "snd_read"

msgDeliveryStatusT :: Text -> Maybe AMsgDeliveryStatus
msgDeliveryStatusT = \case
  "rcv_agent" -> Just $ AMDS SMDRcv MDSRcvAgent
  "rcv_acknowledged" -> Just $ AMDS SMDRcv MDSRcvAcknowledged
  "snd_pending" -> Just $ AMDS SMDSnd MDSSndPending
  "snd_agent" -> Just $ AMDS SMDSnd MDSSndAgent
  "snd_sent" -> Just $ AMDS SMDSnd MDSSndSent
  "snd_received" -> Just $ AMDS SMDSnd MDSSndReceived
  "snd_read" -> Just $ AMDS SMDSnd MDSSndRead
  _ -> Nothing

msgDeliveryStatusT' :: forall d. MsgDirectionI d => Text -> Maybe (MsgDeliveryStatus d)
msgDeliveryStatusT' s =
  msgDeliveryStatusT s >>= \(AMDS d st) ->
    case testEquality d (msgDirection @d) of
      Just Refl -> Just st
      _ -> Nothing
