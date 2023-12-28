{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PostfixOperators #-}

module ChatTests.Local where

import ChatClient
import ChatTests.Utils
import Test.Hspec
import System.Directory (copyFile)

chatLocalTests :: SpecWith FilePath
chatLocalTests = do
  fdescribe "note folders" $ do
    it "create folders, add notes, read, search" testNotes
    it "switch users" testUserNotes
    it "stores files" testFiles

testNotes :: FilePath -> IO ()
testNotes tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  createFolder alice "self"

  alice ##> "/contacts"
  -- not a contact

  alice #> "$self keep in mind"
  alice ##> "/tail"
  alice <# "$self keep in mind"
  alice ##> "/chats"
  alice <# "$self keep in mind"
  alice ##> "/? keep"
  alice <# "$self keep in mind"

  alice #$> ("/_read chat $1 from=1 to=100", id, "ok")
  alice ##> "/_unread chat $1 on"
  alice <## "ok"

  alice ##> "/_delete item $1 1 internal"
  alice <## "message deleted"
  alice ##> "/tail"
  alice ##> "/chats"

  alice #> "$self ahoy!"
  alice ##> "/_update item $1 1 text Greetings."
  alice ##> "/tail $self"
  alice <# "$self Greetings."

  alice ##> "/delete $self"
  alice <## "note folder self deleted"

testUserNotes :: FilePath -> IO ()
testUserNotes tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  createFolder alice "self"

  alice #> "$self keep in mind"
  alice ##> "/tail"
  alice <# "$self keep in mind"

  alice ##> "/create user secret"
  alice <## "user profile: secret"
  alice <## "use /p <display name> to change it"
  alice <## "(the updated profile will be sent to all your contacts)"

  createFolder alice "gossip"
  alice ##> "/tail"

  alice ##> "/_delete item $1 1 internal"
  alice <## "chat db error: SENoteFolderNotFound {noteFolderId = 1}"

testFiles :: FilePath -> IO ()
testFiles tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  createFolder alice "self"

  alice #$> ("/_files_folder ./tests/tmp/app_files", id, "ok")
  copyFile "./tests/fixtures/test.jpg" "./tests/tmp/app_files/test.jpg"
  alice ##> "/_create $1 json {\"filePath\": \"test.jpg\", \"msgContent\": {\"text\":\"\",\"type\":\"image\",\"image\":\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIAQMAAAD+wSzIAAAABlBMVEX///+/v7+jQ3Y5AAAADklEQVQI12P4AIX8EAgALgAD/aNpbtEAAAAASUVORK5CYII=\"}}"
  alice <# "$self file 1 (test.jpg)"
  alice ##> "/tail"
  alice <# "$self file 1 (test.jpg)"
  alice ##> "/fs 1"
  alice <## "local file 1 (test.jpg)"

  alice ##> "/clear $self"
  alice ##> "/fs 1"
  alice <## "chat db error: SEChatItemNotFoundByFileId {fileId = 1}"

createFolder :: TestCC -> String -> IO ()
createFolder cc label = do
  cc ##> ("/note folder " <> label)
  cc <## ("new note folder created, use $" <> label <> " to create a note")
