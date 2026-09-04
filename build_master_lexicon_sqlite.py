#!/usr/bin/env python3
"""
Build ElumiMasterLexicon.sqlite from app export TSV files.

Usage:
    python3 build_master_lexicon_sqlite.py

Input:  /Users/frankknebeljanssen/Documents/New project/frde_app_export/out/*.tsv
Output: Elumi/ElumiMasterLexicon.sqlite

Run this after updating the master DB export. Then rebuild the app (Shift+Cmd+K, Cmd+R).
"""

import sqlite3
import csv
import os
import sys
import time

EXPORT_DIR = "/Users/frankknebeljanssen/Documents/New project/frde_app_export/out"
OUTPUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Elumi", "ElumiMasterLexicon.sqlite")

CORE_FILES = {
    "entries": os.path.join(EXPORT_DIR, "app_entries.tsv"),
    "forms": os.path.join(EXPORT_DIR, "app_forms.tsv"),
    "senses": os.path.join(EXPORT_DIR, "app_senses.tsv"),
}

OPTIONAL_FILES = {
    "relations": os.path.join(EXPORT_DIR, "app_relations.tsv"),
    "pronunciations": os.path.join(EXPORT_DIR, "app_pronunciations.tsv"),
    "examples": os.path.join(EXPORT_DIR, "app_examples.tsv"),
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
        DROP TABLE IF EXISTS examples;

        CREATE TABLE entries (
            entry_id INTEGER PRIMARY KEY,
            lemma_fr TEXT NOT NULL,
            lemma_de TEXT NOT NULL,
            word_class TEXT DEFAULT '',
            gender_fr TEXT DEFAULT '',
            gender_de TEXT DEFAULT '',
            level TEXT DEFAULT '',
            is_phrase INTEGER DEFAULT 0,
            frequency_rank INTEGER DEFAULT 0,
            topic TEXT DEFAULT 'Allgemein'
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

        CREATE TABLE examples (
            entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
            example_id INTEGER NOT NULL,
            example_order INTEGER DEFAULT 0,
            example_fr TEXT DEFAULT '',
            example_de TEXT DEFAULT '',
            example_type TEXT DEFAULT '',
            example_level TEXT DEFAULT '',
            PRIMARY KEY (entry_id, example_id)
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
        CREATE INDEX IF NOT EXISTS idx_entries_topic ON entries(topic);
        CREATE INDEX IF NOT EXISTS idx_relations_entry ON relations(entry_id);
        CREATE INDEX IF NOT EXISTS idx_examples_entry_order ON examples(entry_id, example_order);
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
        "INSERT INTO entries (entry_id, lemma_fr, lemma_de, word_class, gender_fr, gender_de, level, is_phrase, frequency_rank, topic) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
                r[9] if len(r) > 9 else "Allgemein",  # topic
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


def generate_search_forms(db):
    """Generate accent-stripped and article-stripped search forms for better findability."""
    import unicodedata

    def strip_accents(text):
        """Remove diacritical marks: é→e, è→e, ê→e, ç→c, etc."""
        nfkd = unicodedata.normalize("NFKD", text)
        return "".join(c for c in nfkd if not unicodedata.combining(c))

    articles = ["le ", "la ", "l'", "les ", "un ", "une ", "des ", "du ", "de la ", "de l'"]

    cursor = db.cursor()
    cursor.execute("SELECT DISTINCT form, entry_id FROM forms")
    existing = cursor.fetchall()

    # Collect existing form+entry pairs to avoid duplicates
    existing_set = set((f.lower(), eid) for f, eid in existing)

    # Add German translations as search forms (for DE→FR search)
    de_articles = ["der ", "die ", "das ", "den ", "dem ", "des ", "ein ", "eine "]

    def german_ascii_variants(text):
        """
        Erzeugt ASCII-Suchvarianten für deutschen Text:
          • ß → ss    („heißen" → „heissen")
          • ä → ae, ö → oe, ü → ue   („Küche" → „kueche", „schön" → „schoen")
        Nur die nötige Anzahl Varianten wird zurückgegeben (Set, keine Duplikate).
        """
        variants = set()
        # ß → ss
        if "ß" in text:
            variants.add(text.replace("ß", "ss"))
        # Umlaute → ae/oe/ue (+ alle Kombinationen)
        umlaut_base = text
        if "ä" in umlaut_base or "ö" in umlaut_base or "ü" in umlaut_base:
            expanded = (
                umlaut_base
                .replace("ä", "ae")
                .replace("ö", "oe")
                .replace("ü", "ue")
                .replace("ß", "ss")
            )
            variants.add(expanded)
        # Falls beide vorkamen, auch Kombination (ß + Umlaute schon im expanded)
        return [v for v in variants if v and v != text]

    cursor.execute("SELECT DISTINCT entry_id, translation_de FROM senses WHERE translation_de != ''")
    de_new = []
    for entry_id, translation_de in cursor.fetchall():
        de_lower = translation_de.lower().strip()
        if not de_lower:
            continue
        if (de_lower, entry_id) not in existing_set:
            de_new.append((de_lower, entry_id, "de_translation"))
            existing_set.add((de_lower, entry_id))
        # Strip German article
        for art in de_articles:
            if de_lower.startswith(art):
                without = de_lower[len(art):].strip()
                if without and (without, entry_id) not in existing_set:
                    de_new.append((without, entry_id, "de_translation"))
                    existing_set.add((without, entry_id))
                break
        # ß/Umlaut-ASCII-Varianten (heißen → heissen, Küche → kueche, ...)
        for variant in german_ascii_variants(de_lower):
            if (variant, entry_id) not in existing_set:
                de_new.append((variant, entry_id, "de_translation"))
                existing_set.add((variant, entry_id))
            # Auch article-stripped Version der ASCII-Variante
            for art in de_articles:
                if variant.startswith(art):
                    without = variant[len(art):].strip()
                    if without and (without, entry_id) not in existing_set:
                        de_new.append((without, entry_id, "de_translation"))
                        existing_set.add((without, entry_id))
                    break

    # Auch entries.lemma_de als Such-Form (+ ASCII-Varianten), damit Nomen/Verb-Lemmas direkt findbar sind
    cursor.execute("SELECT DISTINCT entry_id, lemma_de FROM entries WHERE lemma_de != ''")
    for entry_id, lemma_de in cursor.fetchall():
        lem_lower = lemma_de.lower().strip()
        if not lem_lower:
            continue
        if (lem_lower, entry_id) not in existing_set:
            de_new.append((lem_lower, entry_id, "de_lemma"))
            existing_set.add((lem_lower, entry_id))
        for art in de_articles:
            if lem_lower.startswith(art):
                without = lem_lower[len(art):].strip()
                if without and (without, entry_id) not in existing_set:
                    de_new.append((without, entry_id, "de_lemma"))
                    existing_set.add((without, entry_id))
                break
        for variant in german_ascii_variants(lem_lower):
            if (variant, entry_id) not in existing_set:
                de_new.append((variant, entry_id, "de_lemma"))
                existing_set.add((variant, entry_id))
            for art in de_articles:
                if variant.startswith(art):
                    without = variant[len(art):].strip()
                    if without and (without, entry_id) not in existing_set:
                        de_new.append((without, entry_id, "de_lemma"))
                        existing_set.add((without, entry_id))
                    break

    if de_new:
        db.executemany("INSERT INTO forms (form, entry_id, form_type) VALUES (?, ?, ?)", de_new)
    print(f"  (added {len(de_new)} German search forms)")
    new_forms = []

    import re as _re

    def apostrophe_space_variant(text):
        """'s'appeler' → 's appeler'; 'j'ai' → 'j ai'. Apostrophe durch Leerzeichen."""
        if "'" not in text and "\u2019" not in text:
            return text
        replaced = text.replace("\u2019", "'").replace("'", " ")
        return _re.sub(r"\s+", " ", replaced).strip()

    for form, entry_id in existing:
        form_lower = form.lower()

        # 1. Strip accents
        stripped = strip_accents(form_lower)
        if stripped != form_lower and (stripped, entry_id) not in existing_set:
            new_forms.append((stripped, entry_id, "search_variant"))
            existing_set.add((stripped, entry_id))

        # 2. Strip leading article
        for art in articles:
            if form_lower.startswith(art):
                without_article = form_lower[len(art):].strip()
                if without_article and (without_article, entry_id) not in existing_set:
                    new_forms.append((without_article, entry_id, "search_variant"))
                    existing_set.add((without_article, entry_id))
                # Also accent-strip the article-stripped version
                stripped_no_art = strip_accents(without_article)
                if stripped_no_art != without_article and (stripped_no_art, entry_id) not in existing_set:
                    new_forms.append((stripped_no_art, entry_id, "search_variant"))
                    existing_set.add((stripped_no_art, entry_id))
                break

        # 3. Apostroph-Varianten: „s'appeler" → „s appeler", „j'ai" → „j ai", „c'est" → „c est".
        # Der Such-Normalizer in der App ersetzt ' durch Leerzeichen, die DB muss die
        # Leerzeichen-Variante kennen, damit Reflexivverben und Elisionen findbar sind.
        space_var = apostrophe_space_variant(form_lower)
        if space_var and space_var != form_lower and (space_var, entry_id) not in existing_set:
            new_forms.append((space_var, entry_id, "search_variant"))
            existing_set.add((space_var, entry_id))
            # Auch accent-stripped Version dieser Variante
            space_no_accents = strip_accents(space_var)
            if space_no_accents != space_var and (space_no_accents, entry_id) not in existing_set:
                new_forms.append((space_no_accents, entry_id, "search_variant"))
                existing_set.add((space_no_accents, entry_id))

    if new_forms:
        db.executemany(
            "INSERT INTO forms (form, entry_id, form_type) VALUES (?, ?, ?)",
            new_forms,
        )

    return len(new_forms)


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


def import_examples(db, path):
    """Import app_examples.tsv — multiple example sentences per entry_id."""
    if not os.path.exists(path):
        return 0
    headers, rows = load_tsv(path)
    db.executemany(
        "INSERT OR REPLACE INTO examples (entry_id, example_id, example_order, example_fr, example_de, example_type, example_level) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (
                int(r[0]),                              # entry_id
                int(r[1]),                              # example_id
                int(r[2]) if len(r) > 2 and r[2].strip() else 0,  # example_order
                r[3] if len(r) > 3 else "",             # example_fr
                r[4] if len(r) > 4 else "",             # example_de
                r[5] if len(r) > 5 else "",             # example_type
                r[6] if len(r) > 6 else "",             # example_level
            )
            for r in rows
            if len(r) >= 2 and r[0].strip() and r[1].strip()
        ],
    )
    return len(rows)


def dedupe_redundant_senses(db):
    """
    Entfernt redundante „Listen-Senses" — wenn ein Eintrag zwei Senses hat:
        Sense A: translation_de = "Straße"
        Sense B: translation_de = "Straße; Öffentlichkeit; Straße als soziales Feld"
    … dann ist B nur eine Liste, in der A als erster Eintrag steht.
    Wir löschen Sense B, wenn das erste Semikolon-Segment einem anderen Sense desselben
    Eintrags entspricht.
    """
    cursor = db.cursor()
    cursor.execute("""
        SELECT entry_id, sense_id, translation_de FROM senses
        WHERE translation_de != ''
        ORDER BY entry_id, sense_id
    """)
    rows = cursor.fetchall()

    by_entry = {}
    for entry_id, sense_id, trans in rows:
        by_entry.setdefault(entry_id, []).append((sense_id, trans))

    to_delete = []  # [(entry_id, sense_id)]
    for entry_id, senses in by_entry.items():
        if len(senses) < 2:
            continue
        simple_translations = set()
        # Erst: alle einfachen (ohne Semikolon) Übersetzungen sammeln
        for sense_id, trans in senses:
            if ";" not in trans:
                simple_translations.add(trans.strip().lower())
        # Dann: Listen-Senses prüfen, deren erste Teile bereits als simple_trans existieren
        for sense_id, trans in senses:
            if ";" not in trans:
                continue
            first_part = trans.split(";")[0].strip().lower()
            if first_part in simple_translations:
                to_delete.append((entry_id, sense_id))

    if to_delete:
        cursor.executemany(
            "DELETE FROM senses WHERE entry_id = ? AND sense_id = ?",
            to_delete
        )
    return len(to_delete)


def promote_compound_nouns(db):
    """
    Wandelt Einträge, die DB-seitig als `word_class='phrase'` gekennzeichnet sind,
    aber strukturell Compound-Nomen sind, in `word_class='noun'` um.

    Struktur eines Compound-Nomen:
      • beginnt mit franz. Artikel (le, la, les, l', un, une, des)
      • enthält mindestens EIN Nomen-Token
      • enthält KEIN konjugiertes Verb-Token
      • 1 bis 5 Tokens nach dem Artikel

    Damit werden Fälle wie
      „le jeu vidéo", „la salle à manger", „le chemin de fer",
      „la carte d'identité", „la clé USB", „le tour de magie",
      „le petit déjeuner", „la pomme de terre" …
    automatisch als noun klassifiziert.

    Nicht getroffen: „je ne sais pas", „c'est fini", „avec plaisir",
    Sätze mit konjugiertem Verb, idiomatische Wendungen ohne Artikel.
    """
    cursor = db.cursor()

    # 1) Nomen-Set aufbauen (inklusive artikel-gestrippt)
    articles = ["le ", "la ", "les ", "l'", "l\u2019", "un ", "une ", "des ", "du ", "l'"]
    noun_lemmas = set()
    cursor.execute("SELECT DISTINCT LOWER(lemma_fr) FROM entries WHERE word_class = 'noun'")
    for (lemma,) in cursor.fetchall():
        if not lemma:
            continue
        noun_lemmas.add(lemma)
        for art in articles:
            if lemma.startswith(art):
                stripped = lemma[len(art):].strip()
                if stripped:
                    noun_lemmas.add(stripped)
                break
        # Erster Token als Noun-Kandidat (ohne Artikel-Check)
        parts = lemma.split()
        for p in parts:
            p_clean = p.strip("'\u2019.,;:!?()")
            if p_clean and len(p_clean) > 1:
                noun_lemmas.add(p_clean)

    # 2) Konjugierte Verb-Flexionen (letztes Wort aus z.B. „je sais" → „sais")
    conjugated_verb_tokens = set()
    cursor.execute("""
        SELECT DISTINCT LOWER(f.form)
        FROM forms f
        JOIN entries e ON f.entry_id = e.entry_id
        WHERE f.form_type = 'inflection' AND e.word_class = 'verb'
    """)
    for (form,) in cursor.fetchall():
        if not form:
            continue
        if " " in form:
            last = form.split()[-1]
            if last:
                conjugated_verb_tokens.add(last)
        else:
            conjugated_verb_tokens.add(form)

    # 3) Phrase-Einträge scannen und promovieren
    cursor.execute("SELECT entry_id, lemma_fr FROM entries WHERE word_class = 'phrase'")
    candidates = cursor.fetchall()
    promoted_ids = []
    examples = []

    for entry_id, lemma in candidates:
        if not lemma:
            continue
        lemma_lower = lemma.lower().strip()

        # Muss mit Artikel beginnen
        body = None
        for art in articles:
            if lemma_lower.startswith(art):
                body = lemma_lower[len(art):].strip()
                break
        if not body:
            continue

        # Satzzeichen am Ende → sicher keine Compound-Noun (Satz/Aufruf)
        if body.endswith((".", "!", "?")):
            continue

        # Tokenisieren (auf Leerzeichen und Apostroph)
        tokens_raw = body.replace("'", " ").replace("\u2019", " ").split()
        tokens = [t for t in tokens_raw if t]
        if not (1 <= len(tokens) <= 5):
            continue

        # Mindestens ein Token muss ein bekanntes Nomen sein
        has_noun_token = any(t in noun_lemmas for t in tokens)
        if not has_noun_token:
            continue

        # Kein Token darf konjugierte Verb-Flexion sein (Infinitive = ok)
        has_conjugated_verb = any(t in conjugated_verb_tokens for t in tokens)
        if has_conjugated_verb:
            continue

        promoted_ids.append(entry_id)
        if len(examples) < 10:
            examples.append(lemma)

    # 4) Batch-Update
    if promoted_ids:
        cursor.executemany(
            "UPDATE entries SET word_class = 'noun' WHERE entry_id = ?",
            [(eid,) for eid in promoted_ids]
        )

    # Zwischen-Summary
    print(f"    (Beispiele: {', '.join(examples[:5])}{' ...' if len(examples) > 5 else ''})")

    return len(promoted_ids)


def main():
    start = time.time()
    print("=== Building ElumiMasterLexicon.sqlite ===")
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

    print("Importing examples...", end=" ")
    n = import_examples(db, OPTIONAL_FILES["examples"])
    print(f"{n} rows")

    print("Dedupe redundant list-senses...", end=" ")
    n = dedupe_redundant_senses(db)
    print(f"{n} senses removed")

    print("Promoting compound nouns (phrase → noun)...", end=" ")
    n = promote_compound_nouns(db)
    print(f"{n} entries promoted")

    print("Generating search forms (accent-stripped, article-stripped)...", end=" ")
    n = generate_search_forms(db)
    print(f"{n} new forms")

    print("Creating indexes...")
    create_indexes(db)

    db.commit()

    # Verify
    cursor = db.cursor()
    for table in ["entries", "forms", "senses", "relations", "pronunciations", "examples"]:
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
