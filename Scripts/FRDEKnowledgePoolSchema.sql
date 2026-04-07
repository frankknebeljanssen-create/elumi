PRAGMA journal_mode = DELETE;
PRAGMA synchronous = NORMAL;

CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS lexicon_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_term TEXT NOT NULL,
    target_term TEXT NOT NULL DEFAULT '',
    card_type TEXT NOT NULL,
    source_lookup_key TEXT NOT NULL,
    source_compact_key TEXT NOT NULL,
    source_lookup_variants TEXT NOT NULL,
    source_compact_variants TEXT NOT NULL,
    target_lookup_key TEXT NOT NULL,
    target_compact_key TEXT NOT NULL,
    is_german_noun INTEGER NOT NULL DEFAULT 0,
    is_french_question INTEGER NOT NULL DEFAULT 0,
    source_gender TEXT,
    target_gender TEXT,
    source_article TEXT,
    target_leading_article TEXT
);

CREATE INDEX IF NOT EXISTS idx_lexicon_source_lookup_key
ON lexicon_entries(source_lookup_key);

CREATE INDEX IF NOT EXISTS idx_lexicon_source_compact_key
ON lexicon_entries(source_compact_key);

CREATE INDEX IF NOT EXISTS idx_lexicon_target_lookup_key
ON lexicon_entries(target_lookup_key);

CREATE INDEX IF NOT EXISTS idx_lexicon_card_type
ON lexicon_entries(card_type);
