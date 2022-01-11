DROP TABLE event_body_parts;
DROP TABLE contact_profile_events;
DROP TABLE group_profile_events;
DROP TABLE group_event_parents;
DROP TABLE group_events;
DROP TABLE message_events;
DROP TABLE message_content;
DROP TABLE events;
DROP TABLE messages;

-- all message events as received or sent, append only
-- maps to message deliveries as one-to-many for group messages
CREATE TABLE messages (
  message_id INTEGER PRIMARY KEY,
  msg_sent INTEGER NOT NULL, -- 0 for received, 1 for sent
  chat_msg_event TEXT NOT NULL, -- message event type (the constructor of ChatMsgEvent)
  msg_body BLOB, -- agent message body as received or sent
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- message deliveries communicated with the agent, append only
CREATE TABLE msg_deliveries (
  msg_delivery_id INTEGER PRIMARY KEY,
  message_id INTEGER NOT NULL REFERENCES messages ON DELETE CASCADE, -- non UNIQUE for group messages
  connection_id INTEGER NOT NULL REFERENCES connections ON DELETE CASCADE,
  agent_msg_id INTEGER, -- internal agent message ID (NULL while pending)
  agent_msg_meta TEXT, -- JSON with timestamps etc. sent in MSG, NULL for sent
  chat_ts TEXT NOT NULL DEFAULT (datetime('now')), -- broker_ts for received, created_at for sent
  UNIQUE (connection_id, agent_msg_id)
);

-- TODO recovery for received messages with "rcv_agent" status - acknowledge to agent
-- changes of messagy delivery status, append only
CREATE TABLE msg_delivery_events (
  msg_delivery_event_id INTEGER PRIMARY KEY,
  msg_delivery_id INTEGER NOT NULL REFERENCES msg_deliveries ON DELETE CASCADE, -- non UNIQUE for multiple events per msg delivery
  delivery_status TEXT NOT NULL, -- see MsgDeliveryStatus for allowed values
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (msg_delivery_id, delivery_status)
);

-- TODO delete all message views when merging migrations

CREATE VIEW direct_messages AS
SELECT
  ct.local_display_name AS contact,
  m.message_id AS message_id,
  m.msg_sent AS msg_sent,
  m.chat_msg_event AS chat_msg_event,
  m.msg_body AS msg_body,
  md.msg_delivery_id AS delivery_id,
  datetime(md.chat_ts) AS chat_dt,
  md.agent_msg_meta AS msg_meta,
  mde.delivery_status AS delivery_status,
  datetime(mde.created_at) AS delivery_status_dt
FROM messages m
JOIN msg_deliveries md ON md.message_id = m.message_id
JOIN (
  SELECT msg_delivery_id, MAX(created_at) MaxDate
  FROM msg_delivery_events
  GROUP BY msg_delivery_id
) MaxDates ON MaxDates.msg_delivery_id = md.msg_delivery_id
JOIN msg_delivery_events mde ON mde.msg_delivery_id = MaxDates.msg_delivery_id
                            AND mde.created_at = MaxDates.MaxDate
JOIN connections c ON c.connection_id = md.connection_id
JOIN contacts ct ON ct.contact_id = c.contact_id
ORDER BY chat_dt DESC;

CREATE VIEW direct_messages_plain AS
SELECT
  dm.contact AS contact,
  dm.msg_sent AS msg_sent,
  dm.msg_body AS msg_body,
  dm.chat_dt AS chat_dt
FROM direct_messages dm
WHERE dm.chat_msg_event = 'x.msg.new';

CREATE VIEW group_messages AS
SELECT
  g.local_display_name AS group_name,
  gm.local_display_name AS contact,
  m.message_id AS message_id,
  m.msg_sent AS msg_sent,
  m.chat_msg_event AS chat_msg_event,
  m.msg_body AS msg_body,
  md.msg_delivery_id AS delivery_id,
  datetime(md.chat_ts) AS chat_dt,
  md.agent_msg_meta AS msg_meta,
  mde.delivery_status AS delivery_status,
  datetime(mde.created_at) AS delivery_status_dt
FROM messages m
JOIN msg_deliveries md ON md.message_id = m.message_id
JOIN (
  SELECT msg_delivery_id, MAX(created_at) MaxDate
  FROM msg_delivery_events
  GROUP BY msg_delivery_id
) MaxDates ON MaxDates.msg_delivery_id = md.msg_delivery_id
JOIN msg_delivery_events mde ON mde.msg_delivery_id = MaxDates.msg_delivery_id
                            AND mde.created_at = MaxDates.MaxDate
JOIN connections c ON c.connection_id = md.connection_id
JOIN group_members gm ON gm.group_member_id = c.group_member_id
JOIN groups g ON g.group_id = gm.group_id
ORDER BY chat_dt DESC;

CREATE VIEW group_messages_plain AS
SELECT
  gm.group_name AS group_name,
  (CASE WHEN gm.msg_sent = 0 THEN gm.contact ELSE gm.group_name END) AS contact,
  gm.msg_sent AS msg_sent,
  gm.msg_body AS msg_body,
  gm.chat_dt AS chat_dt
FROM group_messages gm
JOIN (
  SELECT message_id, MIN(delivery_id) MinDeliveryId
  FROM group_messages
  GROUP BY message_id
) Deduplicated ON Deduplicated.message_id = gm.message_id
              AND Deduplicated.MinDeliveryId = gm.delivery_id
WHERE gm.chat_msg_event = 'x.msg.new';

CREATE VIEW all_messages (
  group_name,
  contact,
  message_id,
  msg_sent,
  chat_msg_event,
  msg_body,
  delivery_id,
  chat_dt,
  msg_meta,
  delivery_status,
  delivery_status_dt
) AS
  SELECT * FROM (
    SELECT NULL AS group_name, * FROM direct_messages
    UNION
    SELECT * FROM group_messages
  )
  ORDER BY chat_dt DESC;

CREATE VIEW all_messages_plain (
  group_name,
  contact,
  msg_sent,
  msg_body,
  chat_dt
) AS
  SELECT * FROM (
    SELECT NULL AS group_name, * FROM direct_messages_plain
    UNION
    SELECT * FROM group_messages_plain
  )
  ORDER BY chat_dt DESC;

-- TODO group message parents and chat items not to be implemented in current scope

-- CREATE TABLE group_message_parents (
--   group_message_parent_id INTEGER PRIMARY KEY,
--   message_id INTEGER NOT NULL REFERENCES group_messages (event_id),
--   parent_group_member_id INTEGER REFERENCES group_members (group_member_id), -- can be NULL if parent_member_id is incorrect
--   parent_member_id BLOB, -- shared member ID, unique per group
--   parent_message_id INTEGER REFERENCES messages (message_id) ON DELETE CASCADE, -- can be NULL if received message references another message that's not received yet
--   parent_chat_msg_id INTEGER NOT NULL,
--   parent_msg_body_hash BLOB NOT NULL
-- );

-- CREATE INDEX group_event_parents_parent_chat_event_id_index
--   ON group_message_parents (parent_member_id, parent_chat_msg_id);

-- CREATE TABLE chat_items ( -- mutable chat_items presented to user
--   chat_item_id INTEGER PRIMARY KEY,
--   chat_msg_id INTEGER NOT NULL, -- sent as part of the message that created the item
--   item_deleted INTEGER NOT NULL, -- 1 for deleted
--   item_type TEXT NOT NULL,
--   item_text TEXT NOT NULL, -- textual representation
--   item_props TEXT NOT NULL -- JSON
-- );

-- CREATE TABLE direct_chat_items (
--   chat_item_id INTEGER NOT NULL UNIQUE REFERENCES chat_items ON DELETE CASCADE,
--   contact_id INTEGER NOT NULL REFERENCES contacts ON DELETE RESTRICT,
--   item_sent INTEGER -- 1 for sent, 0 for received
-- );

-- CREATE TABLE group_chat_items (
--   chat_item_id INTEGER NOT NULL UNIQUE REFERENCES chat_items ON DELETE CASCADE,
--   group_member_id INTEGER REFERENCES group_members ON DELETE RESTRICT, -- NULL for sent
--   group_id INTEGER NOT NULL REFERENCES groups ON DELETE RESTRICT
-- );

-- CREATE TABLE chat_item_content (
--   chat_item_content_id INTEGER PRIMARY KEY,
--   chat_item_id INTEGER NOT NULL REFERENCES chat_items ON DELETE CASCADE,
--   content_type TEXT NOT NULL,
--   content_size INTEGER NOT NULL,
--   content BLOB NOT NULL
-- );

-- CREATE TABLE chat_item_messages (
--   message_id INTEGER NOT NULL UNIQUE REFERENCES messages,
--   chat_item_id INTEGER NOT NULL REFERENCES chat_items
-- );
