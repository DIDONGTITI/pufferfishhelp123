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

module Simplex.Chat.Messages.CIContent where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as J
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Type.Equality
import Data.Typeable (Typeable)
import Data.Word (Word32)
import Database.SQLite.Simple (ResultError (..), SQLData (..))
import Database.SQLite.Simple.FromField (Field, FromField (..), returnError)
import Database.SQLite.Simple.Internal (Field (..))
import Database.SQLite.Simple.Ok
import Database.SQLite.Simple.ToField (ToField (..))
import GHC.Generics (Generic)
import Simplex.Chat.Protocol
import Simplex.Chat.Types
import Simplex.Messaging.Agent.Protocol (MsgErrorType (..), RatchetSyncState (..), SwitchPhase (..))
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Parsers (dropPrefix, enumJSON, fstToLower, singleFieldJSON, sumTypeJSON)
import Simplex.Messaging.Util (safeDecodeUtf8, tshow)

data MsgDirection = MDRcv | MDSnd
  deriving (Eq, Show, Generic)

instance FromJSON MsgDirection where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "MD"

instance ToJSON MsgDirection where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "MD"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "MD"

instance FromField AMsgDirection where fromField = fromIntField_ $ fmap fromMsgDirection . msgDirectionIntP

instance ToField MsgDirection where toField = toField . msgDirectionInt

fromIntField_ :: (Typeable a) => (Int64 -> Maybe a) -> Field -> Ok a
fromIntField_ fromInt = \case
  f@(Field (SQLInteger i) _) ->
    case fromInt i of
      Just x -> Ok x
      _ -> returnError ConversionFailed f ("invalid integer: " <> show i)
  f -> returnError ConversionFailed f "expecting SQLInteger column type"

data SMsgDirection (d :: MsgDirection) where
  SMDRcv :: SMsgDirection 'MDRcv
  SMDSnd :: SMsgDirection 'MDSnd

deriving instance Show (SMsgDirection d)

instance TestEquality SMsgDirection where
  testEquality SMDRcv SMDRcv = Just Refl
  testEquality SMDSnd SMDSnd = Just Refl
  testEquality _ _ = Nothing

instance ToField (SMsgDirection d) where toField = toField . msgDirectionInt . toMsgDirection

data AMsgDirection = forall d. MsgDirectionI d => AMsgDirection (SMsgDirection d)

deriving instance Show AMsgDirection

toMsgDirection :: SMsgDirection d -> MsgDirection
toMsgDirection = \case
  SMDRcv -> MDRcv
  SMDSnd -> MDSnd

fromMsgDirection :: MsgDirection -> AMsgDirection
fromMsgDirection = \case
  MDRcv -> AMsgDirection SMDRcv
  MDSnd -> AMsgDirection SMDSnd

class MsgDirectionI (d :: MsgDirection) where
  msgDirection :: SMsgDirection d

instance MsgDirectionI 'MDRcv where msgDirection = SMDRcv

instance MsgDirectionI 'MDSnd where msgDirection = SMDSnd

msgDirectionInt :: MsgDirection -> Int
msgDirectionInt = \case
  MDRcv -> 0
  MDSnd -> 1

msgDirectionIntP :: Int64 -> Maybe MsgDirection
msgDirectionIntP = \case
  0 -> Just MDRcv
  1 -> Just MDSnd
  _ -> Nothing

data CIDeleteMode = CIDMBroadcast | CIDMInternal
  deriving (Show, Generic)

instance ToJSON CIDeleteMode where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CIDM"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CIDM"

instance FromJSON CIDeleteMode where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CIDM"

ciDeleteModeToText :: CIDeleteMode -> Text
ciDeleteModeToText = \case
  CIDMBroadcast -> "this item is deleted (broadcast)"
  CIDMInternal -> "this item is deleted (internal)"

-- This type is used both in API and in DB, so we use different JSON encodings for the database and for the API
-- ! Nested sum types also have to use different encodings for database and API
-- ! to avoid breaking cross-platform compatibility, see RcvGroupEvent and SndGroupEvent
data CIContent (d :: MsgDirection) where
  CISndMsgContent :: MsgContent -> CIContent 'MDSnd
  CIRcvMsgContent :: MsgContent -> CIContent 'MDRcv
  CISndDeleted :: CIDeleteMode -> CIContent 'MDSnd -- legacy - since v4.3.0 item_deleted field is used
  CIRcvDeleted :: CIDeleteMode -> CIContent 'MDRcv -- legacy - since v4.3.0 item_deleted field is used
  CISndCall :: CICallStatus -> Int -> CIContent 'MDSnd
  CIRcvCall :: CICallStatus -> Int -> CIContent 'MDRcv
  CIRcvIntegrityError :: MsgErrorType -> CIContent 'MDRcv
  CIRcvDecryptionError :: MsgDecryptError -> Word32 -> Maybe Bool -> CIContent 'MDRcv
  CIRcvGroupInvitation :: CIGroupInvitation -> GroupMemberRole -> CIContent 'MDRcv
  CISndGroupInvitation :: CIGroupInvitation -> GroupMemberRole -> CIContent 'MDSnd
  CIRcvGroupEvent :: RcvGroupEvent -> CIContent 'MDRcv
  CISndGroupEvent :: SndGroupEvent -> CIContent 'MDSnd
  CIRcvConnEvent :: RcvConnEvent -> CIContent 'MDRcv
  CISndConnEvent :: SndConnEvent -> CIContent 'MDSnd
  CIRcvChatFeature :: ChatFeature -> PrefEnabled -> Maybe Int -> CIContent 'MDRcv
  CISndChatFeature :: ChatFeature -> PrefEnabled -> Maybe Int -> CIContent 'MDSnd
  CIRcvChatPreference :: ChatFeature -> FeatureAllowed -> Maybe Int -> CIContent 'MDRcv
  CISndChatPreference :: ChatFeature -> FeatureAllowed -> Maybe Int -> CIContent 'MDSnd
  CIRcvGroupFeature :: GroupFeature -> GroupPreference -> Maybe Int -> CIContent 'MDRcv
  CISndGroupFeature :: GroupFeature -> GroupPreference -> Maybe Int -> CIContent 'MDSnd
  CIRcvChatFeatureRejected :: ChatFeature -> CIContent 'MDRcv
  CIRcvGroupFeatureRejected :: GroupFeature -> CIContent 'MDRcv
  CISndModerated :: CIContent 'MDSnd
  CIRcvModerated :: CIContent 'MDRcv
  CIInvalidJSON :: Text -> CIContent d
-- ^ This type is used both in API and in DB, so we use different JSON encodings for the database and for the API
-- ! ^ Nested sum types also have to use different encodings for database and API
-- ! ^ to avoid breaking cross-platform compatibility, see RcvGroupEvent and SndGroupEvent

deriving instance Show (CIContent d)

ciMsgContent :: CIContent d -> Maybe MsgContent
ciMsgContent = \case
  CISndMsgContent mc -> Just mc
  CIRcvMsgContent mc -> Just mc
  _ -> Nothing

data MsgDecryptError = MDERatchetHeader | MDETooManySkipped | MDERatchetEarlier | MDEOther
  deriving (Eq, Show, Generic)

instance ToJSON MsgDecryptError where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "MDE"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "MDE"

instance FromJSON MsgDecryptError where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "MDE"

ciRequiresAttention :: forall d. MsgDirectionI d => CIContent d -> Bool
ciRequiresAttention content = case msgDirection @d of
  SMDSnd -> True
  SMDRcv -> case content of
    CIRcvMsgContent _ -> True
    CIRcvDeleted _ -> True
    CIRcvCall {} -> True
    CIRcvIntegrityError _ -> True
    CIRcvDecryptionError {} -> True
    CIRcvGroupInvitation {} -> True
    CIRcvGroupEvent rge -> case rge of
      RGEMemberAdded {} -> False
      RGEMemberConnected -> False
      RGEMemberLeft -> False
      RGEMemberRole {} -> False
      RGEUserRole _ -> True
      RGEMemberDeleted {} -> False
      RGEUserDeleted -> True
      RGEGroupDeleted -> True
      RGEGroupUpdated _ -> False
      RGEInvitedViaGroupLink -> False
    CIRcvConnEvent _ -> True
    CIRcvChatFeature {} -> False
    CIRcvChatPreference {} -> False
    CIRcvGroupFeature {} -> False
    CIRcvChatFeatureRejected _ -> True
    CIRcvGroupFeatureRejected _ -> True
    CIRcvModerated -> True
    CIInvalidJSON _ -> False

data RcvGroupEvent
  = RGEMemberAdded {groupMemberId :: GroupMemberId, profile :: Profile} -- CRJoinedGroupMemberConnecting
  | RGEMemberConnected -- CRUserJoinedGroup, CRJoinedGroupMember, CRConnectedToGroupMember
  | RGEMemberLeft -- CRLeftMember
  | RGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | RGEUserRole {role :: GroupMemberRole}
  | RGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile} -- CRDeletedMember
  | RGEUserDeleted -- CRDeletedMemberUser
  | RGEGroupDeleted -- CRGroupDeleted
  | RGEGroupUpdated {groupProfile :: GroupProfile} -- CRGroupUpdated
  -- RGEInvitedViaGroupLink chat items are not received - they're created when sending group invitations,
  -- but being RcvGroupEvent allows them to be assigned to the respective member (and so enable "send direct message")
  -- and be created as unread without adding / working around new status for sent items
  | RGEInvitedViaGroupLink -- CRSentGroupInvitationViaLink
  deriving (Show, Generic)

instance FromJSON RcvGroupEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "RGE"

instance ToJSON RcvGroupEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "RGE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "RGE"

newtype DBRcvGroupEvent = RGE RcvGroupEvent

instance FromJSON DBRcvGroupEvent where
  parseJSON v = RGE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "RGE") v

instance ToJSON DBRcvGroupEvent where
  toJSON (RGE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "RGE") v
  toEncoding (RGE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "RGE") v

data SndGroupEvent
  = SGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | SGEUserRole {role :: GroupMemberRole}
  | SGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile} -- CRUserDeletedMember
  | SGEUserLeft -- CRLeftMemberUser
  | SGEGroupUpdated {groupProfile :: GroupProfile} -- CRGroupUpdated
  deriving (Show, Generic)

instance FromJSON SndGroupEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "SGE"

instance ToJSON SndGroupEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "SGE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "SGE"

newtype DBSndGroupEvent = SGE SndGroupEvent

instance FromJSON DBSndGroupEvent where
  parseJSON v = SGE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "SGE") v

instance ToJSON DBSndGroupEvent where
  toJSON (SGE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "SGE") v
  toEncoding (SGE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "SGE") v

data RcvConnEvent
  = RCESwitchQueue {phase :: SwitchPhase}
  | RCERatchetSync {syncStatus :: RatchetSyncState}
  | RCEConnectionCodeChanged
  deriving (Show, Generic)

data SndConnEvent
  = SCESwitchQueue {phase :: SwitchPhase, member :: Maybe GroupMemberRef}
  | SCERatchetSync {syncStatus :: RatchetSyncState, member :: Maybe GroupMemberRef}
  deriving (Show, Generic)

instance FromJSON RcvConnEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "RCE"

instance ToJSON RcvConnEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "RCE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "RCE"

newtype DBRcvConnEvent = RCE RcvConnEvent

instance FromJSON DBRcvConnEvent where
  parseJSON v = RCE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "RCE") v

instance ToJSON DBRcvConnEvent where
  toJSON (RCE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "RCE") v
  toEncoding (RCE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "RCE") v

instance FromJSON SndConnEvent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "SCE"

instance ToJSON SndConnEvent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "SCE"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "SCE"

newtype DBSndConnEvent = SCE SndConnEvent

instance FromJSON DBSndConnEvent where
  parseJSON v = SCE <$> J.genericParseJSON (singleFieldJSON $ dropPrefix "SCE") v

instance ToJSON DBSndConnEvent where
  toJSON (SCE v) = J.genericToJSON (singleFieldJSON $ dropPrefix "SCE") v
  toEncoding (SCE v) = J.genericToEncoding (singleFieldJSON $ dropPrefix "SCE") v

newtype DBMsgErrorType = DBME MsgErrorType

instance FromJSON DBMsgErrorType where
  parseJSON v = DBME <$> J.genericParseJSON (singleFieldJSON fstToLower) v

instance ToJSON DBMsgErrorType where
  toJSON (DBME v) = J.genericToJSON (singleFieldJSON fstToLower) v
  toEncoding (DBME v) = J.genericToEncoding (singleFieldJSON fstToLower) v

data CIGroupInvitation = CIGroupInvitation
  { groupId :: GroupId,
    groupMemberId :: GroupMemberId,
    localDisplayName :: GroupName,
    groupProfile :: GroupProfile,
    status :: CIGroupInvitationStatus
  }
  deriving (Eq, Show, Generic, FromJSON)

instance ToJSON CIGroupInvitation where
  toJSON = J.genericToJSON J.defaultOptions {J.omitNothingFields = True}
  toEncoding = J.genericToEncoding J.defaultOptions {J.omitNothingFields = True}

data CIGroupInvitationStatus
  = CIGISPending
  | CIGISAccepted
  | CIGISRejected
  | CIGISExpired
  deriving (Eq, Show, Generic)

instance FromJSON CIGroupInvitationStatus where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CIGIS"

instance ToJSON CIGroupInvitationStatus where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CIGIS"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CIGIS"

ciContentToText :: CIContent d -> Text
ciContentToText = \case
  CISndMsgContent mc -> msgContentText mc
  CIRcvMsgContent mc -> msgContentText mc
  CISndDeleted cidm -> ciDeleteModeToText cidm
  CIRcvDeleted cidm -> ciDeleteModeToText cidm
  CISndCall status duration -> "outgoing call: " <> ciCallInfoText status duration
  CIRcvCall status duration -> "incoming call: " <> ciCallInfoText status duration
  CIRcvIntegrityError err -> msgIntegrityError err
  CIRcvDecryptionError err n syncRequired -> msgDecryptErrorText err n syncRequired
  CIRcvGroupInvitation groupInvitation memberRole -> "received " <> ciGroupInvitationToText groupInvitation memberRole
  CISndGroupInvitation groupInvitation memberRole -> "sent " <> ciGroupInvitationToText groupInvitation memberRole
  CIRcvGroupEvent event -> rcvGroupEventToText event
  CISndGroupEvent event -> sndGroupEventToText event
  CIRcvConnEvent event -> rcvConnEventToText event
  CISndConnEvent event -> sndConnEventToText event
  CIRcvChatFeature feature enabled param -> featureStateText feature enabled param
  CISndChatFeature feature enabled param -> featureStateText feature enabled param
  CIRcvChatPreference feature allowed param -> prefStateText feature allowed param
  CISndChatPreference feature allowed param -> "you " <> prefStateText feature allowed param
  CIRcvGroupFeature feature pref param -> groupPrefStateText feature pref param
  CISndGroupFeature feature pref param -> groupPrefStateText feature pref param
  CIRcvChatFeatureRejected feature -> chatFeatureNameText feature <> ": received, prohibited"
  CIRcvGroupFeatureRejected feature -> groupFeatureNameText feature <> ": received, prohibited"
  CISndModerated -> ciModeratedText
  CIRcvModerated -> ciModeratedText
  CIInvalidJSON _ -> "invalid content JSON"

ciGroupInvitationToText :: CIGroupInvitation -> GroupMemberRole -> Text
ciGroupInvitationToText CIGroupInvitation {groupProfile = GroupProfile {displayName, fullName}} role =
  "invitation to join group " <> displayName <> optionalFullName displayName fullName <> " as " <> (decodeLatin1 . strEncode $ role)

rcvGroupEventToText :: RcvGroupEvent -> Text
rcvGroupEventToText = \case
  RGEMemberAdded _ p -> "added " <> profileToText p
  RGEMemberConnected -> "connected"
  RGEMemberLeft -> "left"
  RGEMemberRole _ p r -> "changed role of " <> profileToText p <> " to " <> safeDecodeUtf8 (strEncode r)
  RGEUserRole r -> "changed your role to " <> safeDecodeUtf8 (strEncode r)
  RGEMemberDeleted _ p -> "removed " <> profileToText p
  RGEUserDeleted -> "removed you"
  RGEGroupDeleted -> "deleted group"
  RGEGroupUpdated _ -> "group profile updated"
  RGEInvitedViaGroupLink -> "invited via your group link"

sndGroupEventToText :: SndGroupEvent -> Text
sndGroupEventToText = \case
  SGEMemberRole _ p r -> "changed role of " <> profileToText p <> " to " <> safeDecodeUtf8 (strEncode r)
  SGEUserRole r -> "changed role for yourself to " <> safeDecodeUtf8 (strEncode r)
  SGEMemberDeleted _ p -> "removed " <> profileToText p
  SGEUserLeft -> "left"
  SGEGroupUpdated _ -> "group profile updated"

rcvConnEventToText :: RcvConnEvent -> Text
rcvConnEventToText = \case
  RCESwitchQueue phase -> case phase of
    SPStarted -> "started changing address for you..."
    SPConfirmed -> "confirmed changing address for you..."
    SPSecured -> "secured new address for you..."
    SPCompleted -> "changed address for you"
  RCERatchetSync syncStatus -> ratchetSyncStatusToText syncStatus
  RCEConnectionCodeChanged -> "security code changed"

ratchetSyncStatusToText :: RatchetSyncState -> Text
ratchetSyncStatusToText = \case
  RSOk -> "connection synchronized"
  RSAllowed -> "decryption error (connection may be out of sync), synchronization allowed"
  RSRequired -> "decryption error (connection out of sync), synchronization required"
  RSStarted -> "connection synchronization started"
  RSAgreed -> "connection synchronization agreed"

sndConnEventToText :: SndConnEvent -> Text
sndConnEventToText = \case
  SCESwitchQueue phase m -> case phase of
    SPStarted -> "started changing address" <> forMember m <> "..."
    SPConfirmed -> "confirmed changing address" <> forMember m <> "..."
    SPSecured -> "secured new address" <> forMember m <> "..."
    SPCompleted -> "you changed address" <> forMember m
  SCERatchetSync syncStatus m -> ratchetSyncStatusToText syncStatus <> forMember m
  where
    forMember member_ =
      maybe "" (\GroupMemberRef {profile = Profile {displayName}} -> " for " <> displayName) member_

profileToText :: Profile -> Text
profileToText Profile {displayName, fullName} = displayName <> optionalFullName displayName fullName

msgIntegrityError :: MsgErrorType -> Text
msgIntegrityError = \case
  MsgSkipped fromId toId ->
    "skipped message ID " <> tshow fromId
      <> if fromId == toId then "" else ".." <> tshow toId
  MsgBadId msgId -> "unexpected message ID " <> tshow msgId
  MsgBadHash -> "incorrect message hash"
  MsgDuplicate -> "duplicate message ID"

msgDecryptErrorText :: MsgDecryptError -> Word32 -> Maybe Bool -> Text
msgDecryptErrorText err n syncRequired =
  "decryption error, possibly due to the device change"
    <> maybe "" (\ed -> " (" <> ed <> ")") errDesc
    <> (", " <> syncRequiredText)
  where
    errDesc = case err of
      MDERatchetHeader -> Just $ "header" <> counter
      MDETooManySkipped -> Just $ "too many skipped messages" <> counter
      MDERatchetEarlier -> Just $ "earlier message" <> counter
      MDEOther -> counter_
    counter_ = if n == 1 then Nothing else Just $ tshow n <> " messages"
    counter = maybe "" (", " <>) counter_
    syncRequiredText = case syncRequired of
      Just True -> "synchronization required"
      _ -> "synchronization allowed"

msgDirToModeratedContent_ :: SMsgDirection d -> CIContent d
msgDirToModeratedContent_ = \case
  SMDRcv -> CIRcvModerated
  SMDSnd -> CISndModerated

ciModeratedText :: Text
ciModeratedText = "moderated"

-- platform independent
instance MsgDirectionI d => ToField (CIContent d) where
  toField = toField . encodeJSON . dbJsonCIContent

-- platform specific
instance MsgDirectionI d => ToJSON (CIContent d) where
  toJSON = J.toJSON . jsonCIContent
  toEncoding = J.toEncoding . jsonCIContent

data ACIContent = forall d. MsgDirectionI d => ACIContent (SMsgDirection d) (CIContent d)

deriving instance Show ACIContent

-- platform independent
dbParseACIContent :: Text -> Either String ACIContent
dbParseACIContent = fmap aciContentDBJSON . J.eitherDecodeStrict' . encodeUtf8

-- platform specific
instance FromJSON ACIContent where
  parseJSON = fmap aciContentJSON . J.parseJSON

-- platform specific
data JSONCIContent
  = JCISndMsgContent {msgContent :: MsgContent}
  | JCIRcvMsgContent {msgContent :: MsgContent}
  | JCISndDeleted {deleteMode :: CIDeleteMode}
  | JCIRcvDeleted {deleteMode :: CIDeleteMode}
  | JCISndCall {status :: CICallStatus, duration :: Int} -- duration in seconds
  | JCIRcvCall {status :: CICallStatus, duration :: Int}
  | JCIRcvIntegrityError {msgError :: MsgErrorType}
  | JCIRcvDecryptionError {msgDecryptError :: MsgDecryptError, msgCount :: Word32, syncRequired :: Maybe Bool}
  | JCIRcvGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | JCISndGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | JCIRcvGroupEvent {rcvGroupEvent :: RcvGroupEvent}
  | JCISndGroupEvent {sndGroupEvent :: SndGroupEvent}
  | JCIRcvConnEvent {rcvConnEvent :: RcvConnEvent}
  | JCISndConnEvent {sndConnEvent :: SndConnEvent}
  | JCIRcvChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | JCISndChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | JCIRcvChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | JCISndChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | JCIRcvGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | JCISndGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | JCIRcvChatFeatureRejected {feature :: ChatFeature}
  | JCIRcvGroupFeatureRejected {groupFeature :: GroupFeature}
  | JCISndModerated
  | JCIRcvModerated
  | JCIInvalidJSON {direction :: MsgDirection, json :: Text}
  deriving (Generic)

instance FromJSON JSONCIContent where
  parseJSON = J.genericParseJSON . sumTypeJSON $ dropPrefix "JCI"

instance ToJSON JSONCIContent where
  toJSON = J.genericToJSON . sumTypeJSON $ dropPrefix "JCI"
  toEncoding = J.genericToEncoding . sumTypeJSON $ dropPrefix "JCI"

jsonCIContent :: forall d. MsgDirectionI d => CIContent d -> JSONCIContent
jsonCIContent = \case
  CISndMsgContent mc -> JCISndMsgContent mc
  CIRcvMsgContent mc -> JCIRcvMsgContent mc
  CISndDeleted cidm -> JCISndDeleted cidm
  CIRcvDeleted cidm -> JCIRcvDeleted cidm
  CISndCall status duration -> JCISndCall {status, duration}
  CIRcvCall status duration -> JCIRcvCall {status, duration}
  CIRcvIntegrityError err -> JCIRcvIntegrityError err
  CIRcvDecryptionError err n syncRequired -> JCIRcvDecryptionError err n syncRequired
  CIRcvGroupInvitation groupInvitation memberRole -> JCIRcvGroupInvitation {groupInvitation, memberRole}
  CISndGroupInvitation groupInvitation memberRole -> JCISndGroupInvitation {groupInvitation, memberRole}
  CIRcvGroupEvent rcvGroupEvent -> JCIRcvGroupEvent {rcvGroupEvent}
  CISndGroupEvent sndGroupEvent -> JCISndGroupEvent {sndGroupEvent}
  CIRcvConnEvent rcvConnEvent -> JCIRcvConnEvent {rcvConnEvent}
  CISndConnEvent sndConnEvent -> JCISndConnEvent {sndConnEvent}
  CIRcvChatFeature feature enabled param -> JCIRcvChatFeature {feature, enabled, param}
  CISndChatFeature feature enabled param -> JCISndChatFeature {feature, enabled, param}
  CIRcvChatPreference feature allowed param -> JCIRcvChatPreference {feature, allowed, param}
  CISndChatPreference feature allowed param -> JCISndChatPreference {feature, allowed, param}
  CIRcvGroupFeature groupFeature preference param -> JCIRcvGroupFeature {groupFeature, preference, param}
  CISndGroupFeature groupFeature preference param -> JCISndGroupFeature {groupFeature, preference, param}
  CIRcvChatFeatureRejected feature -> JCIRcvChatFeatureRejected {feature}
  CIRcvGroupFeatureRejected groupFeature -> JCIRcvGroupFeatureRejected {groupFeature}
  CISndModerated -> JCISndModerated
  CIRcvModerated -> JCISndModerated
  CIInvalidJSON json -> JCIInvalidJSON (toMsgDirection $ msgDirection @d) json

aciContentJSON :: JSONCIContent -> ACIContent
aciContentJSON = \case
  JCISndMsgContent mc -> ACIContent SMDSnd $ CISndMsgContent mc
  JCIRcvMsgContent mc -> ACIContent SMDRcv $ CIRcvMsgContent mc
  JCISndDeleted cidm -> ACIContent SMDSnd $ CISndDeleted cidm
  JCIRcvDeleted cidm -> ACIContent SMDRcv $ CIRcvDeleted cidm
  JCISndCall {status, duration} -> ACIContent SMDSnd $ CISndCall status duration
  JCIRcvCall {status, duration} -> ACIContent SMDRcv $ CIRcvCall status duration
  JCIRcvIntegrityError err -> ACIContent SMDRcv $ CIRcvIntegrityError err
  JCIRcvDecryptionError err n syncRequired -> ACIContent SMDRcv $ CIRcvDecryptionError err n syncRequired
  JCIRcvGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDRcv $ CIRcvGroupInvitation groupInvitation memberRole
  JCISndGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDSnd $ CISndGroupInvitation groupInvitation memberRole
  JCIRcvGroupEvent {rcvGroupEvent} -> ACIContent SMDRcv $ CIRcvGroupEvent rcvGroupEvent
  JCISndGroupEvent {sndGroupEvent} -> ACIContent SMDSnd $ CISndGroupEvent sndGroupEvent
  JCIRcvConnEvent {rcvConnEvent} -> ACIContent SMDRcv $ CIRcvConnEvent rcvConnEvent
  JCISndConnEvent {sndConnEvent} -> ACIContent SMDSnd $ CISndConnEvent sndConnEvent
  JCIRcvChatFeature {feature, enabled, param} -> ACIContent SMDRcv $ CIRcvChatFeature feature enabled param
  JCISndChatFeature {feature, enabled, param} -> ACIContent SMDSnd $ CISndChatFeature feature enabled param
  JCIRcvChatPreference {feature, allowed, param} -> ACIContent SMDRcv $ CIRcvChatPreference feature allowed param
  JCISndChatPreference {feature, allowed, param} -> ACIContent SMDSnd $ CISndChatPreference feature allowed param
  JCIRcvGroupFeature {groupFeature, preference, param} -> ACIContent SMDRcv $ CIRcvGroupFeature groupFeature preference param
  JCISndGroupFeature {groupFeature, preference, param} -> ACIContent SMDSnd $ CISndGroupFeature groupFeature preference param
  JCIRcvChatFeatureRejected {feature} -> ACIContent SMDRcv $ CIRcvChatFeatureRejected feature
  JCIRcvGroupFeatureRejected {groupFeature} -> ACIContent SMDRcv $ CIRcvGroupFeatureRejected groupFeature
  JCISndModerated -> ACIContent SMDSnd CISndModerated
  JCIRcvModerated -> ACIContent SMDRcv CIRcvModerated
  JCIInvalidJSON dir json -> case fromMsgDirection dir of
    AMsgDirection d -> ACIContent d $ CIInvalidJSON json

-- platform independent
data DBJSONCIContent
  = DBJCISndMsgContent {msgContent :: MsgContent}
  | DBJCIRcvMsgContent {msgContent :: MsgContent}
  | DBJCISndDeleted {deleteMode :: CIDeleteMode}
  | DBJCIRcvDeleted {deleteMode :: CIDeleteMode}
  | DBJCISndCall {status :: CICallStatus, duration :: Int}
  | DBJCIRcvCall {status :: CICallStatus, duration :: Int}
  | DBJCIRcvIntegrityError {msgError :: DBMsgErrorType}
  | DBJCIRcvDecryptionError {msgDecryptError :: MsgDecryptError, msgCount :: Word32, syncRequired :: Maybe Bool}
  | DBJCIRcvGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | DBJCISndGroupInvitation {groupInvitation :: CIGroupInvitation, memberRole :: GroupMemberRole}
  | DBJCIRcvGroupEvent {rcvGroupEvent :: DBRcvGroupEvent}
  | DBJCISndGroupEvent {sndGroupEvent :: DBSndGroupEvent}
  | DBJCIRcvConnEvent {rcvConnEvent :: DBRcvConnEvent}
  | DBJCISndConnEvent {sndConnEvent :: DBSndConnEvent}
  | DBJCIRcvChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | DBJCISndChatFeature {feature :: ChatFeature, enabled :: PrefEnabled, param :: Maybe Int}
  | DBJCIRcvChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | DBJCISndChatPreference {feature :: ChatFeature, allowed :: FeatureAllowed, param :: Maybe Int}
  | DBJCIRcvGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | DBJCISndGroupFeature {groupFeature :: GroupFeature, preference :: GroupPreference, param :: Maybe Int}
  | DBJCIRcvChatFeatureRejected {feature :: ChatFeature}
  | DBJCIRcvGroupFeatureRejected {groupFeature :: GroupFeature}
  | DBJCISndModerated
  | DBJCIRcvModerated
  | DBJCIInvalidJSON {direction :: MsgDirection, json :: Text}
  deriving (Generic)

instance FromJSON DBJSONCIContent where
  parseJSON = J.genericParseJSON . singleFieldJSON $ dropPrefix "DBJCI"

instance ToJSON DBJSONCIContent where
  toJSON = J.genericToJSON . singleFieldJSON $ dropPrefix "DBJCI"
  toEncoding = J.genericToEncoding . singleFieldJSON $ dropPrefix "DBJCI"

dbJsonCIContent :: forall d. MsgDirectionI d => CIContent d -> DBJSONCIContent
dbJsonCIContent = \case
  CISndMsgContent mc -> DBJCISndMsgContent mc
  CIRcvMsgContent mc -> DBJCIRcvMsgContent mc
  CISndDeleted cidm -> DBJCISndDeleted cidm
  CIRcvDeleted cidm -> DBJCIRcvDeleted cidm
  CISndCall status duration -> DBJCISndCall {status, duration}
  CIRcvCall status duration -> DBJCIRcvCall {status, duration}
  CIRcvIntegrityError err -> DBJCIRcvIntegrityError $ DBME err
  CIRcvDecryptionError err n syncRequired -> DBJCIRcvDecryptionError err n syncRequired
  CIRcvGroupInvitation groupInvitation memberRole -> DBJCIRcvGroupInvitation {groupInvitation, memberRole}
  CISndGroupInvitation groupInvitation memberRole -> DBJCISndGroupInvitation {groupInvitation, memberRole}
  CIRcvGroupEvent rge -> DBJCIRcvGroupEvent $ RGE rge
  CISndGroupEvent sge -> DBJCISndGroupEvent $ SGE sge
  CIRcvConnEvent rce -> DBJCIRcvConnEvent $ RCE rce
  CISndConnEvent sce -> DBJCISndConnEvent $ SCE sce
  CIRcvChatFeature feature enabled param -> DBJCIRcvChatFeature {feature, enabled, param}
  CISndChatFeature feature enabled param -> DBJCISndChatFeature {feature, enabled, param}
  CIRcvChatPreference feature allowed param -> DBJCIRcvChatPreference {feature, allowed, param}
  CISndChatPreference feature allowed param -> DBJCISndChatPreference {feature, allowed, param}
  CIRcvGroupFeature groupFeature preference param -> DBJCIRcvGroupFeature {groupFeature, preference, param}
  CISndGroupFeature groupFeature preference param -> DBJCISndGroupFeature {groupFeature, preference, param}
  CIRcvChatFeatureRejected feature -> DBJCIRcvChatFeatureRejected {feature}
  CIRcvGroupFeatureRejected groupFeature -> DBJCIRcvGroupFeatureRejected {groupFeature}
  CISndModerated -> DBJCISndModerated
  CIRcvModerated -> DBJCIRcvModerated
  CIInvalidJSON json -> DBJCIInvalidJSON (toMsgDirection $ msgDirection @d) json

aciContentDBJSON :: DBJSONCIContent -> ACIContent
aciContentDBJSON = \case
  DBJCISndMsgContent mc -> ACIContent SMDSnd $ CISndMsgContent mc
  DBJCIRcvMsgContent mc -> ACIContent SMDRcv $ CIRcvMsgContent mc
  DBJCISndDeleted cidm -> ACIContent SMDSnd $ CISndDeleted cidm
  DBJCIRcvDeleted cidm -> ACIContent SMDRcv $ CIRcvDeleted cidm
  DBJCISndCall {status, duration} -> ACIContent SMDSnd $ CISndCall status duration
  DBJCIRcvCall {status, duration} -> ACIContent SMDRcv $ CIRcvCall status duration
  DBJCIRcvIntegrityError (DBME err) -> ACIContent SMDRcv $ CIRcvIntegrityError err
  DBJCIRcvDecryptionError err n syncRequired -> ACIContent SMDRcv $ CIRcvDecryptionError err n syncRequired
  DBJCIRcvGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDRcv $ CIRcvGroupInvitation groupInvitation memberRole
  DBJCISndGroupInvitation {groupInvitation, memberRole} -> ACIContent SMDSnd $ CISndGroupInvitation groupInvitation memberRole
  DBJCIRcvGroupEvent (RGE rge) -> ACIContent SMDRcv $ CIRcvGroupEvent rge
  DBJCISndGroupEvent (SGE sge) -> ACIContent SMDSnd $ CISndGroupEvent sge
  DBJCIRcvConnEvent (RCE rce) -> ACIContent SMDRcv $ CIRcvConnEvent rce
  DBJCISndConnEvent (SCE sce) -> ACIContent SMDSnd $ CISndConnEvent sce
  DBJCIRcvChatFeature {feature, enabled, param} -> ACIContent SMDRcv $ CIRcvChatFeature feature enabled param
  DBJCISndChatFeature {feature, enabled, param} -> ACIContent SMDSnd $ CISndChatFeature feature enabled param
  DBJCIRcvChatPreference {feature, allowed, param} -> ACIContent SMDRcv $ CIRcvChatPreference feature allowed param
  DBJCISndChatPreference {feature, allowed, param} -> ACIContent SMDSnd $ CISndChatPreference feature allowed param
  DBJCIRcvGroupFeature {groupFeature, preference, param} -> ACIContent SMDRcv $ CIRcvGroupFeature groupFeature preference param
  DBJCISndGroupFeature {groupFeature, preference, param} -> ACIContent SMDSnd $ CISndGroupFeature groupFeature preference param
  DBJCIRcvChatFeatureRejected {feature} -> ACIContent SMDRcv $ CIRcvChatFeatureRejected feature
  DBJCIRcvGroupFeatureRejected {groupFeature} -> ACIContent SMDRcv $ CIRcvGroupFeatureRejected groupFeature
  DBJCISndModerated -> ACIContent SMDSnd CISndModerated
  DBJCIRcvModerated -> ACIContent SMDRcv CIRcvModerated
  DBJCIInvalidJSON dir json -> case fromMsgDirection dir of
    AMsgDirection d -> ACIContent d $ CIInvalidJSON json

data CICallStatus
  = CISCallPending
  | CISCallMissed
  | CISCallRejected -- only possible for received calls, not on type level
  | CISCallAccepted
  | CISCallNegotiated
  | CISCallProgress
  | CISCallEnded
  | CISCallError
  deriving (Show, Generic)

instance FromJSON CICallStatus where
  parseJSON = J.genericParseJSON . enumJSON $ dropPrefix "CISCall"

instance ToJSON CICallStatus where
  toJSON = J.genericToJSON . enumJSON $ dropPrefix "CISCall"
  toEncoding = J.genericToEncoding . enumJSON $ dropPrefix "CISCall"

ciCallInfoText :: CICallStatus -> Int -> Text
ciCallInfoText status duration = case status of
  CISCallPending -> "calling..."
  CISCallMissed -> "missed"
  CISCallRejected -> "rejected"
  CISCallAccepted -> "accepted"
  CISCallNegotiated -> "connecting..."
  CISCallProgress -> "in progress " <> durationText duration
  CISCallEnded -> "ended " <> durationText duration
  CISCallError -> "error"
