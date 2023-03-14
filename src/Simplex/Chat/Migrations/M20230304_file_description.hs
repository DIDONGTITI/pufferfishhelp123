{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20230304_file_description where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

-- this table includes file descriptions for the recipients for both sent and received files
-- in the latter case the user is the recipient

m20230304_file_description :: Query
m20230304_file_description =
  [sql|
CREATE TABLE xftp_file_descriptions (
  file_descr_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  file_descr_text TEXT NOT NULL,
  file_descr_part_no INTEGER NOT NULL DEFAULT(0),
  file_descr_complete INTEGER NOT NULL DEFAULT(0),
  created_at TEXT NOT NULL DEFAULT(datetime('now')),
  updated_at TEXT NOT NULL DEFAULT(datetime('now'))
);

ALTER TABLE files ADD COLUMN agent_snd_file_id BLOB NULL;

ALTER TABLE files ADD COLUMN private_snd_file_descr TEXT NULL;

ALTER TABLE snd_files ADD COLUMN file_descr_id INTEGER NULL
  REFERENCES xftp_file_descriptions ON DELETE SET NULL;

CREATE INDEX idx_snd_files_file_descr_id ON snd_files(file_descr_id);

ALTER TABLE rcv_files ADD COLUMN file_descr_id INTEGER NULL
  REFERENCES xftp_file_descriptions ON DELETE SET NULL;

CREATE INDEX idx_rcv_files_file_descr_id ON rcv_files(file_descr_id);

ALTER TABLE rcv_files ADD COLUMN agent_rcv_file_id BLOB NULL;
|]
