{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Simplex.Chat.Archive
  ( exportArchive,
    importArchive,
    deleteStorage,
    sqlCipherExport,
  )
where

import qualified Codec.Archive.Zip as Z
import Control.Monad.Except
import Control.Monad.Reader
import qualified Data.Text as T
import qualified Database.SQLite3 as SQL
import Simplex.Chat.Controller
import Simplex.Messaging.Agent.Client (agentStore)
import Simplex.Messaging.Agent.Store.SQLite (SQLiteStore (..), sqlString)
import Simplex.Messaging.Util (unlessM, whenM)
import System.FilePath
import UnliftIO.Directory
import UnliftIO.Exception (SomeException, bracket, catch)
import UnliftIO.STM
import UnliftIO.Temporary

archiveAgentDbFile :: String
archiveAgentDbFile = "simplex_v1_agent.db"

archiveChatDbFile :: String
archiveChatDbFile = "simplex_v1_chat.db"

archiveFilesFolder :: String
archiveFilesFolder = "simplex_v1_files"

exportArchive :: ChatMonad m => ArchiveConfig -> m ()
exportArchive cfg@ArchiveConfig {archivePath, disableCompression} =
  withTempDir cfg "simplex-chat." $ \dir -> do
    StorageFiles {chatDb, agentDb, filesPath} <- storageFiles
    copyFile chatDb $ dir </> archiveChatDbFile
    copyFile agentDb $ dir </> archiveAgentDbFile
    forM_ filesPath $ \fp ->
      copyDirectoryFiles fp $ dir </> archiveFilesFolder
    let method = if disableCompression == Just True then Z.Store else Z.Deflate
    Z.createArchive archivePath $ Z.packDirRecur method Z.mkEntrySelector dir

importArchive :: ChatMonad m => ArchiveConfig -> m ()
importArchive cfg@ArchiveConfig {archivePath} =
  withTempDir cfg "simplex-chat." $ \dir -> do
    Z.withArchive archivePath $ Z.unpackInto dir
    StorageFiles {chatDb, agentDb, filesPath} <- storageFiles
    backup chatDb
    backup agentDb
    copyFile (dir </> archiveChatDbFile) chatDb
    copyFile (dir </> archiveAgentDbFile) agentDb
    let filesDir = dir </> archiveFilesFolder
    forM_ filesPath $ \fp ->
      whenM (doesDirectoryExist filesDir) $
        copyDirectoryFiles filesDir fp
  where
    backup f = whenM (doesFileExist f) $ copyFile f $ f <> ".bak"

withTempDir :: ChatMonad m => ArchiveConfig -> (String -> (FilePath -> m ()) -> m ())
withTempDir cfg = case parentTempDirectory cfg of
  Just tmpDir -> withTempDirectory tmpDir
  _ -> withSystemTempDirectory

copyDirectoryFiles :: MonadIO m => FilePath -> FilePath -> m ()
copyDirectoryFiles fromDir toDir = do
  createDirectoryIfMissing False toDir
  fs <- listDirectory fromDir
  forM_ fs $ \f -> do
    let fn = takeFileName f
        f' = fromDir </> fn
    whenM (doesFileExist f') $ copyFile f' $ toDir </> fn

deleteStorage :: ChatMonad m => m ()
deleteStorage = do
  StorageFiles {chatDb, agentDb, filesPath} <- storageFiles
  removeFile chatDb
  removeFile agentDb
  mapM_ removePathForcibly filesPath

data StorageFiles = StorageFiles
  { chatDb :: FilePath,
    chatEncrypted :: TVar Bool,
    agentDb :: FilePath,
    agentEncrypted :: TVar Bool,
    filesPath :: Maybe FilePath
  }

storageFiles :: ChatMonad m => m StorageFiles
storageFiles = do
  ChatController {chatStore, filesFolder, smpAgent} <- ask
  let SQLiteStore {dbFilePath = chatDb, dbEncrypted = chatEncrypted} = chatStore
      SQLiteStore {dbFilePath = agentDb, dbEncrypted = agentEncrypted} = agentStore smpAgent
  filesPath <- readTVarIO filesFolder
  pure StorageFiles {chatDb, chatEncrypted, agentDb, agentEncrypted, filesPath}

sqlCipherExport :: forall m. ChatMonad m => DBEncryptionConfig -> m ()
sqlCipherExport DBEncryptionConfig {currentKey = DBEncryptionKey key, newKey = DBEncryptionKey key'} =
  when (key /= key') $ do
    fs@StorageFiles {chatDb, chatEncrypted, agentDb, agentEncrypted} <- storageFiles
    checkFile `with` fs
    backup `with` fs
    (export chatDb chatEncrypted >> export agentDb agentEncrypted)
      `catchError` \e -> (restore `with` fs) >> throwError e
  where
    action `with` StorageFiles {chatDb, agentDb} = action chatDb >> action agentDb
    backup f = copyFile f (f <> ".bak")
    restore f = copyFile (f <> ".bak") f
    checkFile f = unlessM (doesFileExist f) $ throwDBError $ DBErrorNoFile f
    export f dbEnc = do
      enc <- readTVarIO dbEnc
      when (enc && null key) $ throwDBError DBErrorEncrypted
      when (not enc && not (null key)) $ throwDBError DBErrorPlaintext
      withDB (`SQL.exec` exportSQL) DBErrorExport
      renameFile (f <> ".exported") f
      withDB (`SQL.exec` testSQL) DBErrorOpen
      atomically $ writeTVar dbEnc $ not (null key')
      where
        withDB a err =
          liftIO (bracket (SQL.open $ T.pack f) SQL.close a)
            `catch` (\(e :: SQL.SQLError) -> log' e >> checkSQLError e)
            `catch` (\(e :: SomeException) -> log' e >> throwSQLError e)
          where
            log' e = liftIO . putStrLn $ "Database error: " <> show e
            checkSQLError e = case SQL.sqlError e of
              SQL.ErrorNotADatabase -> throwDBError $ err SQLiteErrorNotADatabase
              _ -> throwSQLError e
            throwSQLError :: Show e => e -> m ()
            throwSQLError = throwDBError . err . SQLiteError . show
        exportSQL =
          T.unlines $
            keySQL key
              <> [ "ATTACH DATABASE " <> sqlString (f <> ".exported") <> " AS exported KEY " <> sqlString key' <> ";",
                   "SELECT sqlcipher_export('exported');",
                   "DETACH DATABASE exported;"
                 ]
        testSQL =
          T.unlines $
            keySQL key'
              <> [ "PRAGMA foreign_keys = ON;",
                   "PRAGMA secure_delete = ON;",
                   "PRAGMA auto_vacuum = FULL;",
                   "SELECT count(*) FROM sqlite_master;"
                 ]
        keySQL k = ["PRAGMA key = " <> sqlString k <> ";" | not (null k)]
