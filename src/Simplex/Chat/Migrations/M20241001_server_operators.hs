{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Migrations.M20241001_server_operators where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20241001_server_operators :: Query
m20241001_server_operators =
  [sql|
CREATE TABLE server_operators (
  server_operator_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  preset INTEGER NOT NULL DEFAULT 0,
  reserved INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  role_storage INTEGER NOT NULL DEFAULT 1,
  role_proxy INTEGER NOT NULL DEFAULT 1
);

ALTER TABLE protocol_servers ADD COLUMN server_operator_id INTEGER REFERENCES server_operators ON DELETE SET NULL;
ALTER TABLE protocol_servers ADD COLUMN role_storage INTEGER NOT NULL DEFAULT 1;
ALTER TABLE protocol_servers ADD COLUMN role_proxy INTEGER NOT NULL DEFAULT 1;

CREATE INDEX idx_protocol_servers_operators ON protocol_servers(server_operator_id);

INSERT INTO server_operators (server_operator_id, name, preset, reserved) VALUES (1, 'SimpleX Chat', 1, 0);
INSERT INTO server_operators (server_operator_id, name, preset, reserved) VALUES (2, '', 1, 1);
INSERT INTO server_operators (server_operator_id, name, preset, reserved) VALUES (3, '', 1, 1);
INSERT INTO server_operators (server_operator_id, name, preset, reserved) VALUES (4, '', 1, 1);
INSERT INTO server_operators (server_operator_id, name, preset, reserved) VALUES (5, '', 1, 1);

UPDATE protocol_servers SET server_operator_id = 1 WHERE host LIKE "%.simplex.im" OR host LIKE "%.simplex.im,%";
|]

down_m20241001_server_operators :: Query
down_m20241001_server_operators =
  [sql|
DROP INDEX idx_protocol_servers_operators;

ALTER TABLE protocol_servers DROP COLUMN server_operator_id;
ALTER TABLE protocol_servers DROP COLUMN role_storage;
ALTER TABLE protocol_servers DROP COLUMN role_proxy;

DROP TABLE server_operators;
|]
