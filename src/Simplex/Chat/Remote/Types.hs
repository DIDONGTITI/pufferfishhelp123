{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Simplex.Chat.Remote.Types where

import Control.Concurrent.Async (Async)
import Control.Exception (Exception)
import qualified Data.Aeson.TH as J
import Data.Int (Int64)
import Data.Text (Text)
import Simplex.Chat.Remote.AppVersion
import Simplex.Messaging.Parsers (defaultJSON, dropPrefix, enumJSON, sumTypeJSON)
import Simplex.Messaging.Transport.HTTP2.Client (HTTP2Client)
import Simplex.RemoteControl.Client
import Simplex.RemoteControl.Types
import Simplex.Messaging.Crypto.File (CryptoFile)

data RemoteHostClient = RemoteHostClient
  { hostEncoding :: PlatformEncoding,
    hostDeviceName :: Text,
    httpClient :: HTTP2Client,
    sessionKeys :: HostSessKeys,
    encryptHostFiles :: Bool,
    storePath :: FilePath
  }

data RHPendingSession = RHPendingSession
  { rhKey :: RHKey,
    rchClient :: RCHostClient,
    rhsWaitSession :: Async (),
    remoteHost_ :: Maybe RemoteHostInfo
  }

data RemoteHostSession
  = RHSessionStarting
  | RHSessionConnecting {rhPendingSession :: RHPendingSession}
  | RHSessionConfirmed {rhPendingSession :: RHPendingSession}
  | RHSessionConnected {rhClient :: RemoteHostClient, pollAction :: Async (), storePath :: FilePath}

data RemoteProtocolError
  = -- | size prefix is malformed
    RPEInvalidSize
  | -- | failed to parse RemoteCommand or RemoteResponse
    RPEInvalidJSON {invalidJSON :: String}
  | RPEIncompatibleEncoding
  | RPEUnexpectedFile
  | RPENoFile
  | RPEFileSize
  | RPEFileDigest
  | -- | Wrong response received for the command sent
    RPEUnexpectedResponse {response :: Text}
  | -- | A file already exists in the destination position
    RPEStoredFileExists
  | RPEHTTP2 {http2Error :: Text}
  | RPEException {someException :: Text}
  deriving (Show, Exception)

type RemoteHostId = Int64

data RHKey = RHNew | RHId {remoteHostId :: RemoteHostId}
  deriving (Eq, Ord, Show)

-- | Storable/internal remote host data
data RemoteHost = RemoteHost
  { remoteHostId :: RemoteHostId,
    hostName :: Text,
    storePath :: FilePath,
    hostPairing :: RCHostPairing
  }

-- | UI-accessible remote host information
data RemoteHostInfo = RemoteHostInfo
  { remoteHostId :: RemoteHostId,
    hostName :: Text,
    storePath :: FilePath,
    sessionActive :: Bool
  }
  deriving (Show)

type RemoteCtrlId = Int64

-- | Storable/internal remote controller data
data RemoteCtrl = RemoteCtrl
  { remoteCtrlId :: RemoteCtrlId,
    ctrlName :: Text,
    ctrlPairing :: RCCtrlPairing
  }

-- | UI-accessible remote controller information
data RemoteCtrlInfo = RemoteCtrlInfo
  { remoteCtrlId :: RemoteCtrlId,
    ctrlName :: Text,
    sessionActive :: Bool
  }
  deriving (Show)

data PlatformEncoding
  = PESwift
  | PEKotlin
  deriving (Show, Eq)

localEncoding :: PlatformEncoding
#if defined(darwin_HOST_OS) && defined(swiftJSON)
localEncoding = PESwift
#else
localEncoding = PEKotlin
#endif

data RemoteFile = RemoteFile
  { userId :: Int64,
    fileId :: Int64,
    sent :: Bool,
    fileSource :: CryptoFile
  }
  deriving (Show)

data CtrlAppInfo = CtrlAppInfo
  { appVersionRange :: AppVersionRange,
    deviceName :: Text
  }

data HostAppInfo = HostAppInfo
  { appVersion :: AppVersion,
    deviceName :: Text,
    encoding :: PlatformEncoding,
    encryptFiles :: Bool -- if the host encrypts files in app storage
  }

$(J.deriveJSON defaultJSON ''RemoteFile)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "RPE") ''RemoteProtocolError)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "RH") ''RHKey)

$(J.deriveJSON (enumJSON $ dropPrefix "PE") ''PlatformEncoding)

$(J.deriveJSON defaultJSON ''RemoteHostInfo)

$(J.deriveJSON defaultJSON ''RemoteCtrlInfo)

$(J.deriveJSON defaultJSON ''CtrlAppInfo)

$(J.deriveJSON defaultJSON ''HostAppInfo)
