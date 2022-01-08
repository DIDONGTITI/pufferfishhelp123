{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TupleSections #-}

module Simplex.Chat.Protocol where

import Control.Monad ((<=<), (>=>))
import Data.Aeson (FromJSON, ToJSON, (.:))
import qualified Data.Aeson as J
import qualified Data.Aeson.Types as JT
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Base64.URL as U
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.List (find, findIndex)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Simplex.Chat.Protocol.Encoding
import Simplex.Chat.Protocol.Legacy
import Simplex.Chat.Types
import Simplex.Chat.Types (GroupInvitation (GroupInvitation))
import Simplex.Chat.Util (safeDecodeUtf8)
import "simplexmq-legacy" Simplex.Messaging.Agent.Protocol
import Simplex.Messaging.Encoding.String (StrEncoding (..))
import "simplexmq" Simplex.Messaging.Parsers (parseAll)
import "simplexmq" Simplex.Messaging.Util (bshow)

data ChatDirection (p :: AParty) where
  ReceivedDirectMessage :: Connection -> Maybe Contact -> ChatDirection 'Agent
  SentDirectMessage :: Contact -> ChatDirection 'Client
  ReceivedGroupMessage :: Connection -> GroupName -> GroupMember -> ChatDirection 'Agent
  SentGroupMessage :: GroupName -> ChatDirection 'Client
  SndFileConnection :: Connection -> SndFileTransfer -> ChatDirection 'Agent
  RcvFileConnection :: Connection -> RcvFileTransfer -> ChatDirection 'Agent
  UserContactConnection :: Connection -> UserContact -> ChatDirection 'Agent

deriving instance Eq (ChatDirection p)

deriving instance Show (ChatDirection p)

fromConnection :: ChatDirection 'Agent -> Connection
fromConnection = \case
  ReceivedDirectMessage conn _ -> conn
  ReceivedGroupMessage conn _ _ -> conn
  SndFileConnection conn _ -> conn
  RcvFileConnection conn _ -> conn
  UserContactConnection conn _ -> conn

data ChatMsgEvent
  = XMsgNew MsgContent
  | XFile FileInvitation
  | XFileAcpt String
  | XInfo Profile
  | XContact Profile (Maybe MsgContent)
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
  deriving (Eq, Show)

data MessageType = MTText | MTImage deriving (Eq, Show)

data MsgContent = MsgContent
  { messageType :: MessageType,
    files :: [(ContentType, Int)],
    content :: [MsgContentBody]
  }
  deriving (Eq, Show)

toMsgType :: ByteString -> Either String MessageType
toMsgType = \case
  "c.text" -> Right MTText
  "c.image" -> Right MTImage
  t -> Left $ "invalid message type " <> B.unpack t

rawMsgType :: MessageType -> ByteString
rawMsgType = \case
  MTText -> "c.text"
  MTImage -> "c.image"

data ChatMessage = ChatMessage
  { chatMsgId :: ByteString,
    chatMsgEvent :: ChatMsgEvent,
    chatDAG :: Maybe ByteString
  }
  deriving (Eq, Show)

toChatEventType :: ChatMsgEvent -> Text
toChatEventType = \case
  XMsgNew _ -> "x.msg.new"
  XFile _ -> "x.file"
  XFileAcpt _ -> "x.file.acpt"
  XInfo _ -> "x.info"
  XContact _ _ -> "x.con"
  XGrpInv _ -> "x.grp.inv"
  XGrpAcpt _ -> "x.grp.acpt"
  XGrpMemNew _ -> "x.grp.mem.new"
  XGrpMemIntro _ -> "x.grp.mem.intro"
  XGrpMemInv _ _ -> "x.grp.mem.inv"
  XGrpMemFwd _ _ -> "x.grp.mem.fwd"
  XGrpMemInfo _ _ -> "x.grp.mem.info"
  XGrpMemCon _ -> "x.grp.mem.con"
  XGrpMemConAll _ -> "x.grp.mem.con.all"
  XGrpMemDel _ -> "x.grp.mem.del"
  XGrpLeave -> "x.grp.leave"
  XGrpDel -> "x.grp.del"
  XInfoProbe _ -> "x.info.probe"
  XInfoProbeCheck _ -> "x.info.probe.check"
  XInfoProbeOk _ -> "x.info.probe.ok"
  XOk -> "x.ok"

(.->) :: FromJSON a => JT.Parser JT.Object -> Text -> JT.Parser a
(.->) parser key = do
  obj <- parser
  obj .: key

appToChatMessage :: AppMessage -> Either String ChatMessage
appToChatMessage AppMessage {msgId, event, params, dag} = do
  chatMsgId <- U.decode $ encodeUtf8 msgId
  chatDAG <- mapM (U.decode . encodeUtf8) dag
  let chatMsg msg = pure ChatMessage {chatMsgId, chatMsgEvent = msg, chatDAG}
  case event of
    "x.msg.new" -> Left ""
    "x.file" -> do
      file <- JT.parseEither (.: "file") params
      chatMsg $ XFile file
    "x.file.acpt" -> do
      fileName <- JT.parseEither (.: "fileName") params
      chatMsg $ XFileAcpt fileName
    "x.info" -> do
      profile <- JT.parseEither (.: "profile") params
      chatMsg $ XInfo profile
    "x.con" -> Left ""
    "x.grp.inv" -> do
      groupInvitation <- JT.parseEither J.parseJSON $ J.Object params
      chatMsg $ XGrpInv groupInvitation
    "x.grp.acpt" -> do
      memberId <- JT.parseEither (.: "memberId") params
      chatMsg $ XGrpAcpt memberId
    "x.grp.mem.new" -> do
      memInfo <- JT.parseEither (.: "memberInfo") params
      chatMsg $ XGrpMemNew memInfo
    "x.grp.mem.intro" -> do
      memInfo <- JT.parseEither (.: "memberInfo") params
      chatMsg $ XGrpMemIntro memInfo
    "x.grp.mem.inv" -> do
      memberId <- JT.parseEither (.: "memberId") params
      memberIntro <- JT.parseEither (.: "memberIntro") params
      chatMsg $ XGrpMemInv memberId memberIntro
    "x.grp.mem.fwd" -> do
      memInfo <- JT.parseEither (.: "memberInfo") params
      memberIntro <- JT.parseEither (.: "memberIntro") params
      chatMsg $ XGrpMemFwd memInfo memberIntro
    "x.grp.mem.info" -> do
      memberId <- JT.parseEither (.: "memberId") params
      profile <- JT.parseEither (.: "profile") params
      chatMsg $ XGrpMemInfo memberId profile
    "x.grp.mem.con" -> do
      memberId <- JT.parseEither (.: "memberId") params
      chatMsg $ XGrpMemCon memberId
    "x.grp.mem.con.all" -> do
      memberId <- JT.parseEither (.: "memberId") params
      chatMsg $ XGrpMemConAll memberId
    "x.grp.mem.del" -> do
      memberId <- JT.parseEither (.: "memberId") params
      chatMsg $ XGrpMemDel memberId
    "x.grp.leave" -> chatMsg XGrpLeave
    "x.grp.del" -> chatMsg XGrpDel
    "x.info.probe" -> do
      probe <- JT.parseEither (.: "probe") params
      chatMsg $ XInfoProbe probe
    "x.info.probe.check" -> do
      probeHash <- JT.parseEither (.: "probeHash") params
      chatMsg $ XInfoProbeCheck probeHash
    "x.info.probe.ok" -> do
      probe <- JT.parseEither (.: "probe") params
      chatMsg $ XInfoProbeOk probe
    "x.ok" -> chatMsg XOk
    _ -> Left $ "bad syntax or unsupported event " <> T.unpack event

rawToChatMessage :: RawChatMessage -> Either String ChatMessage
rawToChatMessage RawChatMessage {chatMsgEvent, chatMsgParams, chatMsgBody} = do
  (chatDAG, body) <- getDAG <$> mapM toMsgBodyContent chatMsgBody
  let chatMsg msg = pure ChatMessage {chatMsgId = "", chatMsgEvent = msg, chatDAG}
  case (chatMsgEvent, chatMsgParams) of
    ("x.msg.new", mt : rawFiles) -> do
      t <- toMsgType mt
      files <- toFiles rawFiles
      chatMsg . XMsgNew $ MsgContent {messageType = t, files, content = body}
    ("x.file", [name, size, cReq]) -> do
      let fileName = T.unpack $ safeDecodeUtf8 name
      fileSize <- parseAll A.decimal size
      fileConnReq <- strDecode cReq
      chatMsg . XFile $ FileInvitation {fileName, fileSize, fileConnReq}
    ("x.file.acpt", [name]) ->
      chatMsg . XFileAcpt . T.unpack $ safeDecodeUtf8 name
    ("x.info", []) -> do
      profile <- getJSON body
      chatMsg $ XInfo profile
    ("x.con", []) -> do
      profile <- getJSON body
      chatMsg $ XContact profile Nothing
    ("x.con", mt : rawFiles) -> do
      (profile, body') <- extractJSON body
      t <- toMsgType mt
      files <- toFiles rawFiles
      chatMsg . XContact profile $ Just MsgContent {messageType = t, files, content = body'}
    ("x.grp.inv", [fromMemId, fromRole, memId, role, cReq]) -> do
      fromMem <- MemberIdRole <$> strDecode fromMemId <*> strDecode fromRole
      invitedMem <- MemberIdRole <$> strDecode memId <*> strDecode role
      groupConnReq <- strDecode cReq
      profile <- getJSON body
      chatMsg . XGrpInv $ GroupInvitation fromMem invitedMem groupConnReq profile
    ("x.grp.acpt", [memId]) ->
      chatMsg . XGrpAcpt =<< strDecode memId
    ("x.grp.mem.new", [memId, role]) -> do
      chatMsg . XGrpMemNew =<< toMemberInfo memId role body
    ("x.grp.mem.intro", [memId, role]) ->
      chatMsg . XGrpMemIntro =<< toMemberInfo memId role body
    ("x.grp.mem.inv", [memId, groupConnReq, directConnReq]) ->
      chatMsg =<< (XGrpMemInv <$> strDecode memId <*> toIntroInv groupConnReq directConnReq)
    ("x.grp.mem.fwd", [memId, role, groupConnReq, directConnReq]) -> do
      chatMsg =<< (XGrpMemFwd <$> toMemberInfo memId role body <*> toIntroInv groupConnReq directConnReq)
    ("x.grp.mem.info", [memId]) ->
      chatMsg =<< (XGrpMemInfo <$> strDecode memId <*> getJSON body)
    ("x.grp.mem.con", [memId]) ->
      chatMsg . XGrpMemCon =<< strDecode memId
    ("x.grp.mem.con.all", [memId]) ->
      chatMsg . XGrpMemConAll =<< strDecode memId
    ("x.grp.mem.del", [memId]) ->
      chatMsg . XGrpMemDel =<< strDecode memId
    ("x.grp.leave", []) ->
      chatMsg XGrpLeave
    ("x.grp.del", []) ->
      chatMsg XGrpDel
    ("x.info.probe", [probe]) -> do
      chatMsg . XInfoProbe =<< strDecode probe
    ("x.info.probe.check", [probeHash]) -> do
      chatMsg . XInfoProbeCheck =<< strDecode probeHash
    ("x.info.probe.ok", [probe]) -> do
      chatMsg . XInfoProbeOk =<< strDecode probe
    ("x.ok", []) ->
      chatMsg XOk
    _ -> Left $ "bad syntax or unsupported event " <> B.unpack chatMsgEvent
  where
    getDAG :: [MsgContentBody] -> (Maybe ByteString, [MsgContentBody])
    getDAG body = case break (isContentType SimplexDAG) body of
      (b, MsgContentBody SimplexDAG dag : a) -> (Just dag, b <> a)
      _ -> (Nothing, body)
    toMemberInfo :: ByteString -> ByteString -> [MsgContentBody] -> Either String MemberInfo
    toMemberInfo memId role body = MemberInfo <$> strDecode memId <*> strDecode role <*> getJSON body
    toIntroInv :: ByteString -> ByteString -> Either String IntroInvitation
    toIntroInv groupConnReq directConnReq = IntroInvitation <$> strDecode groupConnReq <*> strDecode directConnReq
    toContentInfo :: (RawContentType, Int) -> Either String (ContentType, Int)
    toContentInfo (rawType, size) = (,size) <$> toContentType rawType
    toFiles :: [ByteString] -> Either String [(ContentType, Int)]
    toFiles = mapM $ toContentInfo <=< parseAll contentInfoP
    getJSON :: FromJSON a => [MsgContentBody] -> Either String a
    getJSON = J.eitherDecodeStrict' <=< getSimplexContentType XCJson
    extractJSON :: FromJSON a => [MsgContentBody] -> Either String (a, [MsgContentBody])
    extractJSON =
      extractSimplexContentType XCJson >=> \(a, bs) -> do
        j <- J.eitherDecodeStrict' a
        pure (j, bs)

isContentType :: ContentType -> MsgContentBody -> Bool
isContentType t MsgContentBody {contentType = t'} = t == t'

isSimplexContentType :: XContentType -> MsgContentBody -> Bool
isSimplexContentType = isContentType . SimplexContentType

getContentType :: ContentType -> [MsgContentBody] -> Either String ByteString
getContentType t body = case find (isContentType t) body of
  Just MsgContentBody {contentData} -> Right contentData
  Nothing -> Left "no required content type"

extractContentType :: ContentType -> [MsgContentBody] -> Either String (ByteString, [MsgContentBody])
extractContentType t body = case findIndex (isContentType t) body of
  Just i -> case splitAt i body of
    (b, el : a) -> Right (contentData (el :: MsgContentBody), b ++ a)
    (_, []) -> Left "no required content type" -- this can only happen if findIndex returns incorrect result
  Nothing -> Left "no required content type"

getSimplexContentType :: XContentType -> [MsgContentBody] -> Either String ByteString
getSimplexContentType = getContentType . SimplexContentType

extractSimplexContentType :: XContentType -> [MsgContentBody] -> Either String (ByteString, [MsgContentBody])
extractSimplexContentType = extractContentType . SimplexContentType

chatMessageToRaw :: ChatMessage -> RawChatMessage
chatMessageToRaw ChatMessage {chatMsgEvent, chatDAG} =
  case chatMsgEvent of
    XMsgNew MsgContent {messageType = t, files, content} ->
      rawMsg (rawMsgType t : toRawFiles files) content
    XFile FileInvitation {fileName, fileSize, fileConnReq} ->
      rawMsg [encodeUtf8 $ T.pack fileName, bshow fileSize, strEncode fileConnReq] []
    XFileAcpt fileName ->
      rawMsg [encodeUtf8 $ T.pack fileName] []
    XInfo profile ->
      rawMsg [] [jsonBody profile]
    XContact profile Nothing ->
      rawMsg [] [jsonBody profile]
    XContact profile (Just MsgContent {messageType = t, files, content}) ->
      rawMsg (rawMsgType t : toRawFiles files) (jsonBody profile : content)
    XGrpInv (GroupInvitation (MemberIdRole fromMemId fromRole) (MemberIdRole memId role) cReq groupProfile) ->
      let params =
            [ strEncode fromMemId,
              strEncode fromRole,
              strEncode memId,
              strEncode role,
              strEncode cReq
            ]
       in rawMsg params [jsonBody groupProfile]
    XGrpAcpt memId ->
      rawMsg [strEncode memId] []
    XGrpMemNew (MemberInfo memId role profile) ->
      let params = [strEncode memId, strEncode role]
       in rawMsg params [jsonBody profile]
    XGrpMemIntro (MemberInfo memId role profile) ->
      rawMsg [strEncode memId, strEncode role] [jsonBody profile]
    XGrpMemInv memId IntroInvitation {groupConnReq, directConnReq} ->
      let params = [strEncode memId, strEncode groupConnReq, strEncode directConnReq]
       in rawMsg params []
    XGrpMemFwd (MemberInfo memId role profile) IntroInvitation {groupConnReq, directConnReq} ->
      let params =
            [ strEncode memId,
              strEncode role,
              strEncode groupConnReq,
              strEncode directConnReq
            ]
       in rawMsg params [jsonBody profile]
    XGrpMemInfo memId profile ->
      rawMsg [strEncode memId] [jsonBody profile]
    XGrpMemCon memId ->
      rawMsg [strEncode memId] []
    XGrpMemConAll memId ->
      rawMsg [strEncode memId] []
    XGrpMemDel memId ->
      rawMsg [strEncode memId] []
    XGrpLeave ->
      rawMsg [] []
    XGrpDel ->
      rawMsg [] []
    XInfoProbe probe ->
      rawMsg [strEncode probe] []
    XInfoProbeCheck probeHash ->
      rawMsg [strEncode probeHash] []
    XInfoProbeOk probe ->
      rawMsg [strEncode probe] []
    XOk ->
      rawMsg [] []
  where
    rawMsg :: [ByteString] -> [MsgContentBody] -> RawChatMessage
    rawMsg chatMsgParams body = do
      let event = encodeUtf8 $ toChatEventType chatMsgEvent
      RawChatMessage {chatMsgEvent = event, chatMsgParams, chatMsgBody = rawWithDAG body}
    rawContentInfo :: (ContentType, Int) -> (RawContentType, Int)
    rawContentInfo (t, size) = (rawContentType t, size)
    jsonBody :: ToJSON a => a -> MsgContentBody
    jsonBody x =
      let json = LB.toStrict $ J.encode x
       in MsgContentBody {contentType = SimplexContentType XCJson, contentData = json}
    rawWithDAG :: [MsgContentBody] -> [RawMsgBodyContent]
    rawWithDAG body = map rawMsgBodyContent $ case chatDAG of
      Nothing -> body
      Just dag -> MsgContentBody {contentType = SimplexDAG, contentData = dag} : body
    toRawFiles :: [(ContentType, Int)] -> [ByteString]
    toRawFiles = map $ serializeContentInfo . rawContentInfo

toMsgBodyContent :: RawMsgBodyContent -> Either String MsgContentBody
toMsgBodyContent RawMsgBodyContent {contentType, contentData} = do
  cType <- toContentType contentType
  pure MsgContentBody {contentType = cType, contentData}

rawMsgBodyContent :: MsgContentBody -> RawMsgBodyContent
rawMsgBodyContent MsgContentBody {contentType = t, contentData} =
  RawMsgBodyContent {contentType = rawContentType t, contentData}

data MsgContentBody = MsgContentBody
  { contentType :: ContentType,
    contentData :: ByteString
  }
  deriving (Eq, Show)

data ContentType
  = SimplexContentType XContentType
  | MimeContentType MContentType
  | SimplexDAG
  deriving (Eq, Show)

data XContentType = XCText | XCImage | XCJson deriving (Eq, Show)

data MContentType = MCImageJPG | MCImagePNG deriving (Eq, Show)

toContentType :: RawContentType -> Either String ContentType
toContentType (RawContentType ns cType) = case ns of
  "x" -> case cType of
    "text" -> Right $ SimplexContentType XCText
    "image" -> Right $ SimplexContentType XCImage
    "json" -> Right $ SimplexContentType XCJson
    "dag" -> Right SimplexDAG
    _ -> err
  "m" -> case cType of
    "image/jpg" -> Right $ MimeContentType MCImageJPG
    "image/png" -> Right $ MimeContentType MCImagePNG
    _ -> err
  _ -> err
  where
    err = Left . B.unpack $ "invalid content type " <> ns <> "." <> cType

rawContentType :: ContentType -> RawContentType
rawContentType t = case t of
  SimplexContentType t' -> RawContentType "x" $ case t' of
    XCText -> "text"
    XCImage -> "image"
    XCJson -> "json"
  MimeContentType t' -> RawContentType "m" $ case t' of
    MCImageJPG -> "image/jpg"
    MCImagePNG -> "image/png"
  SimplexDAG -> RawContentType "x" "dag"

newtype ContentMsg = NewContentMsg ContentData

newtype ContentData = ContentText Text

newtype MsgData = MsgData ByteString
  deriving (Eq, Show)
