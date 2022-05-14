{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20220514_profiles_user_id where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220514_profiles_user_id :: Query
m20220514_profiles_user_id =
  [sql|
ALTER TABLE contact_profiles ADD COLUMN user_id INTEGER DEFAULT NULL REFERENCES users ON DELETE CASCADE;
UPDATE contact_profiles SET user_id = 1;

ALTER TABLE group_profiles ADD COLUMN user_id INTEGER DEFAULT NULL REFERENCES users ON DELETE CASCADE;
UPDATE group_profiles SET user_id = 1;
|]
