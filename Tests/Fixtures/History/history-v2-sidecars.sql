-- The schema before ticket 78 (history-v1 plus history-retention-v1): sidecar columns,
-- the `deleting` state and the auxiliary ledger. Keep this stable; it is a migration input.
PRAGMA auto_vacuum = INCREMENTAL;
PRAGMA secure_delete = ON;
PRAGMA journal_mode = WAL;
CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
INSERT INTO grdb_migrations VALUES ('history-v1');
INSERT INTO grdb_migrations VALUES ('history-retention-v1');
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
    state TEXT NOT NULL CHECK (state IN ('finalized', 'deleting')),
    date_normalized INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX history_age ON history(finalized_at, id);
CREATE TABLE history_retention (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    last_quota_eviction REAL,
    quota_notice_pending INTEGER NOT NULL DEFAULT 0,
    last_sweep REAL,
    age_deferred INTEGER NOT NULL DEFAULT 0
);
INSERT INTO history_retention (id, last_sweep) VALUES (1, 1000);
CREATE TABLE history_auxiliary_files (
    capture_identifier TEXT NOT NULL,
    location TEXT PRIMARY KEY,
    logical_bytes INTEGER NOT NULL CHECK (logical_bytes >= 0)
);
-- An edited capture (revision 2) with its sidecar and cached thumbnail.
INSERT INTO history VALUES (7, '33333333-3333-3333-3333-333333333333', 2,
    'images/33333333-3333-3333-3333-333333333333.png',
    'images/33333333-3333-3333-3333-333333333333.finalization.json',
    'thumbnails/33333333-3333-3333-3333-333333333333.png',
    2, 1, 70, 10, 70, 1000, 'finalized', 1);
-- A row the old store was deleting when it stopped.
INSERT INTO history VALUES (8, '44444444-4444-4444-4444-444444444444', 1,
    'images/44444444-4444-4444-4444-444444444444.png',
    'images/44444444-4444-4444-4444-444444444444.finalization.json',
    'thumbnails/44444444-4444-4444-4444-444444444444.png',
    2, 1, 70, 10, 70, 1001, 'deleting', 0);
-- An interrupted finalization: its image and sidecar are on disk, owned only by the ledger.
INSERT INTO history_auxiliary_files VALUES ('55555555-5555-5555-5555-555555555555',
    'images/55555555-5555-5555-5555-555555555555.png', 70);
INSERT INTO history_auxiliary_files VALUES ('55555555-5555-5555-5555-555555555555',
    'images/55555555-5555-5555-5555-555555555555.finalization.json', 10);
