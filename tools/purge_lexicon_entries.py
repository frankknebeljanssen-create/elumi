#!/usr/bin/env python3
"""Entfernt Lexikon-Einträge restlos aus der Master-DB.

**Grundsatz (User-Spec 2026-08-05):** Begriffe, die nicht in eine
Schul-Vokabel-App gehören — unbelegbare Übersetzungen, extrem seltene
Fachtermini, Fremdsprachen-Ausreißer — werden nicht notdürftig
repariert, sondern gelöscht. Und zwar vollständig: Ein Eintrag, der
nur aus `entries` verschwindet, hinterlässt verwaiste Zeilen in
`senses`, `examples`, `forms`, `pronunciations` und `relations`, die
später als Geister-Treffer wieder auftauchen können.

Verwendung:
    python3 tools/purge_lexicon_entries.py 7717 8340
    python3 tools/purge_lexicon_entries.py --dry-run 7717

Legt vor jedem Schreibvorgang ein Backup an.
"""
import argparse
import shutil
import sqlite3
import sys
from datetime import datetime

DB = "Elumi/FRDEMasterLexicon.sqlite"

# Tabelle -> Spalten, die auf `entries.entry_id` zeigen. Zentral
# gepflegt: Kommt eine neue Nebentabelle dazu, gehört sie hierher,
# sonst bleiben beim Löschen Reste liegen.
DEPENDENTS = {
    "senses": ["entry_id"],
    "examples": ["entry_id"],
    "forms": ["entry_id"],
    "pronunciations": ["entry_id"],
    "relations": ["entry_id", "related_entry_id"],
}


def purge(entry_ids, dry_run=False):
    con = sqlite3.connect(DB)
    cur = con.cursor()

    placeholders = ",".join("?" for _ in entry_ids)
    rows = cur.execute(
        f"SELECT entry_id, lemma_fr, lemma_de, word_class, level, topic "
        f"FROM entries WHERE entry_id IN ({placeholders})",
        entry_ids,
    ).fetchall()

    if not rows:
        print("Keine passenden Einträge gefunden — nichts zu tun.")
        return 1

    found_ids = [r[0] for r in rows]
    missing = sorted(set(entry_ids) - set(found_ids))

    print("Zu löschende Einträge:\n")
    for eid, fr, de, wc, lv, tp in rows:
        print(f"  {eid:6d} | {fr:30s} | {de:28s} | {wc or '-':10s} | {lv or '-':4s} | {tp}")
    if missing:
        print(f"\n  (nicht vorhanden, übersprungen: {missing})")

    print("\nAbhängige Zeilen:")
    total_deps = 0
    for table, columns in DEPENDENTS.items():
        for column in columns:
            count = cur.execute(
                f"SELECT COUNT(*) FROM {table} WHERE {column} IN ({placeholders})",
                entry_ids,
            ).fetchone()[0]
            if count:
                print(f"  {table}.{column}: {count}")
                total_deps += count
    print(f"  Summe: {total_deps}")

    if dry_run:
        print("\n--dry-run: nichts geschrieben.")
        con.close()
        return 0

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"/tmp/FRDEMasterLexicon.before_purge_{stamp}.sqlite"
    shutil.copy2(DB, backup)
    print(f"\nBackup: {backup}")

    for table, columns in DEPENDENTS.items():
        for column in columns:
            cur.execute(
                f"DELETE FROM {table} WHERE {column} IN ({placeholders})", entry_ids
            )
    cur.execute(f"DELETE FROM entries WHERE entry_id IN ({placeholders})", entry_ids)
    con.commit()

    # Kontrolle: nichts darf zurückbleiben.
    leftovers = 0
    for table, columns in DEPENDENTS.items():
        for column in columns:
            leftovers += cur.execute(
                f"SELECT COUNT(*) FROM {table} WHERE {column} IN ({placeholders})",
                entry_ids,
            ).fetchone()[0]
    leftovers += cur.execute(
        f"SELECT COUNT(*) FROM entries WHERE entry_id IN ({placeholders})", entry_ids
    ).fetchone()[0]

    integrity = cur.execute("PRAGMA integrity_check").fetchone()[0]
    remaining = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    con.close()

    print(f"\nGelöscht: {len(found_ids)} Einträge + {total_deps} abhängige Zeilen")
    print(f"Reste:        {leftovers} (muss 0 sein)")
    print(f"Integrität:   {integrity}")
    print(f"Einträge nun: {remaining}")
    return 0 if leftovers == 0 and integrity == "ok" else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry_ids", nargs="+", type=int)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    sys.exit(purge(args.entry_ids, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
