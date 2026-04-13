#!/usr/bin/env python3
"""
Build FRDEMasterLexicon.sqlite from app export TSV files.

Usage:
    python3 build_master_lexicon_sqlite.py

Input:  /Users/frankknebeljanssen/Documents/New project/frde_app_export/out/*.tsv
Output: FRDEVocabMVP/FRDEMasterLexicon.sqlite

Run this after updating the master DB export. Then rebuild the app (Shift+Cmd+K, Cmd+R).
"""

import sqlite3
import csv
import os
import sys
import time

EXPORT_DIR = "/Users/frankknebeljanssen/Documents/New project/frde_app_export/out"
OUTPUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "FRDEVocabMVP", "FRDEMasterLexicon.sqlite")

CORE_FILES = {
    "entries": os.path.join(EXPORT_DIR, "app_entries.tsv"),
    "forms": os.path.join(EXPORT_DIR, "app_forms.tsv"),
    "senses": os.path.join(EXPORT_DIR, "app_senses.tsv"),
}

OPTIONAL_FILES = {
    "relations": os.path.join(EXPORT_DIR, "app_relations.tsv"),
    "pronunciations": os.path.join(EXPORT_DIR, "app_pronunciations.tsv"),
}


def check_inputs():
    """Verify all required input files exist."""
    for name, path in CORE_FILES.items():
        if not os.path.exists(path):
            print(f"ERROR: Missing core file: {path}")
            sys.exit(1)
        print(f"  Found {name}: {path}")
    for name, path in OPTIONAL_FILES.items():
        if os.path.exists(path):
            print(f"  Found {name}: {path}")
        else:
            print(f"  Optional {name}: not found (skipping)")


def create_schema(db):
    """Create all tables and indexes."""
    db.executescript("""
        DROP TABLE IF EXISTS entries;
        DROP TABLE IF EXISTS forms;
        DROP TABLE IF EXISTS senses;
        DROP TABLE IF EXISTS relations;
        DROP TABLE IF EXISTS pronunciations;

        CREATE TABLE entries (
            entry_id INTEGER PRIMARY KEY,
            lemma_fr TEXT NOT NULL,
            lemma_de TEXT NOT NULL,
            word_class TEXT DEFAULT '',
            gender_fr TEXT DEFAULT '',
            gender_de TEXT DEFAULT '',
            level TEXT DEFAULT '',
            is_phrase INTEGER DEFAULT 0,
            frequency_rank INTEGER DEFAULT 0
        );

        CREATE TABLE forms (
            form TEXT NOT NULL,
            entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
            form_type TEXT DEFAULT 'lemma'
        );

        CREATE TABLE senses (
            entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
            sense_id INTEGER NOT NULL,
            translation_de TEXT DEFAULT '',
            word_class TEXT DEFAULT '',
            definition_fr TEXT DEFAULT '',
            usage_label TEXT DEFAULT '',
            example_fr TEXT DEFAULT '',
            example_de TEXT DEFAULT '',
            PRIMARY KEY (entry_id, sense_id)
        );

        CREATE TABLE relations (
            entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
            related_entry_id INTEGER NOT NULL,
            relation_type TEXT DEFAULT ''
        );

        CREATE TABLE pronunciations (
            entry_id INTEGER PRIMARY KEY REFERENCES entries(entry_id),
            ipa TEXT DEFAULT ''
        );
    """)


def create_indexes(db):
    """Create all indexes for fast lookups."""
    db.executescript("""
        CREATE INDEX IF NOT EXISTS idx_forms_form ON forms(form);
        CREATE INDEX IF NOT EXISTS idx_forms_entry ON forms(entry_id);
        CREATE INDEX IF NOT EXISTS idx_senses_entry ON senses(entry_id);
        CREATE INDEX IF NOT EXISTS idx_entries_level ON entries(level);
        CREATE INDEX IF NOT EXISTS idx_entries_word_class ON entries(word_class);
        CREATE INDEX IF NOT EXISTS idx_entries_lemma_fr ON entries(lemma_fr);
        CREATE INDEX IF NOT EXISTS idx_relations_entry ON relations(entry_id);
    """)


def load_tsv(path):
    """Read a TSV file and return (headers, rows)."""
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        headers = next(reader)
        rows = list(reader)
    return headers, rows


def import_entries(db, path):
    """Import app_entries.tsv."""
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT INTO entries (entry_id, lemma_fr, lemma_de, word_class, gender_fr, gender_de, level, is_phrase, frequency_rank) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                int(r[0]),       # entry_id
                r[1],            # lemma_fr
                r[2],            # lemma_de
                r[3],            # word_class
                r[4],            # gender_fr
                r[5],            # gender_de
                r[6],            # level
                int(r[7]) if r[7] else 0,  # is_phrase
                int(r[8]) if r[8] else 0,  # frequency_rank
            )
            for r in rows
            if len(r) >= 9 and r[0].strip()
        ],
    )
    return len(rows)


def import_forms(db, path):
    """Import app_forms.tsv."""
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT INTO forms (form, entry_id, form_type) VALUES (?, ?, ?)",
        [
            (r[0], int(r[1]), r[2] if len(r) > 2 else "lemma")
            for r in rows
            if len(r) >= 2 and r[0].strip() and r[1].strip()
        ],
    )
    return len(rows)


def import_senses(db, path):
    """Import app_senses.tsv."""
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT OR REPLACE INTO senses (entry_id, sense_id, translation_de, word_class, definition_fr, usage_label, example_fr, example_de) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                int(r[0]),       # entry_id
                int(r[1]),       # sense_id
                r[2] if len(r) > 2 else "",  # translation_de
                r[3] if len(r) > 3 else "",  # word_class
                r[4] if len(r) > 4 else "",  # definition_fr
                r[5] if len(r) > 5 else "",  # usage_label
                r[6] if len(r) > 6 else "",  # example_fr
                r[7] if len(r) > 7 else "",  # example_de
            )
            for r in rows
            if len(r) >= 2 and r[0].strip() and r[1].strip()
        ],
    )
    return len(rows)


def import_relations(db, path):
    """Import app_relations.tsv."""
    if not os.path.exists(path):
        return 0
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT INTO relations (entry_id, related_entry_id, relation_type) VALUES (?, ?, ?)",
        [
            (int(r[0]), int(r[1]), r[2] if len(r) > 2 else "")
            for r in rows
            if len(r) >= 2 and r[0].strip() and r[1].strip()
        ],
    )
    return len(rows)


def import_pronunciations(db, path):
    """Import app_pronunciations.tsv."""
    if not os.path.exists(path):
        return 0
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT OR REPLACE INTO pronunciations (entry_id, ipa) VALUES (?, ?)",
        [
            (int(r[0]), r[1] if len(r) > 1 else "")
            for r in rows
            if len(r) >= 1 and r[0].strip()
        ],
    )
    return len(rows)


def main():
    start = time.time()
    print("=== Building FRDEMasterLexicon.sqlite ===")
    print(f"Export dir: {EXPORT_DIR}")
    print(f"Output:     {OUTPUT_PATH}")
    print()

    check_inputs()
    print()

    # Remove old DB
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    db = sqlite3.connect(OUTPUT_PATH)
    db.execute("PRAGMA journal_mode=DELETE")  # No WAL — read-only in app bundle
    db.execute("PRAGMA synchronous=OFF")

    print("Creating schema...")
    create_schema(db)

    print("Importing entries...", end=" ")
    n = import_entries(db, CORE_FILES["entries"])
    print(f"{n} rows")

    print("Importing forms...", end=" ")
    n = import_forms(db, CORE_FILES["forms"])
    print(f"{n} rows")

    print("Importing senses...", end=" ")
    n = import_senses(db, CORE_FILES["senses"])
    print(f"{n} rows")

    print("Importing relations...", end=" ")
    n = import_relations(db, OPTIONAL_FILES["relations"])
    print(f"{n} rows")

    print("Importing pronunciations...", end=" ")
    n = import_pronunciations(db, OPTIONAL_FILES["pronunciations"])
    print(f"{n} rows")

    print("Creating indexes...")
    create_indexes(db)

    db.commit()

    # Verify
    cursor = db.cursor()
    for table in ["entries", "forms", "senses", "relations", "pronunciations"]:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        print(f"  {table}: {count} rows")

    db.close()

    elapsed = time.time() - start
    size_mb = os.path.getsize(OUTPUT_PATH) / (1024 * 1024)
    print(f"\nDone in {elapsed:.1f}s. DB size: {size_mb:.1f} MB")
    print(f"Output: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
