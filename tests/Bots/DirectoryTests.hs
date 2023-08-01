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
  describe "de-listing the group" $ do
    it "should de-list if owner leaves the group" testDelistedOwnerLeaves
    it "should de-list if owner is removed from the group" testDelistedOwnerRemoved
    it "should NOT de-list if another member leaves the group" testNotDelistedMemberLeaves
    it "should NOT de-list if another member is removed from the group" testNotDelistedMemberRemoved
    it "should de-list if service is removed from the group" testDelistedServiceRemoved
  describe "should require re-approval if profile is changed by" $ do
    it "the registration owner" testRegOwnerChangedProfile
    it "another owner" testAnotherOwnerChangedProfile
  describe "should require profile update if group link is removed by " $ do
    it "the registration owner" testRegOwnerRemovedLink
    it "another owner" testAnotherOwnerRemovedLink

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
        putStrLn "*** create a group"
        bob ##> "/g PSA Privacy, Security & Anonymity"
        bob <## "group #PSA (Privacy, Security & Anonymity) is created"
        bob <## "to add members use /a PSA <name> or /create link #PSA"
        bob ##> "/a PSA SimpleX-Directory member"
        bob <## "invitation to join the group #PSA sent to SimpleX-Directory"
        bob <# "SimpleX-Directory> You must grant directory service admin role to register the group"
        bob ##> "/mr PSA SimpleX-Directory admin"
        putStrLn "*** discover service joins group and creates the link for profile"
        bob <## "#PSA: you changed the role of SimpleX-Directory from member to admin"
        bob <# "SimpleX-Directory> Joining the group #PSA…"
        bob <## "#PSA: SimpleX-Directory joined the group"
        bob <# "SimpleX-Directory> Joined the group #PSA, creating the link…"
        bob <# "SimpleX-Directory> Created the public link to join the group via this directory service that is always online."
        bob <## ""
        bob <## "Please add it to the group welcome message."
        bob <## "For example, add:"
        welcomeWithLink <- dropStrPrefix "SimpleX-Directory> " . dropTime <$> getTermLine bob
        putStrLn "*** update profile without link"
        updateGroupProfile bob "Welcome!"
        bob <# "SimpleX-Directory> The profile updated for ID 1 (PSA), but the group link is not added to the welcome message."
        (superUser </)
        putStrLn "*** update profile so that it has link"
        updateGroupProfile bob welcomeWithLink
        bob <# "SimpleX-Directory> Thank you! The group link for ID 1 (PSA) is added to the welcome message."
        bob <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
        approvalRequested superUser welcomeWithLink (1 :: Int)
        putStrLn "*** update profile so that it still has link"
        let welcomeWithLink' = "Welcome! " <> welcomeWithLink
        updateGroupProfile bob welcomeWithLink'
        bob <# "SimpleX-Directory> The group ID 1 (PSA) is updated!"
        bob <## "It is hidden from the directory until approved."
        superUser <# "SimpleX-Directory> The group ID 1 (PSA) is updated."
        approvalRequested superUser welcomeWithLink' (2 :: Int)
        putStrLn "*** try approving with the old registration code"
        superUser #> "@SimpleX-Directory /approve 1:PSA 1"
        superUser <# "SimpleX-Directory> > /approve 1:PSA 1"
        superUser <## "      Incorrect approval code"
        putStrLn "*** update profile so that it has no link"
        updateGroupProfile bob "Welcome!"
        bob <# "SimpleX-Directory> The group link for ID 1 (PSA) is removed from the welcome message."
        bob <## ""
        bob <## "The group is hidden from the directory until the group link is added and the group is re-approved."
        superUser <# "SimpleX-Directory> The group link is removed from ID 1 (PSA), de-listed."
        superUser #> "@SimpleX-Directory /approve 1:PSA 2"
        superUser <# "SimpleX-Directory> > /approve 1:PSA 2"
        superUser <## "      Error: the group ID 1 (PSA) is not pending approval."
        putStrLn "*** update profile so that it has link again"
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
        bob <## "Group is no longer listed in the directory."
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
        bob <## "Group is no longer listed in the directory."
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
        bob <## "Group is no longer listed in the directory."
        superUser <# "SimpleX-Directory> The group ID 1 (privacy) is de-listed (directory service is removed)."
        groupNotFound cath "privacy"

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
  u ##> ("/g " <> n <> " " <> fn)
  u <## ("group #" <> n <> " (" <> fn <> ") is created")
  u <## ("to add members use /a " <> n <> " <name> or /create link #" <> n)
  u ##> ("/a " <> n <> " SimpleX-Directory admin")
  u <## ("invitation to join the group #" <> n <> " sent to SimpleX-Directory")
  u <# ("SimpleX-Directory> Joining the group #" <> n <> "…")
  u <## ("#" <> n <> ": SimpleX-Directory joined the group")
  u <# ("SimpleX-Directory> Joined the group #" <> n <> ", creating the link…")
  u <# "SimpleX-Directory> Created the public link to join the group via this directory service that is always online."
  u <## ""
  u <## "Please add it to the group welcome message."
  u <## "For example, add:"
  welcomeWithLink <- dropStrPrefix "SimpleX-Directory> " . dropTime <$> getTermLine u
  u ##> ("/set welcome " <> n <> " " <> welcomeWithLink)
  u <## "description changed to:"
  u <## welcomeWithLink
  u <# ("SimpleX-Directory> Thank you! The group link for ID 1 (" <> n <> ") is added to the welcome message.")
  u <## "You will be notified once the group is added to the directory - it may take up to 24 hours."
  su <# ("SimpleX-Directory> bob submitted the group ID 1: " <> n <> " (" <> fn <> ")")
  su <## "Welcome message:"
  su <## welcomeWithLink
  su <## ""
  su <## "To approve send:"
  let approve = "/approve 1:" <> n <> " 1"
  su <# ("SimpleX-Directory> " <> approve)
  su #> ("@SimpleX-Directory " <> approve)
  su <# ("SimpleX-Directory> > " <> approve)
  su <## "      Group approved!"
  u <# ("SimpleX-Directory> The group ID 1 (" <> n <> ") is approved and listed in directory!")
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
groupFound u s = do
  u #> ("@SimpleX-Directory " <> s)
  u <# ("SimpleX-Directory> > " <> s)
  u <## "      Found 1 group(s)"
  u <#. "SimpleX-Directory> privacy ("
  u <## "Welcome message:"
  u <##. "Link to join the group privacy: "

groupNotFound :: TestCC -> String -> IO ()
groupNotFound u s = do
  u #> ("@SimpleX-Directory " <> s)
  u <# ("SimpleX-Directory> > " <> s)
  u <## "      No groups found"
