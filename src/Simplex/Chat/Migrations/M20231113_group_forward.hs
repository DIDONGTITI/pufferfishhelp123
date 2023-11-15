{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20231113_group_forward where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20231113_group_forward :: Query
m20231113_group_forward =
  [sql|
ALTER TABLE group_member_intros ADD COLUMN xgrpmemcon_supported INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_group_member_intros_re_group_member_id ON group_member_intros(re_group_member_id);

ALTER TABLE group_members ADD COLUMN invited_by_group_member_id INTEGER REFERENCES group_members ON DELETE SET NULL;
CREATE INDEX idx_group_members_invited_by_group_member_id ON group_members(invited_by_group_member_id);
|]

down_m20231113_group_forward :: Query
down_m20231113_group_forward =
  [sql|
DROP INDEX idx_group_members_invited_by_group_member_id;
ALTER TABLE group_members DROP COLUMN invited_by_group_member_id;

DROP INDEX idx_group_member_intros_re_group_member_id;
ALTER TABLE group_member_intros DROP COLUMN xgrpmemcon_supported;
|]
