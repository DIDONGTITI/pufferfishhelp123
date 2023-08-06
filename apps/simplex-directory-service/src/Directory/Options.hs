{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Directory.Options
 ( DirectoryOpts (..),
   getDirectoryOpts,
   mkChatOpts,
 )
where

import Options.Applicative
import Simplex.Chat.Bot.KnownContacts
import Simplex.Chat.Controller (updateStr, versionNumber, versionString)
import Simplex.Chat.Options (ChatOpts (..), CoreChatOpts, coreChatOptsP)

data DirectoryOpts = DirectoryOpts
  { coreOptions :: CoreChatOpts,
    superUsers :: [KnownContact],
    directoryLog :: Maybe FilePath,
    serviceName :: String
  }

directoryOpts :: FilePath -> FilePath -> Parser DirectoryOpts
directoryOpts appDir defaultDbFileName = do
  coreOptions <- coreChatOptsP appDir defaultDbFileName
  superUsers <-
    option
      parseKnownContacts
      ( long "super-users"
          <> metavar "SUPER_USERS"
          <> help "Comma-separated list of super-users in the format CONTACT_ID:DISPLAY_NAME who will be allowed to manage the directory"
          <> value []
      )
  directoryLog <-
    optional $
      strOption
        ( long "directory-file"
            <> metavar "DIRECTORY_FILE"
            <> help "Append only log for directory state"
        )
  serviceName <-
    strOption
      ( long "service-name"
          <> metavar "SERVICE_NAME"
          <> help "The display name of the directory service bot, without *'s and spaces (SimpleX-Directory)"
          <> value "SimpleX-Directory"
      )
  pure
    DirectoryOpts
      { coreOptions,
        superUsers,
        directoryLog,
        serviceName
      }

getDirectoryOpts :: FilePath -> FilePath -> IO DirectoryOpts
getDirectoryOpts appDir defaultDbFileName =
  execParser $
    info
      (helper <*> versionOption <*> directoryOpts appDir defaultDbFileName)
      (header versionStr <> fullDesc <> progDesc "Start SimpleX Directory Service with DB_FILE, DIRECTORY_FILE and SUPER_USERS options")
  where
    versionStr = versionString versionNumber
    versionOption = infoOption versionAndUpdate (long "version" <> short 'v' <> help "Show version")
    versionAndUpdate = versionStr <> "\n" <> updateStr

mkChatOpts :: DirectoryOpts -> ChatOpts
mkChatOpts DirectoryOpts {coreOptions} =
  ChatOpts
    { coreOptions,
      chatCmd = "",
      chatCmdDelay = 3,
      chatServerPort = Nothing,
      optFilesFolder = Nothing,
      showReactions = False,
      allowInstantFiles = True,
      autoAcceptFileSize = 0,
      muteNotifications = True,
      maintenance = False
    }
