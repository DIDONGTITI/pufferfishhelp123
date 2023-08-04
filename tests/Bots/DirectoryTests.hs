{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PostfixOperators #-}

module Bots.DirectoryTests where

import ChatClient
import ChatTests.Utils
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (finally)
import Directory.Options
import Directory.Service
import Directory.Store
import Simplex.Chat.Bot.KnownContacts
import Simplex.Chat.Core
import Simplex.Chat.Options (ChatOpts (..), CoreChatOpts (..))
import Simplex.Chat.Types (Profile (..), GroupMemberRole (GROwner))
import System.FilePath ((</>))
import Test.Hspec

directoryServiceTests :: SpecWith FilePath
directoryServiceTests = do
  it "should register group" testDirectoryService
  it "should suspend and resume group" testSuspendResume
  describe "de-listing the group" $ do
    it "should de-list if owner leaves the group" testDelistedOwnerLeaves
    it "should de-list if owner is removed from the group" testDelistedOwnerRemoved
    it "should NOT de-list if another member leaves the group" testNotDelistedMemberLeaves
    it "should NOT de-list if another member is removed from the group" testNotDelistedMemberRemoved
    it "should de-list if service is removed from the group" testDelistedServiceRemoved
    it "should de-list/re-list when service/owner roles change" testDelistedRoleChanges
    it "should NOT de-list if another member role changes" testNotDelistedMemberRoleChanged
    it "should NOT send to approval if roles are incorrect" testNotSentApprovalBadRoles
    it "should NOT allow approving if roles are incorrect" testNotApprovedBadRoles
  describe "should require re-approval if profile is changed by" $ do
    it "the registration owner" testRegOwnerChangedProfile
    it "another owner" testAnotherOwnerChangedProfile
  describe "should require profile update if group link is removed by " $ do
    it "the registration owner" testRegOwnerRemovedLink
    it "another owner" testAnotherOwnerRemovedLink
  describe "duplicate groups (same display name and full name)" $ do
    it "should ask for confirmation if a duplicate group is submitted" testDuplicateAskConfirmation
    it "should prohibit registration if a duplicate group is listed" testDuplicateProhibitRegistration
    it "should prohibit confirmation if a duplicate group is listed" testDuplicateProhibitConfirmation
    it "should prohibit when profile is updated and not send for approval" testDuplicateProhibitWhenUpdated
    it "should prohibit approval if a duplicate group is listed" testDuplicateProhibitApproval

directoryProfile :: Profile
directoryProfile = Profile {displayName = "SimpleX-Directory", fullName = "", image = Nothing, contactLink = Nothing, preferences = Nothing}

mkDirectoryOpts :: FilePath -> [KnownContact] -> DirectoryOpts
mkDirectoryOpts tmp superUsers =
  DirectoryOpts
    { coreOptions = (coreOptions (testOpts :: ChatOpts)) {dbFilePrefix = tmp </> serviceDbPrefix},
      superUsers,
      directoryLog = tmp </> "directory_service.log",
      serviceName = "SimpleX-Directory"
    }

serviceDbPrefix :: FilePath
serviceDbPrefix = "directory_service"

testDirectoryService :: HasCallStack => FilePath -> IO ()
testDirectoryService tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob ->
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        bob #> "@SimpleX-Directory privacy"
        bob <# "SimpleX-Directory> > privacy"
        bob <## "      No groups found"
        -- putStrLn "*** create a group"
        bob ##> "/g PSA Privacy, Security & Anonymity"
        bob <## "group #PSA (Privacy, Security & Anonymity) is created"
        bob <## "to add members use /a PSA <name> or /create link #PSA"
        bob ##> "/a PSA SimpleX-Directory member"
        bob <## "invitation to join the group #PSA sent to SimpleX-Directory"
        bob <# "SimpleX-Directory> You must grant directory service admin role to register the group"
        bob ##> "/mr PSA SimpleX-Directory admin"
        -- putStrLn "*** discover service joins group and creates the link for profile"
        bob <## "#PSA: you changed the role of SimpleX-Directory from member to admin"
        bob <# "SimpleX-Directory> Joining the group PSA…"
        bob <## "#PSA: SimpleX-Directory joined the group"
        bob <# "SimpleX-Directory> Joined the group PSA, creating the link…"
        bob <# "SimpleX-Directory> Created the public link to join the group via this directory service that is always online."
        bob <## ""
        bob <## "Please add it to the group welcome message."
        bob <## "For example, add:"
        welcomeWithLink <- dropStrPrefix "SimpleX-Directory> " . dropTime <$> getTermLine bob
        -- putStrLn "*** update profile without link"
        updateGroupProfile bob "Welcome!"
        bob <# "SimpleX-Directory> The profile updated for ID 1 (PSA), but the group link is not added to the welcome message."
        (superUser </)
        -- putStrLn "*** update profile so that it has link"
        updateGroupProfile bob welcomeWithLink
        bob <# "SimpleX-Directory> Thank you! The group link for ID 1 (PSA) is added to the welcome message."
        bob <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        approvalRequested superUser welcomeWithLink (1 :: Int)
        -- putStrLn "*** update profile so that it still has link"
        let welcomeWithLink' = "Welcome! " <> welcomeWithLink
        updateGroupProfile bob welcomeWithLink'
        bob <# "SimpleX-Directory> The group ID 1 (PSA) is updated!"
        bob <## "It is hidden from the directory until approved."
        superUser <# "SimpleX-Directory> The group ID 1 (PSA) is updated."
        approvalRequested superUser welcomeWithLink' (2 :: Int)
        -- putStrLn "*** try approving with the old registration code"
        superUser #> "@SimpleX-Directory /approve 1:PSA 1"
        superUser <# "SimpleX-Directory> > /approve 1:PSA 1"
        superUser <## "      Incorrect approval code"
        -- putStrLn "*** update profile so that it has no link"
        updateGroupProfile bob "Welcome!"
        bob <# "SimpleX-Directory> The group link for ID 1 (PSA) is removed from the welcome message."
        bob <## ""
        bob <## "The group is hidden from the directory until the group link is added and the group is re-approved."
        superUser <# "SimpleX-Directory> The group link is removed from ID 1 (PSA), de-listed."
        superUser #> "@SimpleX-Directory /approve 1:PSA 2"
        superUser <# "SimpleX-Directory> > /approve 1:PSA 2"
        superUser <## "      Error: the group ID 1 (PSA) is not pending approval."
        -- putStrLn "*** update profile so that it has link again"
        updateGroupProfile bob welcomeWithLink'
        bob <# "SimpleX-Directory> Thank you! The group link for ID 1 (PSA) is added to the welcome message."
        bob <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        approvalRequested superUser welcomeWithLink' (1 :: Int)
        superUser #> "@SimpleX-Directory /approve 1:PSA 1"
        superUser <# "SimpleX-Directory> > /approve 1:PSA 1"
        superUser <## "      Group approved!"
        bob <# "SimpleX-Directory> The group ID 1 (PSA) is approved and listed in directory!"
        bob <## "Please note: if you change the group profile it will be hidden from directory until it is re-approved."
        search bob "privacy" welcomeWithLink'
        search bob "security" welcomeWithLink'
        cath `connectVia` dsLink
        search cath "privacy" welcomeWithLink'
  where
    search u s welcome = do
      u #> ("@SimpleX-Directory " <> s)
      u <# ("SimpleX-Directory> > " <> s)
      u <## "      Found 1 group(s)"
      u <# "SimpleX-Directory> PSA (Privacy, Security & Anonymity)"
      u <## "Welcome message:"
      u <## welcome
    updateGroupProfile u welcome = do
      u ##> ("/set welcome #PSA " <> welcome)
      u <## "description changed to:"
      u <## welcome
    approvalRequested su welcome grId = do
      su <# "SimpleX-Directory> bob submitted the group ID 1: PSA (Privacy, Security & Anonymity)"
      su <## "Welcome message:"
      su <## welcome
      su <## ""
      su <## "To approve send:"
      su <# ("SimpleX-Directory> /approve 1:PSA " <> show grId)

testSuspendResume :: HasCallStack => FilePath -> IO ()
testSuspendResume tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      bob `connectVia` dsLink
      registerGroup superUser bob "privacy" "Privacy"
      groupFound bob "privacy"
      superUser #> "@SimpleX-Directory /suspend 1:privacy"
      superUser <# "SimpleX-Directory> > /suspend 1:privacy"
      superUser <## "      Group suspended!"
      bob <# "SimpleX-Directory> The group ID 1 (privacy) is suspended and hidden from directory. Please contact the administrators."
      groupNotFound bob "privacy"
      superUser #> "@SimpleX-Directory /resume 1:privacy"
      superUser <# "SimpleX-Directory> > /resume 1:privacy"
      superUser <## "      Group listing resumed!"
      bob <# "SimpleX-Directory> The group ID 1 (privacy) is listed in the directory again!"
      groupFound bob "privacy"

testDelistedOwnerLeaves :: HasCallStack => FilePath -> IO ()
testDelistedOwnerLeaves tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        leaveGroup "privacy" bob
        cath <## "#privacy: bob left the group"
        bob <# "SimpleX-Directory> You left the group ID 1 (privacy)."
        bob <## ""
        bob <## "The group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (group owner left)."
        groupNotFound cath "privacy"

testDelistedOwnerRemoved :: HasCallStack => FilePath -> IO ()
testDelistedOwnerRemoved tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob ->
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        removeMember "privacy" cath bob
        bob <# "SimpleX-Directory> You are removed from the group ID 1 (privacy)."
        bob <## ""
        bob <## "The group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (group owner is removed)."
        groupNotFound cath "privacy"

testNotDelistedMemberLeaves :: HasCallStack => FilePath -> IO ()
testNotDelistedMemberLeaves tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        leaveGroup "privacy" cath
        bob <## "#privacy: cath left the group"
        (superUser </)
        groupFound cath "privacy"

testNotDelistedMemberRemoved :: HasCallStack => FilePath -> IO ()
testNotDelistedMemberRemoved tmp = 
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        removeMember "privacy" bob cath
        (superUser </)
        groupFound cath "privacy"

testDelistedServiceRemoved :: HasCallStack => FilePath -> IO ()
testDelistedServiceRemoved tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        bob ##> "/rm #privacy SimpleX-Directory"
        bob <## "#privacy: you removed SimpleX-Directory from the group"
        cath <## "#privacy: bob removed SimpleX-Directory from the group"
        bob <# "SimpleX-Directory> SimpleX-Directory is removed from the group ID 1 (privacy)."
        bob <## ""
        bob <## "The group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (directory service is removed)."
        groupNotFound cath "privacy"

testDelistedRoleChanges :: HasCallStack => FilePath -> IO ()
testDelistedRoleChanges tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        groupFound cath "privacy"
        -- de-listed if service role changed
        bob ##> "/mr privacy SimpleX-Directory member"
        bob <## "#privacy: you changed the role of SimpleX-Directory from admin to member"
        cath <## "#privacy: bob changed the role of SimpleX-Directory from admin to member"
        bob <# "SimpleX-Directory> SimpleX-Directory role in the group ID 1 (privacy) is changed to member."
        bob <## ""
        bob <## "The group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (SimpleX-Directory role is changed to member)."
        groupNotFound cath "privacy"
        -- re-listed if service role changed back without profile changes
        cath ##> "/mr privacy SimpleX-Directory admin"
        cath <## "#privacy: you changed the role of SimpleX-Directory from member to admin"
        bob <## "#privacy: cath changed the role of SimpleX-Directory from member to admin"
        bob <# "SimpleX-Directory> SimpleX-Directory role in the group ID 1 (privacy) is changed to admin."
        bob <## ""
        bob <## "The group is listed in the directory again."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is listed (SimpleX-Directory role is changed to admin)."
        groupFound cath "privacy"
        -- de-listed if owner role changed
        cath ##> "/mr privacy bob admin"
        cath <## "#privacy: you changed the role of bob from owner to admin"
        bob <## "#privacy: cath changed your role from owner to admin"
        bob <# "SimpleX-Directory> Your role in the group ID 1 (privacy) is changed to admin."
        bob <## ""
        bob <## "The group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (user role is set to admin)."
        groupNotFound cath "privacy"
        -- re-listed if owner role changed back without profile changes
        cath ##> "/mr privacy bob owner"
        cath <## "#privacy: you changed the role of bob from admin to owner"
        bob <## "#privacy: cath changed your role from admin to owner"
        bob <# "SimpleX-Directory> Your role in the group ID 1 (privacy) is changed to owner."
        bob <## ""
        bob <## "The group is listed in the directory again."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is listed (user role is set to owner)."
        groupFound cath "privacy"

testNotDelistedMemberRoleChanged :: HasCallStack => FilePath -> IO ()
testNotDelistedMemberRoleChanged tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        groupFound cath "privacy"
        bob ##> "/mr privacy cath member"
        bob <## "#privacy: you changed the role of cath from owner to member"
        cath <## "#privacy: bob changed your role from owner to member"
        groupFound cath "privacy"

testNotSentApprovalBadRoles :: HasCallStack => FilePath -> IO ()
testNotSentApprovalBadRoles tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        cath `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        welcomeWithLink <- groupAccepted bob "privacy"
        bob ##> "/mr privacy SimpleX-Directory member"
        bob <## "#privacy: you changed the role of SimpleX-Directory from admin to member"
        updateProfileWithLink bob "privacy" welcomeWithLink 1
        bob <# "SimpleX-Directory> You must grant directory service admin role to register the group"
        bob ##> "/mr privacy SimpleX-Directory admin"
        bob <## "#privacy: you changed the role of SimpleX-Directory from member to admin"
        bob <# "SimpleX-Directory> SimpleX-Directory role in the group ID 1 (privacy) is changed to admin."
        bob <## ""
        bob <## "The group is submitted for approval."
        notifySuperUser superUser bob "privacy" "Privacy" welcomeWithLink 1
        groupNotFound cath "privacy"
        approveRegistration superUser bob "privacy" 1
        groupFound cath "privacy"

testNotApprovedBadRoles :: HasCallStack => FilePath -> IO ()
testNotApprovedBadRoles tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        cath `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        welcomeWithLink <- groupAccepted bob "privacy"
        updateProfileWithLink bob "privacy" welcomeWithLink 1
        notifySuperUser superUser bob "privacy" "Privacy" welcomeWithLink 1
        bob ##> "/mr privacy SimpleX-Directory member"
        bob <## "#privacy: you changed the role of SimpleX-Directory from admin to member"
        let approve = "/approve 1:privacy 1"
        superUser #> ("@SimpleX-Directory " <> approve)
        superUser <# ("SimpleX-Directory> > " <> approve)
        superUser <## "      Group is not approved: user is not an owner."
        groupNotFound cath "privacy"
        bob ##> "/mr privacy SimpleX-Directory admin"
        bob <## "#privacy: you changed the role of SimpleX-Directory from member to admin"
        bob <# "SimpleX-Directory> SimpleX-Directory role in the group ID 1 (privacy) is changed to admin."
        bob <## ""
        bob <## "The group is submitted for approval."
        notifySuperUser superUser bob "privacy" "Privacy" welcomeWithLink 1
        approveRegistration superUser bob "privacy" 1
        groupFound cath "privacy"

testRegOwnerChangedProfile :: HasCallStack => FilePath -> IO ()
testRegOwnerChangedProfile tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        bob ##> "/gp privacy privacy Privacy and Security"
        bob <## "full name changed to: Privacy and Security"
        bob <# "SimpleX-Directory> The group ID 1 (privacy) is updated!"
        bob <## "It is hidden from the directory until approved."
        cath <## "bob updated group #privacy:"
        cath <## "full name changed to: Privacy and Security"
        groupNotFound cath "privacy"
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is updated."
        reapproveGroup superUser bob
        groupFound cath "privacy"

testAnotherOwnerChangedProfile :: HasCallStack => FilePath -> IO ()
testAnotherOwnerChangedProfile tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        cath ##> "/gp privacy privacy Privacy and Security"
        cath <## "full name changed to: Privacy and Security"
        bob <## "cath updated group #privacy:"
        bob <## "full name changed to: Privacy and Security"
        bob <# "SimpleX-Directory> The group ID 1 (privacy) is updated!"
        bob <## "It is hidden from the directory until approved."
        groupNotFound cath "privacy"
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is updated."
        reapproveGroup superUser bob
        groupFound cath "privacy"

testRegOwnerRemovedLink :: HasCallStack => FilePath -> IO ()
testRegOwnerRemovedLink tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        bob ##> "/show welcome #privacy"
        bob <## "Welcome message:"
        welcomeWithLink <- getTermLine bob
        bob ##> "/set welcome #privacy Welcome!"
        bob <## "description changed to:"
        bob <## "Welcome!"
        bob <# "SimpleX-Directory> The group link for ID 1 (privacy) is removed from the welcome message."
        bob <## ""
        bob <## "The group is hidden from the directory until the group link is added and the group is re-approved."
        cath <## "bob updated group #privacy:"
        cath <## "description changed to:"
        cath <## "Welcome!"
        superUser <# "SimpleX-Directory> The group link is removed from ID 1 (privacy), de-listed."
        groupNotFound cath "privacy"
        bob ##> ("/set welcome #privacy " <> welcomeWithLink)
        bob <## "description changed to:"
        bob <## welcomeWithLink
        bob <# "SimpleX-Directory> Thank you! The group link for ID 1 (privacy) is added to the welcome message."
        bob <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        cath <## "bob updated group #privacy:"
        cath <## "description changed to:"
        cath <## welcomeWithLink
        reapproveGroup superUser bob
        groupFound cath "privacy"

testAnotherOwnerRemovedLink :: HasCallStack => FilePath -> IO ()
testAnotherOwnerRemovedLink tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        addCathAsOwner bob cath
        bob ##> "/show welcome #privacy"
        bob <## "Welcome message:"
        welcomeWithLink <- getTermLine bob
        cath ##> "/set welcome #privacy Welcome!"
        cath <## "description changed to:"
        cath <## "Welcome!"
        bob <## "cath updated group #privacy:"
        bob <## "description changed to:"
        bob <## "Welcome!"
        bob <# "SimpleX-Directory> The group link for ID 1 (privacy) is removed from the welcome message."
        bob <## ""
        bob <## "The group is hidden from the directory until the group link is added and the group is re-approved."
        superUser <# "SimpleX-Directory> The group link is removed from ID 1 (privacy), de-listed."
        groupNotFound cath "privacy"
        cath ##> ("/set welcome #privacy " <> welcomeWithLink)
        cath <## "description changed to:"
        cath <## welcomeWithLink
        bob <## "cath updated group #privacy:"
        bob <## "description changed to:"
        bob <## welcomeWithLink
        bob <# "SimpleX-Directory> The group link is added by another group member, your registration will not be processed."
        bob <## ""
        bob <## "Please update the group profile yourself."
        bob ##> ("/set welcome #privacy " <> welcomeWithLink <> " - welcome!")
        bob <## "description changed to:"
        bob <## (welcomeWithLink <> " - welcome!")
        bob <# "SimpleX-Directory> Thank you! The group link for ID 1 (privacy) is added to the welcome message."
        bob <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        cath <## "bob updated group #privacy:"
        cath <## "description changed to:"
        cath <## (welcomeWithLink <> " - welcome!")
        reapproveGroup superUser bob
        groupFound cath "privacy"

testDuplicateAskConfirmation :: HasCallStack => FilePath -> IO ()
testDuplicateAskConfirmation tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        _ <- groupAccepted bob "privacy"
        cath `connectVia` dsLink
        submitGroup cath "privacy" "Privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already submitted to the directory."
        cath <## "To confirm the registration, please send:"
        cath <# "SimpleX-Directory> /confirm 2:privacy"
        cath #> "@SimpleX-Directory /confirm 2:privacy"
        welcomeWithLink <- groupAccepted cath "privacy"
        groupNotFound bob "privacy"
        completeRegistration superUser cath "privacy" "Privacy" welcomeWithLink 2
        groupFound bob "privacy"

testDuplicateProhibitRegistration :: HasCallStack => FilePath -> IO ()
testDuplicateProhibitRegistration tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        registerGroup superUser bob "privacy" "Privacy"
        cath `connectVia` dsLink
        groupFound cath "privacy"
        _ <- submitGroup cath "privacy" "Privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already listed in the directory, please choose another name."

testDuplicateProhibitConfirmation :: HasCallStack => FilePath -> IO ()
testDuplicateProhibitConfirmation tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        welcomeWithLink <- groupAccepted bob "privacy"
        cath `connectVia` dsLink
        submitGroup cath "privacy" "Privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already submitted to the directory."
        cath <## "To confirm the registration, please send:"
        cath <# "SimpleX-Directory> /confirm 2:privacy"
        groupNotFound cath "privacy"
        completeRegistration superUser bob "privacy" "Privacy" welcomeWithLink 1
        groupFound cath "privacy"
        cath #> "@SimpleX-Directory /confirm 2:privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already listed in the directory, please choose another name."

testDuplicateProhibitWhenUpdated :: HasCallStack => FilePath -> IO ()
testDuplicateProhibitWhenUpdated tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        welcomeWithLink <- groupAccepted bob "privacy"
        cath `connectVia` dsLink
        submitGroup cath "privacy" "Privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already submitted to the directory."
        cath <## "To confirm the registration, please send:"
        cath <# "SimpleX-Directory> /confirm 2:privacy"
        cath #> "@SimpleX-Directory /confirm 2:privacy"
        welcomeWithLink' <- groupAccepted cath "privacy"
        groupNotFound cath "privacy"
        completeRegistration superUser bob "privacy" "Privacy" welcomeWithLink 1
        groupFound cath "privacy"
        cath ##> ("/set welcome privacy " <> welcomeWithLink')
        cath <## "description changed to:"
        cath <## welcomeWithLink'
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already listed in the directory, please choose another name."
        cath ##> "/gp privacy security Security"
        cath <## "changed to #security (Security)"
        cath <# "SimpleX-Directory> Thank you! The group link for ID 2 (security) is added to the welcome message."
        cath <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        notifySuperUser superUser cath "security" "Security" welcomeWithLink' 2
        approveRegistration superUser cath "security" 2
        groupFound bob "security"
        groupFound cath "security"

testDuplicateProhibitApproval :: HasCallStack => FilePath -> IO ()
testDuplicateProhibitApproval tmp =
  withDirectoryService tmp $ \superUser dsLink ->
    withNewTestChat tmp "bob" bobProfile $ \bob -> do
      withNewTestChat tmp "cath" cathProfile $ \cath -> do
        bob `connectVia` dsLink
        submitGroup bob "privacy" "Privacy"
        welcomeWithLink <- groupAccepted bob "privacy"
        cath `connectVia` dsLink
        submitGroup cath "privacy" "Privacy"
        cath <# "SimpleX-Directory> The group privacy (Privacy) is already submitted to the directory."
        cath <## "To confirm the registration, please send:"
        cath <# "SimpleX-Directory> /confirm 2:privacy"
        cath #> "@SimpleX-Directory /confirm 2:privacy"
        welcomeWithLink' <- groupAccepted cath "privacy"
        updateProfileWithLink cath "privacy" welcomeWithLink' 2
        notifySuperUser superUser cath "privacy" "Privacy" welcomeWithLink' 2
        groupNotFound cath "privacy"
        completeRegistration superUser bob "privacy" "Privacy" welcomeWithLink 1
        groupFound cath "privacy"
        -- fails at approval, as already listed
        let approve = "/approve 2:privacy 1"
        superUser #> ("@SimpleX-Directory " <> approve)
        superUser <# ("SimpleX-Directory> > " <> approve)
        superUser <## "      The group ID 2 (privacy) is already listed in the directory."

reapproveGroup :: HasCallStack => TestCC -> TestCC -> IO ()
reapproveGroup superUser bob = do
  superUser <#. "SimpleX-Directory> bob submitted the group ID 1: privacy ("
  superUser <## "Welcome message:"
  superUser <##. "Link to join the group privacy: "
  superUser <## ""
  superUser <## "To approve send:"
  superUser <# "SimpleX-Directory> /approve 1:privacy 1"
  superUser #> "@SimpleX-Directory /approve 1:privacy 1"
  superUser <# "SimpleX-Directory> > /approve 1:privacy 1"
  superUser <## "      Group approved!"
  bob <# "SimpleX-Directory> The group ID 1 (privacy) is approved and listed in directory!"
  bob <## "Please note: if you change the group profile it will be hidden from directory until it is re-approved."

addCathAsOwner :: HasCallStack => TestCC -> TestCC -> IO ()
addCathAsOwner bob cath = do
  connectUsers bob cath
  fullAddMember "privacy" "Privacy" bob cath GROwner
  joinGroup "privacy" cath bob
  cath <## "#privacy: member SimpleX-Directory is connected"

withDirectoryService :: HasCallStack => FilePath -> (TestCC -> String -> IO ()) -> IO ()
withDirectoryService tmp test = do
  dsLink <-
    withNewTestChat tmp serviceDbPrefix directoryProfile $ \ds ->
      withNewTestChat tmp "super_user" aliceProfile $ \superUser -> do
        connectUsers ds superUser
        ds ##> "/ad"
        getContactLink ds True
  let opts = mkDirectoryOpts tmp [KnownContact 2 "alice"]
  withDirectory opts $
    withTestChat tmp "super_user" $ \superUser -> do
      superUser <## "1 contacts connected (use /cs for the list)"
      test superUser dsLink
  where
    withDirectory :: DirectoryOpts -> IO () -> IO ()
    withDirectory opts@DirectoryOpts {directoryLog} action = do
      st <- getDirectoryStore directoryLog
      t <- forkIO $ bot st
      threadDelay 500000
      action `finally` killThread t
      where
        bot st = simplexChatCore testCfg (mkChatOpts opts) Nothing $ directoryService st opts

registerGroup :: TestCC -> TestCC -> String -> String -> IO ()
registerGroup su u n fn = do
  submitGroup u n fn
  welcomeWithLink <- groupAccepted u n
  completeRegistration su u n fn welcomeWithLink 1

submitGroup :: TestCC -> String -> String -> IO ()
submitGroup u n fn = do
  u ##> ("/g " <> n <> " " <> fn)
  u <## ("group #" <> n <> " (" <> fn <> ") is created")
  u <## ("to add members use /a " <> n <> " <name> or /create link #" <> n)
  u ##> ("/a " <> n <> " SimpleX-Directory admin")
  u <## ("invitation to join the group #" <> n <> " sent to SimpleX-Directory")

groupAccepted :: TestCC -> String -> IO String
groupAccepted u n = do
  u <# ("SimpleX-Directory> Joining the group " <> n <> "…")
  u <## ("#" <> n <> ": SimpleX-Directory joined the group")
  u <# ("SimpleX-Directory> Joined the group " <> n <> ", creating the link…")
  u <# "SimpleX-Directory> Created the public link to join the group via this directory service that is always online."
  u <## ""
  u <## "Please add it to the group welcome message."
  u <## "For example, add:"
  dropStrPrefix "SimpleX-Directory> " . dropTime <$> getTermLine u -- welcome message with link

completeRegistration :: TestCC -> TestCC -> String -> String -> String -> Int -> IO ()
completeRegistration su u n fn welcomeWithLink gId = do
  updateProfileWithLink u n welcomeWithLink gId
  notifySuperUser su u n fn welcomeWithLink gId
  approveRegistration su u n gId

updateProfileWithLink :: TestCC -> String -> String -> Int -> IO ()
updateProfileWithLink u n welcomeWithLink gId = do
  u ##> ("/set welcome " <> n <> " " <> welcomeWithLink)
  u <## "description changed to:"
  u <## welcomeWithLink
  u <# ("SimpleX-Directory> Thank you! The group link for ID " <> show gId <> " (" <> n <> ") is added to the welcome message.")
  u <## "You will be notified once the group is added to the directory - it may take up to 24 hours."

notifySuperUser :: TestCC -> TestCC -> String -> String -> String -> Int -> IO ()
notifySuperUser su u n fn welcomeWithLink gId = do
  uName <- userName u
  su <# ("SimpleX-Directory> " <> uName <> " submitted the group ID " <> show gId <> ": " <> n <> " (" <> fn <> ")")
  su <## "Welcome message:"
  su <## welcomeWithLink
  su <## ""
  su <## "To approve send:"
  let approve = "/approve " <> show gId <> ":" <> n <> " 1"
  su <# ("SimpleX-Directory> " <> approve)

approveRegistration :: TestCC -> TestCC -> String -> Int -> IO ()
approveRegistration su u n gId = do
  let approve = "/approve " <> show gId <> ":" <> n <> " 1"
  su #> ("@SimpleX-Directory " <> approve)
  su <# ("SimpleX-Directory> > " <> approve)
  su <## "      Group approved!"
  u <# ("SimpleX-Directory> The group ID " <> show gId <> " (" <> n <> ") is approved and listed in directory!")
  u <## "Please note: if you change the group profile it will be hidden from directory until it is re-approved."

connectVia :: TestCC -> String -> IO ()
u `connectVia` dsLink = do
  u ##> ("/c " <> dsLink)
  u <## "connection request sent!"
  u <## "SimpleX-Directory: contact is connected"
  u <# "SimpleX-Directory> Welcome to SimpleX-Directory service!"
  u <## "Send a search string to find groups or /help to learn how to add groups to directory."
  u <## ""
  u <## "For example, send privacy to find groups about privacy."

joinGroup :: String -> TestCC -> TestCC -> IO ()
joinGroup gName member host = do
  let gn = "#" <> gName
  memberName <- userName member
  hostName <- userName host
  member ##> ("/j " <> gName)
  member <## (gn <> ": you joined the group")
  member <#. (gn <> " " <> hostName <> "> Link to join the group " <> gName <> ": ")
  host <## (gn <> ": " <> memberName <> " joined the group")

leaveGroup :: String -> TestCC -> IO ()
leaveGroup gName member = do
  let gn = "#" <> gName
  member ##> ("/l " <> gName)
  member <## (gn <> ": you left the group")
  member <## ("use /d " <> gn <> " to delete the group")

removeMember :: String -> TestCC -> TestCC -> IO ()
removeMember gName admin removed = do
  let gn = "#" <> gName
  adminName <- userName admin
  removedName <- userName removed
  admin ##> ("/rm " <> gName <> " " <> removedName)
  admin <## (gn <> ": you removed " <> removedName <> " from the group")
  removed <## (gn <> ": " <> adminName <> " removed you from the group")
  removed <## ("use /d " <> gn <> " to delete the group")

groupFound :: TestCC -> String -> IO ()
groupFound u name = do
  u #> ("@SimpleX-Directory " <> name)
  u <# ("SimpleX-Directory> > " <> name)
  u <## "      Found 1 group(s)"
  u <#. ("SimpleX-Directory> " <> name <> " (")
  u <## "Welcome message:"
  u <##. "Link to join the group privacy: "

groupNotFound :: TestCC -> String -> IO ()
groupNotFound u s = do
  u #> ("@SimpleX-Directory " <> s)
  u <# ("SimpleX-Directory> > " <> s)
  u <## "      No groups found"
