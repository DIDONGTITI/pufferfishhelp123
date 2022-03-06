{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Simplex.Chat.Protocol where

import Control.Applicative ((<|>))
import Control.Monad ((<=<))
import Data.Aeson (FromJSON, ToJSON, (.:), (.:?), (.=))
import qualified Data.Aeson as J
import qualified Data.Aeson.Encoding as JE
import qualified Data.Aeson.KeyMap as JM
import qualified Data.Aeson.Types as JT
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Time.Clock (UTCTime)
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))
import GHC.Generics (Generic)
import Simplex.Chat.Types
import Simplex.Chat.Util (eitherToMaybe, safeDecodeUtf8)
import Simplex.Messaging.Agent.Store.SQLite (fromTextField_)
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Parsers (dropPrefix, taggedObjectJSON)
import Simplex.Messaging.Util ((<$?>))

data ConnectionEntity
  = RcvDirectMsgConnection {entityConnection :: Connection, contact :: Maybe Contact}
  | RcvGroupMsgConnection {entityConnection :: Connection, groupInfo :: GroupInfo, groupMember :: GroupMember}
  | SndFileConnection {entityConnection :: Connection, sndFileTransfer :: SndFileTransfer}
  | RcvFileConnection {entityConnection :: Connection, rcvFileTransfer :: RcvFileTransfer}
  | UserContactConnection {entityConnection :: Connection, userContact :: UserContact}
  deriving (Eq, Show)

updateEntityConnStatus :: ConnectionEntity -> ConnStatus -> ConnectionEntity
updateEntityConnStatus connEntity connStatus = case connEntity of
  RcvDirectMsgConnection c ct_ -> RcvDirectMsgConnection (st c) ((\ct -> (ct :: Contact) {activeConn = st c}) <$> ct_)
  RcvGroupMsgConnection c gInfo m@GroupMember {activeConn = c'} -> RcvGroupMsgConnection (st c) gInfo m {activeConn = st <$> c'}
  SndFileConnection c ft -> SndFileConnection (st c) ft
  RcvFileConnection c ft -> RcvFileConnection (st c) ft
  UserContactConnection c uc -> UserContactConnection (st c) uc
  where
    st c = c {connStatus}

-- chat message is sent as JSON with these properties
data AppMessage = AppMessage
  { msgId :: Maybe SharedMsgId,
    event :: Text,
    params :: J.Object
  }
  deriving (Generic, FromJSON)

instance ToJSON AppMessage where
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}

newtype SharedMsgId = SharedMsgId ByteString
  deriving (Eq, Show)

instance FromField SharedMsgId where fromField f = SharedMsgId <$> fromField f

instance ToField SharedMsgId where toField (SharedMsgId m) = toField m

instance StrEncoding SharedMsgId where
  strEncode (SharedMsgId m) = strEncode m
  strDecode s = SharedMsgId <$> strDecode s
  strP = SharedMsgId <$> strP

instance FromJSON SharedMsgId where
  parseJSON = strParseJSON "SharedMsgId"

instance ToJSON SharedMsgId where
  toJSON = strToJSON
  toEncoding = strToJEncoding

data MessageRef
  = MsgRefDirect
      { msgId :: SharedMsgId,
        sentAt :: UTCTime,
        sent :: Bool
      }
  | MsgRefGroup
      { msgId :: SharedMsgId,
        sentAt :: UTCTime,
        memberId :: MemberId
      }
  deriving (Eq, Show, Generic)

msgRefJSONOpts :: J.Options
msgRefJSONOpts = taggedObjectJSON $ dropPrefix "MsgRef"

instance FromJSON MessageRef where
  parseJSON = J.genericParseJSON msgRefJSONOpts

instance ToJSON MessageRef where
  toJSON = J.genericToJSON msgRefJSONOpts
  toEncoding = J.genericToEncoding msgRefJSONOpts

data ChatMessage = ChatMessage {msgId :: Maybe SharedMsgId, chatMsgEvent :: ChatMsgEvent}
  deriving (Eq, Show)

instance StrEncoding ChatMessage where
  strEncode = LB.toStrict . J.encode . chatToAppMessage
  strDecode = appToChatMessage <=< J.eitherDecodeStrict'
  strP = strDecode <$?> A.takeByteString

data ChatMsgEvent
  = XMsgNew MsgContent
  | XFile FileInvitation
  | XFileAcpt String
  | XInfo Profile
  | XContact Profile (Maybe XContactId)
  | XGrpInv GroupInvitation
  | XGrpAcpt MemberId
  | XGrpMemNew MemberInfo
  | XGrpMemIntro MemberInfo
  | XGrpMemInv MemberId IntroInvitation
  | XGrpMemFwd MemberInfo IntroInvitation
  | XGrpMemInfo MemberId Profile
  | XGrpMemCon MemberId
  | XGrpMemConAll MemberId
  | XGrpMemDel MemberId
  | XGrpLeave
  | XGrpDel
  | XInfoProbe Probe
  | XInfoProbeCheck ProbeHash
  | XInfoProbeOk Probe
  | XOk
  | XUnknown {event :: Text, params :: J.Object}
  deriving (Eq, Show)

data RepliedMsg = RepliedMsg {msgRef :: Maybe MessageRef, content :: MsgContent}
  deriving (Eq, Show, Generic, FromJSON)

instance ToJSON RepliedMsg where
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}

cmReplyToMsgRef :: ChatMsgEvent -> Maybe MessageRef
cmReplyToMsgRef = \case
  XMsgNew (MCReply (RepliedMsg {msgRef}) _) -> msgRef
  _ -> Nothing

data MsgContentTag = MCText_ | MCUnknown_ Text

instance StrEncoding MsgContentTag where
  strEncode = \case
    MCText_ -> "text"
    MCUnknown_ t -> encodeUtf8 t
  strDecode = \case
    "text" -> Right MCText_
    t -> Right . MCUnknown_ $ safeDecodeUtf8 t
  strP = strDecode <$?> A.takeTill (== ' ')

instance FromJSON MsgContentTag where
  parseJSON = strParseJSON "MsgContentType"

instance ToJSON MsgContentTag where
  toJSON = strToJSON
  toEncoding = strToJEncoding

data MsgContent
  = MCReply RepliedMsg MsgContent
  | MCForward MsgContent
  | MCText Text
  | MCUnknown {tag :: Text, text :: Text, json :: J.Value}
  deriving (Eq, Show)

msgContentText :: MsgContent -> Text
msgContentText = \case
  MCReply _ mc -> msgContentText mc
  MCForward mc -> msgContentText mc
  MCText t -> t
  MCUnknown {text} -> text

msgContentTag :: MsgContent -> MsgContentTag
msgContentTag = \case
  MCReply _ mc -> msgContentTag mc
  MCForward mc -> msgContentTag mc
  MCText _ -> MCText_
  MCUnknown {tag} -> MCUnknown_ tag

instance FromJSON MsgContent where
  parseJSON jv@(J.Object v) =
    v .: "type" >>= \case
      MCText_ -> mcMode $ MCText <$> v .: "text"
      MCUnknown_ tag -> mcMode $ do
        text <- fromMaybe unknownMsgType <$> v .:? "text"
        pure MCUnknown {tag, text, json = jv}
    where
      mcMode :: JT.Parser MsgContent -> JT.Parser MsgContent
      mcMode mc =
        MCReply <$> v .: "replyTo" <*> mc
          <|> (v .: "forward" >>= \f -> if f then MCForward <$> mc else mc)
          <|> mc
  parseJSON invalid =
    JT.prependFailure "bad MsgContent, " (JT.typeMismatch "Object" invalid)

unknownMsgType :: Text
unknownMsgType = "unknown message type"

instance ToJSON MsgContent where
  toJSON = \case
    MCUnknown {json} -> json
    mc -> J.object $ mcPairs mc
    where
      mcPairs :: MsgContent -> [JT.Pair]
      mcPairs = \case
        MCReply rm mc -> ("replyTo" .= rm) : mcPairs mc
        MCForward mc -> ("forward" .= True) : mcPairs mc
        MCText t -> ["type" .= ("text" :: Text), "text" .= t]
        MCUnknown {} -> []

  toEncoding = \case
    MCUnknown {json} -> JE.value json
    mc -> J.pairs $ mcPairs mc
    where
      mcPairs :: MsgContent -> JT.Series
      mcPairs = \case
        MCReply rm mc -> ("replyTo" .= rm) <> mcPairs mc
        MCForward mc -> ("forward" .= True) <> mcPairs mc
        MCText t -> "type" .= ("text" :: Text) <> "text" .= t
        MCUnknown {} -> mempty

data CMEventTag
  = XMsgNew_
  | XFile_
  | XFileAcpt_
  | XInfo_
  | XContact_
  | XGrpInv_
  | XGrpAcpt_
  | XGrpMemNew_
  | XGrpMemIntro_
  | XGrpMemInv_
  | XGrpMemFwd_
  | XGrpMemInfo_
  | XGrpMemCon_
  | XGrpMemConAll_
  | XGrpMemDel_
  | XGrpLeave_
  | XGrpDel_
  | XInfoProbe_
  | XInfoProbeCheck_
  | XInfoProbeOk_
  | XOk_
  | XUnknown_ Text
  deriving (Eq, Show)

instance StrEncoding CMEventTag where
  strEncode = \case
    XMsgNew_ -> "x.msg.new"
    XFile_ -> "x.file"
    XFileAcpt_ -> "x.file.acpt"
    XInfo_ -> "x.info"
    XContact_ -> "x.contact"
    XGrpInv_ -> "x.grp.inv"
    XGrpAcpt_ -> "x.grp.acpt"
    XGrpMemNew_ -> "x.grp.mem.new"
    XGrpMemIntro_ -> "x.grp.mem.intro"
    XGrpMemInv_ -> "x.grp.mem.inv"
    XGrpMemFwd_ -> "x.grp.mem.fwd"
    XGrpMemInfo_ -> "x.grp.mem.info"
    XGrpMemCon_ -> "x.grp.mem.con"
    XGrpMemConAll_ -> "x.grp.mem.con.all"
    XGrpMemDel_ -> "x.grp.mem.del"
    XGrpLeave_ -> "x.grp.leave"
    XGrpDel_ -> "x.grp.del"
    XInfoProbe_ -> "x.info.probe"
    XInfoProbeCheck_ -> "x.info.probe.check"
    XInfoProbeOk_ -> "x.info.probe.ok"
    XOk_ -> "x.ok"
    XUnknown_ t -> encodeUtf8 t
  strDecode = \case
    "x.msg.new" -> Right XMsgNew_
    "x.file" -> Right XFile_
    "x.file.acpt" -> Right XFileAcpt_
    "x.info" -> Right XInfo_
    "x.contact" -> Right XContact_
    "x.grp.inv" -> Right XGrpInv_
    "x.grp.acpt" -> Right XGrpAcpt_
    "x.grp.mem.new" -> Right XGrpMemNew_
    "x.grp.mem.intro" -> Right XGrpMemIntro_
    "x.grp.mem.inv" -> Right XGrpMemInv_
    "x.grp.mem.fwd" -> Right XGrpMemFwd_
    "x.grp.mem.info" -> Right XGrpMemInfo_
    "x.grp.mem.con" -> Right XGrpMemCon_
    "x.grp.mem.con.all" -> Right XGrpMemConAll_
    "x.grp.mem.del" -> Right XGrpMemDel_
    "x.grp.leave" -> Right XGrpLeave_
    "x.grp.del" -> Right XGrpDel_
    "x.info.probe" -> Right XInfoProbe_
    "x.info.probe.check" -> Right XInfoProbeCheck_
    "x.info.probe.ok" -> Right XInfoProbeOk_
    "x.ok" -> Right XOk_
    t -> Right . XUnknown_ $ safeDecodeUtf8 t
  strP = strDecode <$?> A.takeTill (== ' ')

toCMEventTag :: ChatMsgEvent -> CMEventTag
toCMEventTag = \case
  XMsgNew _ -> XMsgNew_
  XFile _ -> XFile_
  XFileAcpt _ -> XFileAcpt_
  XInfo _ -> XInfo_
  XContact _ _ -> XContact_
  XGrpInv _ -> XGrpInv_
  XGrpAcpt _ -> XGrpAcpt_
  XGrpMemNew _ -> XGrpMemNew_
  XGrpMemIntro _ -> XGrpMemIntro_
  XGrpMemInv _ _ -> XGrpMemInv_
  XGrpMemFwd _ _ -> XGrpMemFwd_
  XGrpMemInfo _ _ -> XGrpMemInfo_
  XGrpMemCon _ -> XGrpMemCon_
  XGrpMemConAll _ -> XGrpMemConAll_
  XGrpMemDel _ -> XGrpMemDel_
  XGrpLeave -> XGrpLeave_
  XGrpDel -> XGrpDel_
  XInfoProbe _ -> XInfoProbe_
  XInfoProbeCheck _ -> XInfoProbeCheck_
  XInfoProbeOk _ -> XInfoProbeOk_
  XOk -> XOk_
  XUnknown t _ -> XUnknown_ t

cmEventTagT :: Text -> Maybe CMEventTag
cmEventTagT = eitherToMaybe . strDecode . encodeUtf8

serializeCMEventTag :: CMEventTag -> Text
serializeCMEventTag = decodeLatin1 . strEncode

instance FromField CMEventTag where fromField = fromTextField_ cmEventTagT

instance ToField CMEventTag where toField = toField . serializeCMEventTag

appToChatMessage :: AppMessage -> Either String ChatMessage
appToChatMessage AppMessage {msgId, event, params} = do
  eventTag <- strDecode $ encodeUtf8 event
  chatMsgEvent <- msg eventTag
  pure ChatMessage {msgId, chatMsgEvent}
  where
    p :: FromJSON a => J.Key -> Either String a
    p key = JT.parseEither (.: key) params
    opt :: FromJSON a => J.Key -> Either String (Maybe a)
    opt key = JT.parseEither (.:? key) params
    msg = \case
      XMsgNew_ -> XMsgNew <$> p "content"
      XFile_ -> XFile <$> p "file"
      XFileAcpt_ -> XFileAcpt <$> p "fileName"
      XInfo_ -> XInfo <$> p "profile"
      XContact_ -> XContact <$> p "profile" <*> opt "contactReqId"
      XGrpInv_ -> XGrpInv <$> p "groupInvitation"
      XGrpAcpt_ -> XGrpAcpt <$> p "memberId"
      XGrpMemNew_ -> XGrpMemNew <$> p "memberInfo"
      XGrpMemIntro_ -> XGrpMemIntro <$> p "memberInfo"
      XGrpMemInv_ -> XGrpMemInv <$> p "memberId" <*> p "memberIntro"
      XGrpMemFwd_ -> XGrpMemFwd <$> p "memberInfo" <*> p "memberIntro"
      XGrpMemInfo_ -> XGrpMemInfo <$> p "memberId" <*> p "profile"
      XGrpMemCon_ -> XGrpMemCon <$> p "memberId"
      XGrpMemConAll_ -> XGrpMemConAll <$> p "memberId"
      XGrpMemDel_ -> XGrpMemDel <$> p "memberId"
      XGrpLeave_ -> pure XGrpLeave
      XGrpDel_ -> pure XGrpDel
      XInfoProbe_ -> XInfoProbe <$> p "probe"
      XInfoProbeCheck_ -> XInfoProbeCheck <$> p "probeHash"
      XInfoProbeOk_ -> XInfoProbeOk <$> p "probe"
      XOk_ -> pure XOk
      XUnknown_ t -> pure $ XUnknown t params

chatToAppMessage :: ChatMessage -> AppMessage
chatToAppMessage ChatMessage {msgId, chatMsgEvent} = AppMessage {msgId, event, params}
  where
    event = serializeCMEventTag . toCMEventTag $ chatMsgEvent
    o :: [(J.Key, J.Value)] -> J.Object
    o = JM.fromList
    key .=? value = maybe id ((:) . (key .=)) value
    params = case chatMsgEvent of
      XMsgNew content -> o $ ["content" .= content]
      XFile fileInv -> o ["file" .= fileInv]
      XFileAcpt fileName -> o ["fileName" .= fileName]
      XInfo profile -> o $ ["profile" .= profile]
      XContact profile xContactId -> o $ ("contactReqId" .=? xContactId) ["profile" .= profile]
      XGrpInv groupInv -> o ["groupInvitation" .= groupInv]
      XGrpAcpt memId -> o ["memberId" .= memId]
      XGrpMemNew memInfo -> o ["memberInfo" .= memInfo]
      XGrpMemIntro memInfo -> o ["memberInfo" .= memInfo]
      XGrpMemInv memId memIntro -> o ["memberId" .= memId, "memberIntro" .= memIntro]
      XGrpMemFwd memInfo memIntro -> o ["memberInfo" .= memInfo, "memberIntro" .= memIntro]
      XGrpMemInfo memId profile -> o ["memberId" .= memId, "profile" .= profile]
      XGrpMemCon memId -> o ["memberId" .= memId]
      XGrpMemConAll memId -> o ["memberId" .= memId]
      XGrpMemDel memId -> o ["memberId" .= memId]
      XGrpLeave -> JM.empty
      XGrpDel -> JM.empty
      XInfoProbe probe -> o ["probe" .= probe]
      XInfoProbeCheck probeHash -> o ["probeHash" .= probeHash]
      XInfoProbeOk probe -> o ["probe" .= probe]
      XOk -> JM.empty
      XUnknown _ ps -> ps
