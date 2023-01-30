{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

module ChatClient where

import Control.Concurrent (forkIOWithUnmask, killThread, threadDelay)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Exception (bracket, bracket_)
import Control.Monad.Except
import Data.Functor (($>))
import Data.List (dropWhileEnd, find)
import Data.Maybe (fromJust, isNothing)
import qualified Data.Text as T
import Network.Socket
import Simplex.Chat
import Simplex.Chat.Controller (ChatConfig (..), ChatController (..), ChatDatabase (..), ChatLogLevel (..))
import Simplex.Chat.Core
import Simplex.Chat.Options
import Simplex.Chat.Store
import Simplex.Chat.Terminal
import Simplex.Chat.Terminal.Output (newChatTerminal)
import Simplex.Chat.Types (AgentUserId (..), Profile, User (..))
import Simplex.Messaging.Agent.Env.SQLite
import Simplex.Messaging.Agent.RetryInterval
import Simplex.Messaging.Client (ProtocolClientConfig (..), defaultNetworkConfig)
import Simplex.Messaging.Server (runSMPServerBlocking)
import Simplex.Messaging.Server.Env.STM
import Simplex.Messaging.Transport
import Simplex.Messaging.Version
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)
import qualified System.Terminal as C
import System.Terminal.Internal (VirtualTerminal (..), VirtualTerminalSettings (..), withVirtualTerminal)
import System.Timeout (timeout)
import Test.Hspec (Expectation, HasCallStack, shouldReturn)

testDBPrefix :: FilePath
testDBPrefix = "tests/tmp/test"

serverPort :: ServiceName
serverPort = "7001"

testOpts :: ChatOpts
testOpts =
  ChatOpts
    { dbFilePrefix = undefined,
      dbKey = "",
      -- dbKey = "this is a pass-phrase to encrypt the database",
      smpServers = ["smp://LcJUMfVhwD8yxjAiSaDzzGF3-kLG4Uh0Fl_ZIjrRwjI=:server_password@localhost:7001"],
      networkConfig = defaultNetworkConfig,
      logLevel = CLLImportant,
      logConnections = False,
      logServerHosts = False,
      logAgent = False,
      tbqSize = 64,
      chatCmd = "",
      chatCmdDelay = 3,
      chatServerPort = Nothing,
      optFilesFolder = Nothing,
      allowInstantFiles = True,
      maintenance = False
    }

termSettings :: VirtualTerminalSettings
termSettings =
  VirtualTerminalSettings
    { virtualType = "xterm",
      virtualWindowSize = pure C.Size {height = 24, width = 1000},
      virtualEvent = retry,
      virtualInterrupt = retry
    }

data TestCC = TestCC
  { chatController :: ChatController,
    virtualTerminal :: VirtualTerminal,
    chatAsync :: Async (),
    termAsync :: Async (),
    termQ :: TQueue String
  }

aCfg :: AgentConfig
aCfg = agentConfig defaultChatConfig

testAgentCfg :: AgentConfig
testAgentCfg = aCfg {reconnectInterval = (reconnectInterval aCfg) {initialInterval = 50000}}

testCfg :: ChatConfig
testCfg =
  defaultChatConfig
    { agentConfig = testAgentCfg,
      testView = True
    }

testAgentCfgV1 :: AgentConfig
testAgentCfgV1 =
  testAgentCfg
    { smpClientVRange = mkVersionRange 1 1,
      smpAgentVRange = mkVersionRange 1 1,
      smpCfg = (smpCfg testAgentCfg) {smpServerVRange = mkVersionRange 1 1}
    }

testCfgV1 :: ChatConfig
testCfgV1 = testCfg {agentConfig = testAgentCfgV1}

createTestChat :: ChatConfig -> ChatOpts -> String -> Profile -> IO TestCC
createTestChat cfg opts@ChatOpts {dbKey} dbPrefix profile = do
  db@ChatDatabase {chatStore} <- createChatDatabase (testDBPrefix <> dbPrefix) dbKey False
  Right user <- withTransaction chatStore $ \db' -> runExceptT $ createUserRecord db' (AgentUserId 1) profile True
  startTestChat_ db cfg opts user

startTestChat :: ChatConfig -> ChatOpts -> String -> IO TestCC
startTestChat cfg opts@ChatOpts {dbKey} dbPrefix = do
  db@ChatDatabase {chatStore} <- createChatDatabase (testDBPrefix <> dbPrefix) dbKey False
  Just user <- find activeUser <$> withTransaction chatStore getUsers
  startTestChat_ db cfg opts user

startTestChat_ :: ChatDatabase -> ChatConfig -> ChatOpts -> User -> IO TestCC
startTestChat_ db cfg opts user = do
  t <- withVirtualTerminal termSettings pure
  ct <- newChatTerminal t
  cc <- newChatController db (Just user) cfg opts Nothing -- no notifications
  chatAsync <- async . runSimplexChat opts user cc . const $ runChatTerminal ct
  atomically . unless (maintenance opts) $ readTVar (agentAsync cc) >>= \a -> when (isNothing a) retry
  termQ <- newTQueueIO
  termAsync <- async $ readTerminalOutput t termQ
  pure TestCC {chatController = cc, virtualTerminal = t, chatAsync, termAsync, termQ}

stopTestChat :: TestCC -> IO ()
stopTestChat TestCC {chatController = cc, chatAsync, termAsync} = do
  stopChatController cc
  uninterruptibleCancel termAsync
  uninterruptibleCancel chatAsync
  threadDelay 200000

withNewTestChat :: HasCallStack => String -> Profile -> (HasCallStack => TestCC -> IO a) -> IO a
withNewTestChat = withNewTestChatCfgOpts testCfg testOpts

withNewTestChatV1 :: HasCallStack => String -> Profile -> (HasCallStack => TestCC -> IO a) -> IO a
withNewTestChatV1 = withNewTestChatCfg testCfgV1

withNewTestChatCfg :: HasCallStack => ChatConfig -> String -> Profile -> (HasCallStack => TestCC -> IO a) -> IO a
withNewTestChatCfg cfg = withNewTestChatCfgOpts cfg testOpts

withNewTestChatOpts :: HasCallStack => ChatOpts -> String -> Profile -> (HasCallStack => TestCC -> IO a) -> IO a
withNewTestChatOpts = withNewTestChatCfgOpts testCfg

withNewTestChatCfgOpts :: HasCallStack => ChatConfig -> ChatOpts -> String -> Profile -> (HasCallStack => TestCC -> IO a) -> IO a
withNewTestChatCfgOpts cfg opts dbPrefix profile runTest =
  bracket
    (createTestChat cfg opts dbPrefix profile)
    stopTestChat
    (\cc -> runTest cc >>= ((cc <// 100000) $>))

withTestChatV1 :: HasCallStack => String -> (HasCallStack => TestCC -> IO a) -> IO a
withTestChatV1 = withTestChatCfg testCfgV1

withTestChat :: HasCallStack => String -> (HasCallStack => TestCC -> IO a) -> IO a
withTestChat = withTestChatCfgOpts testCfg testOpts

withTestChatCfg :: HasCallStack => ChatConfig -> String -> (HasCallStack => TestCC -> IO a) -> IO a
withTestChatCfg cfg = withTestChatCfgOpts cfg testOpts

withTestChatOpts :: HasCallStack => ChatOpts -> String -> (HasCallStack => TestCC -> IO a) -> IO a
withTestChatOpts = withTestChatCfgOpts testCfg

withTestChatCfgOpts :: HasCallStack => ChatConfig -> ChatOpts -> String -> (HasCallStack => TestCC -> IO a) -> IO a
withTestChatCfgOpts cfg opts dbPrefix = bracket (startTestChat cfg opts dbPrefix) (\cc -> cc <// 100000 >> stopTestChat cc)

readTerminalOutput :: VirtualTerminal -> TQueue String -> IO ()
readTerminalOutput t termQ = do
  let w = virtualWindow t
  winVar <- atomically $ newTVar . init =<< readTVar w
  forever . atomically $ do
    win <- readTVar winVar
    win' <- init <$> readTVar w
    if win' == win
      then retry
      else do
        let diff = getDiff win' win
        forM_ diff $ writeTQueue termQ
        writeTVar winVar win'
  where
    getDiff :: [String] -> [String] -> [String]
    getDiff win win' = getDiff_ 1 (length win) win win'
    getDiff_ :: Int -> Int -> [String] -> [String] -> [String]
    getDiff_ n len win' win =
      let diff = drop (len - n) win'
       in if drop n win <> diff == win'
            then map (dropWhileEnd (== ' ')) diff
            else getDiff_ (n + 1) len win' win

withTmpFiles :: IO () -> IO ()
withTmpFiles =
  bracket_
    (createDirectoryIfMissing False "tests/tmp")
    (removeDirectoryRecursive "tests/tmp")

testChatN :: HasCallStack => ChatConfig -> ChatOpts -> [Profile] -> (HasCallStack => [TestCC] -> IO ()) -> IO ()
testChatN cfg opts ps test = do
  tcs <- getTestCCs (zip ps [1 ..]) []
  test tcs
  concurrentlyN_ $ map (<// 100000) tcs
  concurrentlyN_ $ map stopTestChat tcs
  where
    getTestCCs :: [(Profile, Int)] -> [TestCC] -> IO [TestCC]
    getTestCCs [] tcs = pure tcs
    getTestCCs ((p, db) : envs') tcs = (:) <$> createTestChat cfg opts (show db) p <*> getTestCCs envs' tcs

(<//) :: HasCallStack => TestCC -> Int -> Expectation
(<//) cc t = timeout t (getTermLine cc) `shouldReturn` Nothing

getTermLine :: HasCallStack => TestCC -> IO String
getTermLine cc =
  5000000 `timeout` atomically (readTQueue $ termQ cc) >>= \case
    Just s -> do
      -- uncomment 2 lines below to echo virtual terminal
      -- name <- userName cc
      -- putStrLn $ name <> ": " <> s
      pure s
    _ -> error "no output for 5 seconds"

userName :: TestCC -> IO [Char]
userName (TestCC ChatController {currentUser} _ _ _ _) = T.unpack . localDisplayName . fromJust <$> readTVarIO currentUser

testChat2 :: Profile -> Profile -> (TestCC -> TestCC -> IO ()) -> IO ()
testChat2 = testChatCfgOpts2 testCfg testOpts

testChatCfg2 :: ChatConfig -> Profile -> Profile -> (TestCC -> TestCC -> IO ()) -> IO ()
testChatCfg2 cfg = testChatCfgOpts2 cfg testOpts

testChatOpts2 :: ChatOpts -> Profile -> Profile -> (TestCC -> TestCC -> IO ()) -> IO ()
testChatOpts2 = testChatCfgOpts2 testCfg

testChatCfgOpts2 :: ChatConfig -> ChatOpts -> Profile -> Profile -> (TestCC -> TestCC -> IO ()) -> IO ()
testChatCfgOpts2 cfg opts p1 p2 test = testChatN cfg opts [p1, p2] test_
  where
    test_ :: [TestCC] -> IO ()
    test_ [tc1, tc2] = test tc1 tc2
    test_ _ = error "expected 2 chat clients"

testChat3 :: Profile -> Profile -> Profile -> (TestCC -> TestCC -> TestCC -> IO ()) -> IO ()
testChat3 = testChatCfgOpts3 testCfg testOpts

testChatCfg3 :: ChatConfig -> Profile -> Profile -> Profile -> (TestCC -> TestCC -> TestCC -> IO ()) -> IO ()
testChatCfg3 cfg = testChatCfgOpts3 cfg testOpts

testChatCfgOpts3 :: ChatConfig -> ChatOpts -> Profile -> Profile -> Profile -> (TestCC -> TestCC -> TestCC -> IO ()) -> IO ()
testChatCfgOpts3 cfg opts p1 p2 p3 test = testChatN cfg opts [p1, p2, p3] test_
  where
    test_ :: [TestCC] -> IO ()
    test_ [tc1, tc2, tc3] = test tc1 tc2 tc3
    test_ _ = error "expected 3 chat clients"

testChat4 :: Profile -> Profile -> Profile -> Profile -> (TestCC -> TestCC -> TestCC -> TestCC -> IO ()) -> IO ()
testChat4 p1 p2 p3 p4 test = testChatN testCfg testOpts [p1, p2, p3, p4] test_
  where
    test_ :: [TestCC] -> IO ()
    test_ [tc1, tc2, tc3, tc4] = test tc1 tc2 tc3 tc4
    test_ _ = error "expected 4 chat clients"

concurrentlyN_ :: [IO a] -> IO ()
concurrentlyN_ = mapConcurrently_ id

serverCfg :: ServerConfig
serverCfg =
  ServerConfig
    { transports = [(serverPort, transport @TLS)],
      tbqSize = 1,
      serverTbqSize = 1,
      msgQueueQuota = 16,
      queueIdBytes = 12,
      msgIdBytes = 6,
      storeLogFile = Nothing,
      storeMsgsFile = Nothing,
      allowNewQueues = True,
      -- server password is disabled as otherwise v1 tests fail
      newQueueBasicAuth = Nothing, -- Just "server_password",
      messageExpiration = Just defaultMessageExpiration,
      inactiveClientExpiration = Just defaultInactiveClientExpiration,
      caCertificateFile = "tests/fixtures/tls/ca.crt",
      privateKeyFile = "tests/fixtures/tls/server.key",
      certificateFile = "tests/fixtures/tls/server.crt",
      logStatsInterval = Nothing,
      logStatsStartTime = 0,
      serverStatsLogFile = "tests/smp-server-stats.daily.log",
      serverStatsBackupFile = Nothing,
      smpServerVRange = supportedSMPServerVRange,
      logTLSErrors = True
    }

withSmpServer :: IO () -> IO ()
withSmpServer = serverBracket (`runSMPServerBlocking` serverCfg)

serverBracket :: (TMVar Bool -> IO ()) -> IO () -> IO ()
serverBracket server f = do
  started <- newEmptyTMVarIO
  bracket
    (forkIOWithUnmask ($ server started))
    (\t -> killThread t >> waitFor started "stop")
    (\_ -> waitFor started "start" >> f)
  where
    waitFor started s =
      5000000 `timeout` atomically (takeTMVar started) >>= \case
        Nothing -> error $ "server did not " <> s
        _ -> pure ()
