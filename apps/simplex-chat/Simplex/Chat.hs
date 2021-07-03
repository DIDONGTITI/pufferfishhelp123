{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Simplex.Chat where

import Control.Applicative (optional, (<|>))
import Control.Monad.Except
import Control.Monad.IO.Unlift
import Control.Monad.Reader
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.Bifunctor (first)
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Functor (($>))
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Simplex.Chat.Controller
import Simplex.Chat.Protocol
import Simplex.Chat.Styled (plain)
import Simplex.Chat.Types
import Simplex.Help
import Simplex.Messaging.Agent
import Simplex.Messaging.Agent.Protocol
import Simplex.Messaging.Parsers (parseAll)
import Simplex.Messaging.Util (bshow, raceAny_)
import Simplex.Notification
import Simplex.Store
import Simplex.Terminal
import Simplex.View
import qualified UnliftIO.Exception as E
import UnliftIO.STM

data ChatCommand
  = ChatHelp
  | MarkdownHelp
  | AddContact (Maybe ContactRef)
  | Connect (Maybe ContactRef) SMPQueueInfo
  | DeleteContact ContactRef
  | SendMessage ContactRef ByteString
  deriving (Show)

runChatController :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
runChatController =
  raceAny_
    [ inputSubscriber,
      agentSubscriber,
      chatSubscriber,
      notificationSubscriber
    ]

inputSubscriber :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
inputSubscriber = do
  q <- asks inputQ
  forever $
    atomically (readTBQueue q) >>= \case
      InputControl _ -> pure ()
      InputCommand s ->
        case parseAll chatCommandP . encodeUtf8 $ T.pack s of
          Left e -> printToView [plain s, "invalid input: " <> plain e]
          Right cmd -> do
            case cmd of
              SendMessage c msg -> showSentMessage c msg
              _ -> printToView [plain s]
            runExceptT (processChatCommand cmd) >>= \case
              Left e -> showChatError e
              _ -> pure ()

processChatCommand :: ChatMonad m => ChatCommand -> m ()
processChatCommand = \case
  ChatHelp -> printToView chatHelpInfo
  MarkdownHelp -> printToView markdownInfo
  AddContact cRef -> do
    (connId, qInfo) <- withAgent (fromMaybe "" cRef) createConnection
    userId <- asks currentUserId
    contact <- withStore $ \st -> createDirectContact st userId connId cRef
    showInvitation (localContactRef contact) qInfo
  Connect cRef qInfo -> do
    userId <- asks currentUserId
    connId <- withAgent (fromMaybe "" cRef) $ \agent -> joinConnection agent qInfo "user profile here"
    void $ withStore $ \st -> createDirectContact st userId connId cRef
  DeleteContact cRef -> do
    userId <- asks currentUserId
    conns <- withStore $ \st -> getContactConnections st userId cRef
    withAgent cRef $ \smp -> forM_ conns $ \Connection {agentConnId} ->
      deleteConnection smp agentConnId `catchError` \(_ :: AgentErrorType) -> pure ()
    void $ withStore $ \st -> deleteContact st userId cRef
    unsetActive $ ActiveC cRef
    when (null conns) . throwError . ChatErrorContact $ CENotFound cRef
    showContactDeleted cRef
  SendMessage cRef msg -> do
    userId <- asks currentUserId
    Connection {agentConnId} <- withStore $ \st -> getContactConnection st userId cRef
    let body = MsgBodyContent {contentType = SimplexContentType XCText, contentHash = Nothing, contentData = MBFull $ MsgData msg}
        rawMsg = rawChatMessage ChatMessage {chatMsgId = Nothing, chatMsgEvent = XMsgNew MTText, chatMsgBody = [body], chatDAGIdx = Nothing}
    void . withAgent cRef $ \smp -> sendMessage smp agentConnId $ serializeRawChatMessage rawMsg
    setActive $ ActiveC cRef

agentSubscriber :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
agentSubscriber = do
  aQ <- asks $ subQ . smpAgent
  cQ <- asks chatQ
  forever $ do
    (_, agentConnId, resp) <- atomically (readTBQueue aQ)
    userId <- asks currentUserId
    runExceptT (withStore $ \st -> getConnectionChatDirection st userId agentConnId) >>= \case
      -- TODO handle errors
      Left e -> liftIO $ print e
      Right chatDirection -> do
        case resp of
          MSG agentMsgMeta msgBody -> do
            atomically . writeTBQueue cQ $
              case first B.pack (parseAll rawChatMessageP msgBody) >>= toChatMessage of
                Right chatMessage -> ChatTransmission {agentMsgMeta, chatDirection, chatMessage}
                Left msgError -> ChatTransmissionError {agentMsgMeta, chatDirection, msgBody, msgError}
          agentMessage ->
            atomically $ writeTBQueue cQ AgentTransmission {agentConnId, chatDirection, agentMessage}

chatSubscriber :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
chatSubscriber = do
  cQ <- asks chatQ
  forever $
    atomically (readTBQueue cQ) >>= \case
      ChatTransmission
        { agentMsgMeta = meta,
          chatDirection = ReceivedDirectMessage Contact {localContactRef = c},
          chatMessage = ChatMessage {chatMsgEvent, chatMsgBody}
        } ->
          case chatMsgEvent of
            XMsgNew MTText -> do
              case find (isSimplexContentType XCText) chatMsgBody of
                Just MsgBodyContent {contentData = MBFull (MsgData bs)} -> do
                  let text = safeDecodeUtf8 bs
                  showReceivedMessage c (snd $ broker meta) text (integrity meta)
                  showToast ("@" <> c) text
                  setActive $ ActiveC c
                _ -> pure ()
            _ -> pure ()
      AgentTransmission {agentConnId, chatDirection = ReceivedDirectMessage Contact {localContactRef = c}, agentMessage} ->
        case agentMessage of
          CONF confId _ ->
            -- TODO save profile? Show confirmation?
            void . runExceptT . withAgent c $ \a -> allowConnection a agentConnId confId "user profile here"
          CON -> do
            showContactConnected c
            showToast ("@" <> c) "connected"
            setActive $ ActiveC c
          END -> do
            showContactDisconnected c
            showToast ("@" <> c) "disconnected"
            unsetActive $ ActiveC c
          _ -> pure ()
      _ -> pure ()

showToast :: (MonadUnliftIO m, MonadReader ChatController m) => Text -> Text -> m ()
showToast title text = atomically . (`writeTBQueue` Notification {title, text}) =<< asks notifyQ

notificationSubscriber :: (MonadUnliftIO m, MonadReader ChatController m) => m ()
notificationSubscriber = do
  ChatController {notifyQ, sendNotification} <- ask
  forever $ atomically (readTBQueue notifyQ) >>= liftIO . sendNotification

withAgent :: ChatMonad m => ContactRef -> (AgentClient -> ExceptT AgentErrorType m a) -> m a
withAgent c action =
  asks smpAgent
    >>= runExceptT . action
    >>= liftEither . first (ChatErrorAgent c)

withStore ::
  ChatMonad m =>
  (forall m'. (MonadUnliftIO m', MonadError StoreError m') => SQLiteStore -> m' a) ->
  m a
withStore action = do
  st <- asks chatStore
  runExceptT (action st `E.catch` handleInternal) >>= \case
    Right c -> pure c
    Left e -> throwError $ storeError e
  where
    -- TODO when parsing exception happens in store, the agent hangs;
    -- changing SQLError to SomeException does not help
    handleInternal :: (MonadError StoreError m') => E.SomeException -> m' a
    handleInternal e = throwError . SEInternal $ bshow e
    storeError :: StoreError -> ChatError
    storeError = \case
      SEContactNotFound c -> ChatErrorContact $ CENotFound c
      e -> ChatErrorStore e

chatCommandP :: Parser ChatCommand
chatCommandP =
  ("/help" <|> "/h") $> ChatHelp
    <|> ("/add" <|> "/a") *> (AddContact <$> optional (A.space *> contactRef))
    <|> ("/connect" <|> "/c") *> ((Connect <$> optional (A.space *> contactRef) <*> qInfo) <|> (Connect Nothing <$> qInfo))
    <|> ("/delete " <|> "/d ") *> (DeleteContact <$> contactRef)
    <|> A.char '@' *> (SendMessage <$> contactRef <*> (A.space *> A.takeByteString))
    <|> ("/markdown" <|> "/m") $> MarkdownHelp
  where
    contactRef = safeDecodeUtf8 <$> A.takeTill (== ' ')
    qInfo = A.space *> smpQueueInfoP
