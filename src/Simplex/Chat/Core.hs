{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module Simplex.Chat.Core where

import Control.Logger.Simple
import Control.Monad.Reader
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Simplex.Chat
import Simplex.Chat.Controller
import Simplex.Chat.Options (ChatOpts (..))
import Simplex.Chat.Store
import Simplex.Chat.Types
import UnliftIO.Async

simplexChatCore :: ChatConfig -> ChatOpts -> Maybe (Notification -> IO ()) -> (User -> ChatController -> IO ()) -> IO ()
simplexChatCore cfg@ChatConfig {dbPoolSize, yesToMigrations} opts sendToast chat
  | logAgent opts = do
    setLogLevel LogInfo -- LogError
    withGlobalLogging logCfg initRun
  | otherwise = initRun
  where
    initRun = do
      let f = chatStoreFile $ dbFilePrefix opts
      st <- createStore f dbPoolSize yesToMigrations
      u <- getCreateActiveUser st
      cc <- newChatController st (Just u) cfg opts $ fromMaybe (const $ pure ()) sendToast
      runSimplexChat u cc chat

runSimplexChat :: User -> ChatController -> (User -> ChatController -> IO ()) -> IO ()
runSimplexChat u cc chat = do
  a1 <- async $ chat u cc
  a2 <- runReaderT (startChatController u) cc
  waitEither_ a1 a2

sendChatCmd :: ChatController -> String -> IO ChatResponse
sendChatCmd cc s = runReaderT (execChatCommand . encodeUtf8 $ T.pack s) cc
