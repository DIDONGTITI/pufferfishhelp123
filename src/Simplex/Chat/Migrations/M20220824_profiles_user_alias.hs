{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20220824_profiles_user_alias where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220824_profiles_user_alias :: Query
m20220824_profiles_user_alias =
  [sql|
PRAGMA ignore_check_constraints=ON;

ALTER TABLE contact_profiles ADD COLUMN user_alias TEXT DEFAULT '' CHECK (user_alias NOT NULL);
UPDATE contact_profiles SET user_alias = '';

PRAGMA ignore_check_constraints=OFF;
|]
