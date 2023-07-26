{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Monad.Reader
import qualified Data.ByteString.Char8 as B
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Directory.Events
import Directory.Options
import Directory.Store
import Simplex.Chat.Bot
import Simplex.Chat.Bot.KnownContacts
import Simplex.Chat.Controller
import Simplex.Chat.Core
import Simplex.Chat.Messages
-- import Simplex.Chat.Messages.CIContent
import Simplex.Chat.Options
import Simplex.Chat.Protocol (MsgContent (..))
import Simplex.Chat.Terminal (terminalChatConfig)
import Simplex.Chat.Types
import Simplex.Messaging.Encoding.String
import Simplex.Messaging.Util (safeDecodeUtf8, tshow)
import System.Directory (getAppUserDataDirectory)

main :: IO ()
main = do
  opts@DirectoryOpts {directoryLog} <- welcomeGetOpts
  st <- getDirectoryStore directoryLog
  simplexChatCore terminalChatConfig (mkChatOpts opts) Nothing $ directoryService st opts

welcomeGetOpts :: IO DirectoryOpts
welcomeGetOpts = do
  appDir <- getAppUserDataDirectory "simplex"
  opts@DirectoryOpts {coreOptions = CoreChatOpts {dbFilePrefix}} <- getDirectoryOpts appDir "simplex_directory_service"
  putStrLn $ "SimpleX Directory Service Bot v" ++ versionNumber
  putStrLn $ "db: " <> dbFilePrefix <> "_chat.db, " <> dbFilePrefix <> "_agent.db"
  pure opts

directoryService :: DirectoryStore -> DirectoryOpts -> User -> ChatController -> IO ()
directoryService st DirectoryOpts {superUsers, serviceName} User {userId} cc = do
  initializeBotAddress cc
  race_ (forever $ void getLine) . forever $ do
    (_, resp) <- atomically . readTBQueue $ outputQ cc
    forM_ (crDirectoryEvent resp) $ \case
      DEContactConnected ct -> do
        contactConnected ct
        sendMessage cc ct $
          "Welcome to " <> serviceName <> " service!\n\
          \Send a search string to find groups or */help* to learn how to add groups to directory.\n\n\
          \For example, send _politics_ to find groups about politics."
      DEGroupInvitation {contact = ct, groupInfo = g, fromMemberRole, memberRole} -> case badInvitation fromMemberRole memberRole of
        -- TODO check duplicate group name and ask to confirm
        Just msg -> sendMessage cc ct msg
        Nothing -> do
          let GroupInfo {groupId, groupProfile = GroupProfile {displayName}} = g
          atomically $ addGroupReg st ct g
          r <- sendChatCmd cc $ APIJoinGroup groupId
          sendMessage cc ct $ T.unpack $ case r of
            CRUserAcceptedGroupSent {} -> "Joining the group #" <> displayName <> "…"
            _ -> "Error joining group " <> displayName <> ", please re-send the invitation!"
      DEServiceJoinedGroup ctId g -> withGroupReg g "joined group" $ \GroupReg {groupRegStatus} -> do
        let GroupInfo {groupId, groupProfile = GroupProfile {displayName}} = g
        sendMessage' cc ctId $ T.unpack $ "Joined the group #" <> displayName <> ", creating the link…"
        sendChatCmd cc (APICreateGroupLink groupId GRMember) >>= \case
          CRGroupLinkCreated {connReqContact} -> do
            atomically $ writeTVar groupRegStatus GRSPendingUpdate
            sendMessage' cc ctId
              "Created the public link to join the group via this directory service that is always online.\n\n\
              \Please add it to the group welcome message.\n\
              \For example, add:"
            sendMessage' cc ctId $ "Link to join the group " <> T.unpack displayName <> ": " <> B.unpack (strEncode connReqContact)
          CRChatCmdError _ (ChatError e) -> case e of
            CEGroupUserRole {} -> sendMessage' cc ctId "Failed creating group link, as service is no longer an admin."
            CEGroupMemberUserRemoved -> sendMessage' cc ctId "Failed creating group link, as service is removed from the group."
            CEGroupNotJoined _ -> sendMessage' cc ctId $ unexpectedError "group not joined"
            CEGroupMemberNotActive -> sendMessage' cc ctId $ unexpectedError "service membership is not active"
            _ -> sendMessage' cc ctId $ unexpectedError "can't create group link"
          _ -> sendMessage' cc ctId $ unexpectedError "can't create group link"
      DEGroupUpdated {contactId, fromGroup, toGroup} -> do
        unless (sameProfile p p') $ do
          atomically $ unlistGroup st groupId
          withGroupReg toGroup "group updated" $ \gr@GroupReg {dbContactId, groupRegStatus} -> do
            readTVarIO groupRegStatus >>= \case
              GRSPendingConfirmation -> pure ()
              GRSProposed -> pure ()
              GRSPendingUpdate ->
                when (contactId == dbContactId) $ -- we do not need to process updates made by other members in this case
                  sendChatCmd cc (APIGetGroupLink groupId) >>= \case
                    CRGroupLink {connReqContact} -> do
                      let groupLink = safeDecodeUtf8 $ strEncode connReqContact
                          hadLinkBefore = groupLink `isInfix` description p
                          hasLinkNow = groupLink `isInfix` description p'
                      case (hadLinkBefore, hasLinkNow) of
                        (True, True) -> do
                          sendMessage' cc contactId "The group profile is updated: the group registration is suspended and it will not appear in search results until re-approved"
                          -- TODO suspend group listing, send for approval
                        (True, False) -> do
                          sendMessage' cc contactId "The group link is removed, the group registration is suspended and it will not appear in search results"
                          -- TODO suspend group listing, remove approval code
                          atomically $ writeTVar groupRegStatus GRSPendingUpdate
                        (False, True) -> do
                          sendMessage' cc contactId $ "Thank you! The group link for group ID " <> show groupId <> " (" <> T.unpack displayName <> ") added to the welcome message.\nYou will be notified once the group is added to the directory - it may take up to 24 hours."
                          let gaId = 1
                          atomically $ writeTVar groupRegStatus $ GRSPendingApproval gaId
                          sendForApproval gr gaId
                        (False, False) -> pure ()
                          -- check status, remove approval code, remove listing
                    _ -> pure () -- TODO handle errors
              GRSPendingApproval n -> do
                let gaId = n + 1
                atomically $ writeTVar groupRegStatus $ GRSPendingApproval gaId
                notifySuperUsers $ T.unpack $ "The group registration updated for ID " <> tshow groupId <> ": " <> localDisplayName
                sendForApproval gr gaId
              GRSActive -> do
                let gaId = 1
                atomically $ writeTVar groupRegStatus $ GRSPendingApproval gaId
                notifySuperUsers $ T.unpack $ "The group profile updated, group suspended for ID " <> tshow groupId <> ": " <> localDisplayName
                sendForApproval gr gaId
                sendMessage' cc dbContactId $ T.unpack $ "The group profile is updated, the group registration is suspended until re-approved for ID " <> tshow (userGroupRegId gr) <> ": " <> displayName
              GRSSuspended -> pure ()
        where
          isInfix l d_ = l `T.isInfixOf` fromMaybe "" d_
          GroupInfo {groupId, groupProfile = p} = fromGroup
          GroupInfo {localDisplayName, groupProfile = p'@GroupProfile {displayName, image = image'}} = toGroup
          sameProfile
            GroupProfile {displayName = n, fullName = fn, image = i, description = d}
            GroupProfile {displayName = n', fullName = fn', image = i', description = d'} =
              n == n' && fn == fn' && i == i' && d == d'
          sendForApproval GroupReg {dbGroupId, dbContactId} gaId = do
            ct_ <-  getContact cc dbContactId
            let text = maybe ("The group ID " <> tshow dbGroupId <> " submitted: ") (\c -> localDisplayName' c <> " submitted the group ID " <> tshow dbGroupId <> ": ") ct_
                        <> groupInfoText p' <> "\n\nTo approve send:"
                msg = maybe (MCText text) (\image -> MCImage {text, image}) image'
            withSuperUsers $ \ctId -> do
              sendComposedMessage' cc ctId Nothing msg
              sendMessage' cc ctId $ "/approve " <> show dbGroupId <> ":" <> T.unpack localDisplayName <> " " <> show gaId
      DEContactRoleChanged _ctId _g _role -> pure ()
      DEServiceRoleChanged _g _role -> pure ()
      DEContactRemovedFromGroup _ctId _g -> pure ()
      DEContactLeftGroup _ctId _g -> pure ()
      DEServiceRemovedFromGroup _g -> pure ()
      DEGroupDeleted _g -> pure ()
      DEUnsupportedMessage _ct _ciId -> pure ()
      DEItemEditIgnored _ct -> pure ()
      DEItemDeleteIgnored _ct -> pure ()
      DEContactCommand ct ciId aCmd -> case aCmd of
        ADC SDRUser cmd -> case cmd of
          DCHelp ->
            sendMessage cc ct $
              "You must be the owner to add the group to the directory:\n\
              \1. Invite " <> serviceName <> " bot to your group as *admin*.\n\
              \2. " <> serviceName <> " bot will create a public group link for the new members to join even when you are offline.\n\
              \3. You will then need to add this link to the group welcome message.\n\
              \4. Once the link is added, service admins will approve the group (it can take up to 24 hours), and everybody will be able to find it in directory.\n\n\
              \Start from inviting the bot to your group as admin - it will guide you through the process"
          DCSearchGroup s -> do
            sendChatCmd cc (APIListGroups userId Nothing $ Just $ T.unpack s) >>= \case
              CRGroupsList {groups} ->
                atomically (filterListedGroups st groups) >>= \case
                  [] -> sendReply "No groups found"
                  gs -> do
                    sendReply $ "Found " <> show (length gs) <> " group(s)"
                    void . forkIO $ forM_ gs $ \GroupInfo {groupProfile = p@GroupProfile {image = image_}} -> do
                      let text = groupInfoText p
                          msg = maybe (MCText text) (\image -> MCImage {text, image}) image_
                      sendComposedMessage cc ct Nothing msg
              _ -> sendReply "Unexpected error"
          DCConfirmDuplicateGroup _ugrId _gName -> pure ()
          DCListUserGroups -> pure ()
          DCDeleteGroup _ugrId _gName -> pure ()
          DCUnknownCommand -> sendReply "Unknown command"
          DCCommandError tag -> sendReply $ "Command error: " <> show tag
        ADC SDRSuperUser cmd -- TODO check group status
          | superUser `elem` superUsers -> case cmd of
            DCApproveGroup {groupId, localDisplayName = n, groupApprovalId} ->
              atomically (getGroupReg st groupId) >>= \case
                Nothing -> sendMessage cc ct $ "Group ID " <> show groupId <> " not found"
                Just GroupReg {dbContactId, groupRegStatus} -> do
                  readTVarIO groupRegStatus >>= \case
                    GRSPendingApproval gaId
                      | gaId == groupApprovalId -> do
                        getGroup cc groupId >>= \case
                          Just GroupInfo {localDisplayName = n'}
                            | n == n' -> do
                              atomically $ do
                                writeTVar groupRegStatus GRSActive
                                listGroup st groupId
                              sendReply "Group approved!"
                              sendMessage' cc dbContactId $ "The group ID " <> show groupId <> " (" <> T.unpack n <> ") is approved and listed in directory!\nPlease note: if you change the group profile it will be hidden from directory until it is re-approved."
                            | otherwise -> sendReply "Incorrect group name"
                          Nothing -> pure ()
                      | otherwise -> sendReply "Incorrect approval code"
                    _ -> sendMessage cc ct $ "Error: the group ID " <> show groupId <> " (" <> T.unpack n <> ") is not pending approval."
            DCRejectGroup _gaId _gName -> pure ()
            DCSuspendGroup _gId _gName -> pure ()
            DCResumeGroup _gId _gName -> pure ()
            DCListGroups -> pure ()
            DCCommandError tag -> sendReply $ "Command error: " <> show tag
          | otherwise -> sendReply "You are not allowed to use this command"
          where
            superUser = KnownContact {contactId = contactId' ct, localDisplayName = localDisplayName' ct}
        where
          sendReply = sendComposedMessage cc ct (Just ciId) . textMsgContent
  where
    contactConnected ct = putStrLn $ T.unpack (localDisplayName' ct) <> " connected"
    -- withContactGroupReg ctId g err action = withContact ctId g err $ withGroupReg g err . action
    withSuperUsers action = void . forkIO $ forM_ superUsers $ \KnownContact {contactId} -> action contactId
    notifySuperUsers s = withSuperUsers $ \contactId -> sendMessage' cc contactId s
    -- withContact ctId GroupInfo {localDisplayName} err action = do
    --   getContact cc ctId >>= \case
    --     Just ct -> action ct
    --     Nothing -> putStrLn $ T.unpack $ "Error: " <> err <> ", group: " <> localDisplayName <> ", can't find contact ID " <> tshow ctId
    withGroupReg GroupInfo {groupId, localDisplayName} err action = do
      atomically (getGroupReg st groupId) >>= \case
        Just gr -> action gr
        Nothing -> putStrLn $ T.unpack $ "Error: " <> err <> ", group: " <> localDisplayName <> ", can't find group registration ID " <> tshow groupId
    withGroupReg' groupId err action = do
      atomically (getGroupReg st groupId) >>= \case
        Just gr -> action gr
        Nothing -> putStrLn $ T.unpack $ "Error: " <> err <> ", can't find group registration ID " <> tshow groupId
    groupInfoText GroupProfile {displayName = n, fullName = fn, description = d} =
      n <> (if n == fn || T.null fn then "" else " (" <> fn <> ")") <> maybe "" ("\nWelcome message:\n" <>) d

badInvitation :: GroupMemberRole -> GroupMemberRole -> Maybe String
badInvitation contactRole serviceRole = case (contactRole, serviceRole) of
  (GROwner, GRAdmin) -> Nothing
  (_, GRAdmin) -> Just "You must have a group *owner* role to register the group"
  (GROwner, _) -> Just "You must grant directory service *admin* role to register the group"
  _ -> Just "You must have a group *owner* role and you must grant directory service *admin* role to register the group"

getContact :: ChatController -> ContactId -> IO (Maybe Contact)
getContact cc ctId = resp <$> sendChatCmd cc (APIGetChat (ChatRef CTDirect ctId) (CPLast 0) Nothing)
  where
    resp :: ChatResponse -> Maybe Contact
    resp = \case
      CRApiChat _ (AChat SCTDirect Chat {chatInfo = DirectChat ct}) -> Just ct
      _ -> Nothing

getGroup :: ChatController -> GroupId -> IO (Maybe GroupInfo)
getGroup cc gId = resp <$> sendChatCmd cc (APIGetChat (ChatRef CTGroup gId) (CPLast 0) Nothing)
  where
    resp :: ChatResponse -> Maybe GroupInfo
    resp = \case
      CRApiChat _ (AChat SCTGroup Chat {chatInfo = GroupChat g}) -> Just g
      _ -> Nothing

unexpectedError :: String -> String
unexpectedError err = "Unexpected error: " <> err <> ", please notify the developers."
