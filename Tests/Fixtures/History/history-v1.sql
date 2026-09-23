-- Shipped-baseline fixture: keep this stable when later migrations are added.
PRAGMA auto_vacuum = INCREMENTAL;
PRAGMA secure_delete = ON;
PRAGMA journal_mode = WAL;
CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
INSERT INTO grdb_migrations VALUES ('history-v1');
CREATE TABLE history (
    id INTEGER PRIMARY KEY,
    capture_identifier TEXT NOT NULL UNIQUE,
    revision INTEGER NOT NULL CHECK (revision > 0),
    image_location TEXT NOT NULL UNIQUE,
    record_location TEXT NOT NULL UNIQUE,
    thumbnail_location TEXT,
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    image_bytes INTEGER NOT NULL CHECK (image_bytes >= 0),
    record_bytes INTEGER NOT NULL CHECK (record_bytes >= 0),
    thumbnail_bytes INTEGER NOT NULL DEFAULT 0 CHECK (thumbnail_bytes >= 0),
    finalized_at REAL NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('finalized', 'deleting'))
);
CREATE INDEX history_age ON history(finalized_at, id);
INSERT INTO history VALUES (41, '11111111-1111-1111-1111-111111111111', 1,
    'images/11111111-1111-1111-1111-111111111111.png',
    'images/11111111-1111-1111-1111-111111111111.finalization.json', NULL,
    2, 1, 70, 0, 0, 1000, 'finalized');
INSERT INTO history VALUES (42, '22222222-2222-2222-2222-222222222222', 1,
    'images/22222222-2222-2222-2222-222222222222.png',
    'images/22222222-2222-2222-2222-222222222222.finalization.json', NULL,
    2, 1, 70, 0, 0, 1001, 'deleting');
