{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module RemoteTests where

import ChatClient
import ChatTests.Utils
import Control.Logger.Simple
import Control.Monad
import qualified Data.Aeson as J
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as M
import Network.HTTP.Types (ok200)
import qualified Network.HTTP2.Client as C
import qualified Network.HTTP2.Server as S
import qualified Network.Socket as N
import qualified Network.TLS as TLS
import Simplex.Chat.Archive (archiveFilesFolder)
import Simplex.Chat.Controller (ChatConfig (..), XFTPFileConfig (..))
import qualified Simplex.Chat.Controller as Controller
import Simplex.Chat.Mobile.File
import Simplex.Chat.Remote.Types
import qualified Simplex.Chat.Remote.Discovery as Discovery
import qualified Simplex.Messaging.Crypto as C
import Simplex.Messaging.Crypto.File (CryptoFileArgs (..))
import Simplex.Messaging.Encoding.String
import qualified Simplex.Messaging.Transport as Transport
import Simplex.Messaging.Transport.Client (TransportHost (..))
import Simplex.Messaging.Transport.Credentials (genCredentials, tlsCredentials)
import Simplex.Messaging.Transport.HTTP2.Client (HTTP2Response (..), closeHTTP2Client, sendRequest)
import Simplex.Messaging.Transport.HTTP2.Server (HTTP2Request (..))
import Simplex.Messaging.Util
import System.FilePath ((</>))
import Test.Hspec
import UnliftIO
import UnliftIO.Concurrent
import UnliftIO.Directory

remoteTests :: SpecWith FilePath
remoteTests = describe "Remote" $ do
  it "generates usable credentials" genCredentialsTest
  it "connects announcer with discoverer over reverse-http2" announceDiscoverHttp2Test
  it "performs protocol handshake" remoteHandshakeTest
  it "performs protocol handshake (again)" remoteHandshakeTest -- leaking servers regression check
  it "sends messages" remoteMessageTest
  describe "remote files" $ do
    it "store/get/send/receive files" remoteStoreFileTest
    it "should sends files from CLI wihtout /store" remoteCLIFileTest

-- * Low-level TLS with ephemeral credentials

genCredentialsTest :: (HasCallStack) => FilePath -> IO ()
genCredentialsTest _tmp = do
  (fingerprint, credentials) <- genTestCredentials
  started <- newEmptyTMVarIO
  bracket (Discovery.startTLSServer started credentials serverHandler) cancel $ \_server -> do
    ok <- atomically (readTMVar started)
    unless ok $ error "TLS server failed to start"
    Discovery.connectTLSClient "127.0.0.1" fingerprint clientHandler
  where
    serverHandler serverTls = do
      logNote "Sending from server"
      Transport.putLn serverTls "hi client"
      logNote "Reading from server"
      Transport.getLn serverTls `shouldReturn` "hi server"
    clientHandler clientTls = do
      logNote "Sending from client"
      Transport.putLn clientTls "hi server"
      logNote "Reading from client"
      Transport.getLn clientTls `shouldReturn` "hi client"

-- * UDP discovery and rever HTTP2

announceDiscoverHttp2Test :: (HasCallStack) => FilePath -> IO ()
announceDiscoverHttp2Test _tmp = do
  (fingerprint, credentials) <- genTestCredentials
  tasks <- newTVarIO []
  finished <- newEmptyMVar
  controller <- async $ do
    logNote "Controller: starting"
    bracket
      (Discovery.announceRevHTTP2 tasks fingerprint credentials (putMVar finished ()) >>= either (fail . show) pure)
      closeHTTP2Client
      ( \http -> do
          logNote "Controller: got client"
          sendRequest http (C.requestNoBody "GET" "/" []) (Just 10000000) >>= \case
            Left err -> do
              logNote "Controller: got error"
              fail $ show err
            Right HTTP2Response {} ->
              logNote "Controller: got response"
      )
  host <- async $ Discovery.withListener $ \sock -> do
    (N.SockAddrInet _port addr, invite) <- Discovery.recvAnnounce sock
    strDecode invite `shouldBe` Right fingerprint
    logNote "Host: connecting"
    server <- async $ Discovery.connectTLSClient (THIPv4 $ N.hostAddressToTuple addr) fingerprint $ \tls -> do
      logNote "Host: got tls"
      flip Discovery.attachHTTP2Server tls $ \HTTP2Request {sendResponse} -> do
        logNote "Host: got request"
        sendResponse $ S.responseNoBody ok200 []
        logNote "Host: sent response"
    takeMVar finished `finally` cancel server
    logNote "Host: finished"
  tasks `registerAsync` controller
  tasks `registerAsync` host
  (waitBoth host controller `shouldReturn` ((), ())) `finally` cancelTasks tasks

-- * Chat commands

remoteHandshakeTest :: (HasCallStack) => FilePath -> IO ()
remoteHandshakeTest = testChat2 aliceProfile bobProfile $ \desktop mobile -> do
  desktop ##> "/list remote hosts"
  desktop <## "No remote hosts"

  startRemote mobile desktop

  logNote "Session active"

  desktop ##> "/list remote hosts"
  desktop <## "Remote hosts:"
  desktop <## "1.  (active)"
  mobile ##> "/list remote ctrls"
  mobile <## "Remote controllers:"
  mobile <## "1. My desktop (active)"

  stopMobile mobile desktop `catchAny` (logError . tshow)
  -- TODO: add a case for 'stopDesktop'

  desktop ##> "/delete remote host 1"
  desktop <## "ok"
  desktop ##> "/list remote hosts"
  desktop <## "No remote hosts"

  mobile ##> "/delete remote ctrl 1"
  mobile <## "ok"
  mobile ##> "/list remote ctrls"
  mobile <## "No remote controllers"

remoteMessageTest :: (HasCallStack) => FilePath -> IO ()
remoteMessageTest = testChat3 aliceProfile aliceDesktopProfile bobProfile $ \mobile desktop bob -> do
  startRemote mobile desktop
  contactBob desktop bob

  logNote "sending messages"
  desktop #> "@bob hello there 🙂"
  bob <# "alice> hello there 🙂"
  bob #> "@alice hi"
  desktop <# "bob> hi"

  logNote "post-remote checks"
  stopMobile mobile desktop

  mobile ##> "/contacts"
  mobile <## "bob (Bob)"

  bob ##> "/contacts"
  bob <## "alice (Alice)"

  desktop ##> "/contacts"
  -- empty contact list on desktop-local

  threadDelay 1000000
  logNote "done"

remoteStoreFileTest :: HasCallStack => FilePath -> IO ()
remoteStoreFileTest =
  testChatCfg3 cfg aliceProfile aliceDesktopProfile bobProfile $ \mobile desktop bob ->
    withXFTPServer $ do
      let mobileFiles = "./tests/tmp/mobile_files"
      mobile ##> ("/_files_folder " <> mobileFiles)
      mobile <## "ok"
      let desktopFiles = "./tests/tmp/desktop_files"
      desktop ##> ("/_files_folder " <> desktopFiles)
      desktop <## "ok"
      let desktopHostFiles = "./tests/tmp/remote_hosts_data"
      desktop ##> ("/remote_hosts_folder " <> desktopHostFiles)
      desktop <## "ok"
      let bobFiles = "./tests/tmp/bob_files"
      bob ##> ("/_files_folder " <> bobFiles)
      bob <## "ok"
      startRemote mobile desktop
      contactBob desktop bob
      rhs <- readTVarIO (Controller.remoteHostSessions $ chatController desktop)
      desktopHostStore <- case M.lookup 1 rhs of
        Just RemoteHostSession {storePath} -> pure $ desktopHostFiles </> storePath </> archiveFilesFolder
        _ -> fail "Host session 1 should be started"
      desktop ##> "/store remote file 1 tests/fixtures/test.pdf"
      desktop <## "file test.pdf stored on remote host 1"
      src <- B.readFile "tests/fixtures/test.pdf"
      B.readFile (mobileFiles </> "test.pdf") `shouldReturn` src
      B.readFile (desktopHostStore </> "test.pdf") `shouldReturn` src
      desktop ##> "/store remote file 1 tests/fixtures/test.pdf"
      desktop <## "file test_1.pdf stored on remote host 1"
      B.readFile (mobileFiles </> "test_1.pdf") `shouldReturn` src
      B.readFile (desktopHostStore </> "test_1.pdf") `shouldReturn` src
      desktop ##> "/store remote file 1 encrypt=on tests/fixtures/test.pdf"
      desktop <## "file test_2.pdf stored on remote host 1"
      Just cfArgs@(CFArgs key nonce) <- J.decode . LB.pack <$> getTermLine desktop
      chatReadFile (mobileFiles </> "test_2.pdf") (strEncode key) (strEncode nonce) `shouldReturn` Right (LB.fromStrict src)
      chatReadFile (desktopHostStore </> "test_2.pdf") (strEncode key) (strEncode nonce) `shouldReturn` Right (LB.fromStrict src)

      removeFile (desktopHostStore </> "test_1.pdf")
      removeFile (desktopHostStore </> "test_2.pdf")

      -- cannot get file before it is used
      desktop ##> "/get remote file 1 {\"userId\": 1, \"fileId\": 1, \"sent\": true, \"fileSource\": {\"filePath\": \"test_1.pdf\"}}"
      hostError desktop "SEFileNotFound"
      -- send file not encrypted locally on mobile host
      desktop ##> "/_send @2 json {\"filePath\": \"test_1.pdf\", \"msgContent\": {\"type\": \"file\", \"text\": \"sending a file\"}}"
      desktop <# "@bob sending a file"
      desktop <# "/f @bob test_1.pdf" 
      desktop <## "use /fc 1 to cancel sending"
      bob <# "alice> sending a file"
      bob <# "alice> sends file test_1.pdf (266.0 KiB / 272376 bytes)"
      bob <## "use /fr 1 [<dir>/ | <path>] to receive it"
      bob ##> "/fr 1"
      concurrentlyN_
        [ do
            desktop <## "completed uploading file 1 (test_1.pdf) for bob",
          do
            bob <## "saving file 1 from alice to test_1.pdf"
            bob <## "started receiving file 1 (test_1.pdf) from alice"
            bob <## "completed receiving file 1 (test_1.pdf) from alice"
        ]
      B.readFile (bobFiles </> "test_1.pdf") `shouldReturn` src
      -- returns error for inactive user
      desktop ##> "/get remote file 1 {\"userId\": 2, \"fileId\": 1, \"sent\": true, \"fileSource\": {\"filePath\": \"test_1.pdf\"}}"
      hostError desktop "CEDifferentActiveUser"
      -- returns error with incorrect file ID
      desktop ##> "/get remote file 1 {\"userId\": 1, \"fileId\": 2, \"sent\": true, \"fileSource\": {\"filePath\": \"test_1.pdf\"}}"
      hostError desktop "SEFileNotFound"
      -- gets file
      doesFileExist (desktopHostStore </> "test_1.pdf") `shouldReturn` False
      desktop ##> "/get remote file 1 {\"userId\": 1, \"fileId\": 1, \"sent\": true, \"fileSource\": {\"filePath\": \"test_1.pdf\"}}"
      desktop <## "ok"
      B.readFile (desktopHostStore </> "test_1.pdf") `shouldReturn` src

      -- send file encrypted locally on mobile host
      desktop ##> ("/_send @2 json {\"fileSource\": {\"filePath\":\"test_2.pdf\", \"cryptoArgs\": " <> LB.unpack (J.encode cfArgs) <> "}, \"msgContent\": {\"type\": \"file\", \"text\": \"\"}}")
      desktop <# "/f @bob test_2.pdf" 
      desktop <## "use /fc 2 to cancel sending"
      bob <# "alice> sends file test_2.pdf (266.0 KiB / 272376 bytes)"
      bob <## "use /fr 2 [<dir>/ | <path>] to receive it"
      bob ##> "/fr 2"
      concurrentlyN_
        [ do
            desktop <## "completed uploading file 2 (test_2.pdf) for bob",
          do
            bob <## "saving file 2 from alice to test_2.pdf"
            bob <## "started receiving file 2 (test_2.pdf) from alice"
            bob <## "completed receiving file 2 (test_2.pdf) from alice"
        ]
      B.readFile (bobFiles </> "test_2.pdf") `shouldReturn` src

      -- receive file via remote host
      copyFile "./tests/fixtures/test.jpg" (bobFiles </> "test.jpg")
      bob #> "/f @alice test.jpg"
      bob <## "use /fc 3 to cancel sending"
      desktop <# "bob> sends file test.jpg (136.5 KiB / 139737 bytes)"
      desktop <## "use /fr 3 [<dir>/ | <path>] to receive it"
      desktop ##> "/fr 3 encrypt=on"
      concurrentlyN_
        [ do
            bob <## "completed uploading file 3 (test.jpg) for alice",
          do
            desktop <## "saving file 3 from bob to test.jpg"
            desktop <## "started receiving file 3 (test.jpg) from bob"
            desktop <## "completed receiving file 3 (test.jpg) from bob"
        ]
      Just cfArgs'@(CFArgs key' nonce') <- J.decode . LB.pack <$> getTermLine desktop
      desktop <## "File received to connected remote host 1"
      desktop <## "To download to this device use:"
      getCmd <- getTermLine desktop
      getCmd `shouldBe` ("/get remote file 1 {\"userId\":1,\"fileId\":3,\"sent\":false,\"fileSource\":{\"filePath\":\"test.jpg\",\"cryptoArgs\":" <> LB.unpack (J.encode cfArgs') <> "}}")
      src' <- B.readFile (bobFiles </> "test.jpg")
      chatReadFile (mobileFiles </> "test.jpg") (strEncode key') (strEncode nonce') `shouldReturn` Right (LB.fromStrict src')
      doesFileExist (desktopHostStore </> "test.jpg") `shouldReturn` False
      -- returns error with incorrect key
      desktop ##> "/get remote file 1 {\"userId\": 1, \"fileId\": 3, \"sent\": false, \"fileSource\": {\"filePath\": \"test.jpg\", \"cryptoArgs\": null}}"
      hostError desktop "SEFileNotFound"
      doesFileExist (desktopHostStore </> "test.jpg") `shouldReturn` False
      desktop ##> getCmd
      desktop <## "ok"
      chatReadFile (desktopHostStore </> "test.jpg") (strEncode key') (strEncode nonce') `shouldReturn` Right (LB.fromStrict src')

      stopMobile mobile desktop
  where
    cfg = testCfg {xftpFileConfig = Just $ XFTPFileConfig {minFileSize = 0}, tempDir = Just "./tests/tmp/tmp"}
    hostError cc err = do
      r <- getTermLine cc
      r `shouldStartWith` "remote host 1 error"
      r `shouldContain` err

remoteCLIFileTest :: (HasCallStack) => FilePath -> IO ()
remoteCLIFileTest = testChatCfg3 cfg aliceProfile aliceDesktopProfile bobProfile $ \mobile desktop bob -> withXFTPServer $ do
  createDirectoryIfMissing True "./tests/tmp/tmp/"
  let mobileFiles = "./tests/tmp/mobile_files"
  mobile ##> ("/_files_folder " <> mobileFiles)
  mobile <## "ok"
  let bobFiles = "./tests/tmp/bob_files/"
  createDirectoryIfMissing True bobFiles
  let desktopHostFiles = "./tests/tmp/remote_hosts_data"
  desktop ##> ("/remote_hosts_folder " <> desktopHostFiles)
  desktop <## "ok"

  startRemote mobile desktop
  contactBob desktop bob

  rhs <- readTVarIO (Controller.remoteHostSessions $ chatController desktop)
  desktopHostStore <- case M.lookup 1 rhs of
    Just RemoteHostSession {storePath} -> pure $ desktopHostFiles </> storePath </> archiveFilesFolder
    _ -> fail "Host session 1 should be started"

  mobileName <- userName mobile

  bob #> ("/f @" <> mobileName <> " " <> "tests/fixtures/test.pdf")
  bob <## "use /fc 1 to cancel sending"

  desktop <# "bob> sends file test.pdf (266.0 KiB / 272376 bytes)"
  desktop <## "use /fr 1 [<dir>/ | <path>] to receive it"
  desktop ##> "/fr 1"
  concurrentlyN_
    [ do
        bob <## "completed uploading file 1 (test.pdf) for alice",
      do
        desktop <## "saving file 1 from bob to test.pdf"
        desktop <## "started receiving file 1 (test.pdf) from bob"
        desktop <## "completed receiving file 1 (test.pdf) from bob"
    ]

  desktop <## "File received to connected remote host 1"
  desktop <## "To download to this device use:"
  getCmd <- getTermLine desktop
  src <- B.readFile "tests/fixtures/test.pdf"
  B.readFile (mobileFiles </> "test.pdf") `shouldReturn` src
  doesFileExist (desktopHostStore </> "test.pdf") `shouldReturn` False
  desktop ##> getCmd
  desktop <## "ok"
  B.readFile (desktopHostStore </> "test.pdf") `shouldReturn` src

  desktop `send` "/f @bob tests/fixtures/test.jpg"
  desktop <# "/f @bob test.jpg"
  desktop <## "use /fc 2 to cancel sending"

  bob <# "alice> sends file test.jpg (136.5 KiB / 139737 bytes)"
  bob <## "use /fr 2 [<dir>/ | <path>] to receive it"
  bob ##> ("/fr 2 " <> bobFiles)
  concurrentlyN_
    [ do
        desktop <## "completed uploading file 2 (test.jpg) for bob",
      do
        bob <## "saving file 2 from alice to ./tests/tmp/bob_files/test.jpg"
        bob <## "started receiving file 2 (test.jpg) from alice"
        bob <## "completed receiving file 2 (test.jpg) from alice"
    ]

  src' <- B.readFile "tests/fixtures/test.jpg"
  B.readFile (mobileFiles </> "test.jpg") `shouldReturn` src'
  B.readFile (desktopHostStore </> "test.jpg") `shouldReturn` src'
  B.readFile (bobFiles </> "test.jpg") `shouldReturn` src'

  stopMobile mobile desktop
  where
    cfg = testCfg {xftpFileConfig = Just $ XFTPFileConfig {minFileSize = 0}, tempDir = Just "./tests/tmp/tmp"}

-- * Utils

startRemote :: TestCC -> TestCC -> IO ()
startRemote mobile desktop = do
  desktop ##> "/create remote host"
  desktop <## "remote host 1 created"
  desktop <## "connection code:"
  fingerprint <- getTermLine desktop

  desktop ##> "/start remote host 1"
  desktop <## "ok"

  mobile ##> "/start remote ctrl"
  mobile <## "ok"
  mobile <## "remote controller announced"
  mobile <## "connection code:"
  fingerprint' <- getTermLine mobile
  fingerprint' `shouldBe` fingerprint
  mobile ##> ("/register remote ctrl " <> fingerprint' <> " " <> "My desktop")
  mobile <## "remote controller 1 registered"
  mobile ##> "/accept remote ctrl 1"
  mobile <## "ok" -- alternative scenario: accepted before controller start
  mobile <## "remote controller 1 connecting to My desktop"
  mobile <## "remote controller 1 connected, My desktop"
  desktop <## "remote host 1 connected"

contactBob :: TestCC -> TestCC -> IO ()
contactBob desktop bob = do
  logNote "exchanging contacts"
  bob ##> "/c"
  inv' <- getInvitation bob
  desktop ##> ("/c " <> inv')
  desktop <## "confirmation sent!"
  concurrently_
    (desktop <## "bob (Bob): contact is connected")
    (bob <## "alice (Alice): contact is connected")

genTestCredentials :: IO (C.KeyHash, TLS.Credentials)
genTestCredentials = do
  caCreds <- liftIO $ genCredentials Nothing (0, 24) "CA"
  sessionCreds <- liftIO $ genCredentials (Just caCreds) (0, 24) "Session"
  pure . tlsCredentials $ sessionCreds :| [caCreds]

stopDesktop :: HasCallStack => TestCC -> TestCC -> IO ()
stopDesktop mobile desktop = do
  logWarn "stopping via desktop"
  desktop ##> "/stop remote host 1"
  -- desktop <## "ok"
  concurrently_
    (desktop <## "remote host 1 stopped")
    (eventually 3 $ mobile <## "remote controller stopped")

stopMobile :: HasCallStack => TestCC -> TestCC -> IO ()
stopMobile mobile desktop = do
  logWarn "stopping via mobile"
  mobile ##> "/stop remote ctrl"
  mobile <## "ok"
  concurrently_
    (mobile <## "remote controller stopped")
    (eventually 3 $ desktop <## "remote host 1 stopped")

-- | Run action with extended timeout
eventually :: Int -> IO a -> IO a
eventually retries action = tryAny action >>= \case -- TODO: only catch timeouts
  Left err | retries == 0 -> throwIO err
  Left _ -> eventually (retries - 1) action
  Right r -> pure r
