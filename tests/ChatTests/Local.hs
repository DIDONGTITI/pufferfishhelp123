{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PostfixOperators #-}

module ChatTests.Local where

import ChatClient
import ChatTests.Utils
import System.Directory (copyFile, doesFileExist)
import Test.Hspec
import System.FilePath (takeFileName, (</>))
import Data.Time (getCurrentTime)
import ChatTests.ChatList (getChats_)
import Data.Time.Format.ISO8601 (iso8601Show)

chatLocalTests :: SpecWith FilePath
chatLocalTests = do
  describe "note folders" $ do
    it "create folders, add notes, read, search" testNotes
    it "switch users" testUserNotes
    it "preview pagination for notes" testPreviewsPagination
    it "stores files" testFiles

testNotes :: FilePath -> IO ()
testNotes tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  alice ##> "/contacts"
  -- not a contact

  alice #> "$notes keep in mind"
  alice ##> "/tail"
  alice <# "$notes keep in mind"
  alice ##> "/chats"
  alice <# "$notes keep in mind"
  alice ##> "/? keep"
  alice <# "$notes keep in mind"

  alice #$> ("/_read chat $1 from=1 to=100", id, "ok")
  alice ##> "/_unread chat $1 on"
  alice <## "ok"

  alice ##> "/_delete item $1 1 internal"
  alice <## "message deleted"
  alice ##> "/tail"
  alice ##> "/chats"

  alice #> "$notes ahoy!"
  alice ##> "/_update item $1 1 text Greetings."
  alice ##> "/tail $notes"
  alice <# "$notes Greetings."

testUserNotes :: FilePath -> IO ()
testUserNotes tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  alice #> "$notes keep in mind"
  alice ##> "/tail"
  alice <# "$notes keep in mind"

  alice ##> "/create user secret"
  alice <## "user profile: secret"
  alice <## "use /p <display name> to change it"
  alice <## "(the updated profile will be sent to all your contacts)"

  alice ##> "/tail"

  alice ##> "/_delete item $1 1 internal"
  alice <## "chat db error: SENoteFolderNotFound {noteFolderId = 1}"

testPreviewsPagination :: FilePath -> IO ()
testPreviewsPagination tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  tsS <- iso8601Show <$> getCurrentTime
  alice #> "$notes first"
  tsM <- iso8601Show <$> getCurrentTime
  alice #> "$notes last"
  tsE <- iso8601Show <$> getCurrentTime

  -- there's only one folder that got updated after tsM and before tsE
  getChats_ alice "count=3" [("$notes", "last")]
  getChats_ alice ("after=" <> tsE <> " count=10") []
  getChats_ alice ("after=" <> tsS <> " count=10") [("$notes", "last")]
  getChats_ alice ("before=" <> tsM <> " count=10") []
  getChats_ alice ("before=" <> tsE <> " count=10") [("$notes", "last")]
  getChats_ alice ("before=" <> tsS <> " count=10") []

testFiles :: FilePath -> IO ()
testFiles tmp = withNewTestChat tmp "alice" aliceProfile $ \alice -> do
  -- setup
  let files = "./tests/tmp/app_files"
  alice ##> ("/_files_folder " <> files)
  alice <## "ok"

  -- ui-like upload
  let source = "./tests/fixtures/test.jpg"
  let stored = files </> takeFileName source
  copyFile source stored
  alice ##> "/_create $1 json {\"filePath\": \"test.jpg\", \"msgContent\": {\"text\":\"hi myself\",\"type\":\"image\",\"image\":\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIAQMAAAD+wSzIAAAABlBMVEX///+/v7+jQ3Y5AAAADklEQVQI12P4AIX8EAgALgAD/aNpbtEAAAAASUVORK5CYII=\"}}"
  alice <# "$notes hi myself"
  alice <# "$notes file 1 (test.jpg)"

  alice ##> "/tail"
  alice <# "$notes hi myself"
  alice <# "$notes file 1 (test.jpg)"

  alice ##> "/_get chat $1 count=100"
  r <- chatF <$> getTermLine alice
  r `shouldBe` [((1, "hi myself"), Just "test.jpg")]

  alice ##> "/fs 1"
  alice <## "local file 1 (test.jpg)"

  -- one more file
  let stored2 = files </> "another_test.jpg"
  copyFile source stored2
  alice ##> "/_create $1 json {\"filePath\": \"another_test.jpg\", \"msgContent\": {\"text\":\"\",\"type\":\"image\",\"image\":\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIAQMAAAD+wSzIAAAABlBMVEX///+/v7+jQ3Y5AAAADklEQVQI12P4AIX8EAgALgAD/aNpbtEAAAAASUVORK5CYII=\"}}"
  alice <# "$notes file 2 (another_test.jpg)"

  alice ##> "/_delete item $1 2 internal"
  alice <## "message deleted"
  doesFileExist stored2 `shouldReturn` False
  doesFileExist stored `shouldReturn` True

  alice ##> "/clear $notes"
  alice ##> "/tail"
  doesFileExist stored `shouldReturn` False
  alice ##> "/fs 1"
  alice <## "chat db error: SEChatItemNotFoundByFileId {fileId = 1}"
