{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20230317_hidden_profiles where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20230317_hidden_profiles :: Query
m20230317_hidden_profiles =
  [sql|
ALTER TABLE users ADD COLUMN view_pwd_hash BLOB;
ALTER TABLE users ADD COLUMN view_pwd_salt BLOB;
ALTER TABLE users ADD COLUMN show_ntfs INTEGER NOT NULL DEFAULT 1;
|]
