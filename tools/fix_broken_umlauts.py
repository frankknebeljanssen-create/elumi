#!/usr/bin/env python3
"""Repariert zerschossene Umlaute im deutschen Text der Master-DB.

Befund 2026-08-06: Ein Teil des Bestands wurde mit ae/oe/ue statt ä/ö/ü
importiert — „die Einheit fuer Beweglichkeit", „der Kletterfuehrer",
„die Buerste". Im Quiz sieht das aus wie ein Tippfehler.

WARUM NICHT EINFACH ae→ä, oe→ö, ue→ü
────────────────────────────────────
Weil diese Buchstabenfolgen im Deutschen massenhaft korrekt vorkommen.
Die Falle ist subtil: „Steuer" enthält die Folge „ue" (st-e-**ue**-r).
Eine pauschale Ersetzung macht daraus „Stür", aus „Abenteuer" wird
„Abentür", aus „anschauen" „anschaün". Genau deshalb meldete ein erster,
grober Suchlauf 1.380 Treffer — die Hälfte davon Fehlalarme.

DIE ABSICHERUNG
───────────────
Zwei Quellen, beide wortweise (nie auf Teilzeichenketten):

 1. **Selbstvalidierung gegen den eigenen Bestand.** Für jedes Wort mit
    ae/oe/ue werden die Umlaut-Varianten gebildet. Nur wenn eine davon
    **bereits als korrektes Wort in der DB steht**, gilt sie als
    bestätigt — die DB ist ihr eigenes Wörterbuch. „steuererklaerung"
    bekommt so „steuererklärung" (existiert) und nicht „stürerklärung"
    (existiert nicht). 256 Wörter.

 2. **Handgeprüfte Liste** für Wörter ohne korrekten Zwilling im
    Bestand (58 Wörter, unten einzeln aufgeführt und durchgesehen).

Groß-/Kleinschreibung des Originals bleibt erhalten.
NICHT angefasst: ss/ß — das ist eine eigene Frage (Schweizer Schreibung
ist gültig) und gehört nicht in denselben Durchlauf.

BENUTZUNG
─────────
    python3 tools/fix_broken_umlauts.py --dry-run
    python3 tools/fix_broken_umlauts.py
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sqlite3
import sys
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(REPO, "Elumi", "FRDEMasterLexicon.sqlite")
BACKUP = "/tmp/FRDEMasterLexicon.before_umlauts.sqlite"

WORD_RE = re.compile(r"[A-Za-zÄÖÜäöüß-]+")

# Deutsche Textspalten. `senses.word_class` steht bewusst dabei: In dieser
# DB ist die senses-Tabelle spaltenverschoben und führt dort ebenfalls die
# Übersetzung (siehe tools/lexique_frequency.py).
TEXT_COLUMNS = [
    ("entries", "lemma_de", "entry_id"),
    ("senses", "translation_de", "rowid"),
    ("senses", "word_class", "rowid"),
    ("examples", "example_de", "rowid"),
]

# Wörter ohne korrekten Zwilling im Bestand — einzeln durchgesehen.
MANUAL = [
    "alarmgefuehl", "antikoerper", "boarding-verspaetung", "familiengefuehrte",
    "fruehstuecksmenue", "fuetterungsvorfuehrung", "gemuese-pfanne",
    "gemuesegratin", "gemuesequiche", "gewaehlt", "heizkoerperventil",
    "hoehenarbeit", "hoehenmeter", "hoehenstrasse", "industriegelaende",
    "kaeseblaetterteiggebaeck", "kaesesosse", "kaesetoast", "kletterfuehrer",
    "kraeuterfrischkaese", "moeglichst", "natuerlichen", "naturfuehrer",
    "oeffnungsphase", "oeffnungssensor", "pruefungskalender", "saisongemuese",
    "schinken-kaese-panini", "schokostueckchen-cookie", "spannungspruefer",
    "sprachfuehrer", "staedtischen", "stichprobengroesse",
    "stromverbrauchszaehler", "ueberflutet", "uebergangstag", "uebergangswoche",
    "ueberhangwand", "ueberlasteten", "uebermaessige", "ueberschwemmungsebene",
    "ueberschwemmungsgebiet", "uebersicht", "ueberspannungsschutz",
    "ueberspannungsschutz-steckdose", "ueberspannungsschutz-steckdosenleiste",
    "uebertriebene", "verfuegbarkeiten", "verfuegbarkeitsfenster",
    "verfuegbarkeitskalender", "verspaeteten", "verspaetungsnachweis",
    "waermeleit-reinigungspaste", "waermeleitpaste", "waermenetz",
    "wasserkuehlung", "zurueckgewiesen", "zurueckkommt",
    # Nachtrag nach dem ersten Durchlauf — von den Mustern der
    # Kontrollsuche nicht erfasst, beim Nachsehen eindeutig kaputt.
    "objekttraeger", "pferdeanhaenger", "zurueckzieht",
]


def candidates(word: str) -> list[str]:
    """Mögliche Umlaut-Lesarten — einzeln und kombiniert."""
    out = []
    for digraph, umlaut in (("ae", "ä"), ("oe", "ö"), ("ue", "ü")):
        if digraph in word:
            out.append(word.replace(digraph, umlaut))
    combined = word.replace("ae", "ä").replace("oe", "ö").replace("ue", "ü")
    if combined != word:
        out.append(combined)
    return out


def build_mapping(cur) -> dict[str, str]:
    counts: Counter[str] = Counter()
    for table, column, _ in TEXT_COLUMNS:
        cur.execute(f"SELECT {column} FROM {table}")
        for (text,) in cur.fetchall():
            for word in WORD_RE.findall(text or ""):
                counts[word.lower()] += 1

    mapping: dict[str, str] = {}
    for word in counts:
        if not re.search(r"(ae|oe|ue)", word):
            continue
        # Quelle 1: bestätigt durch den eigenen Bestand
        confirmed = [c for c in candidates(word) if c in counts]
        if confirmed:
            mapping[word] = max(confirmed, key=lambda c: counts[c])

    # Quelle 2: handgeprüfte Ergänzungen
    for word in MANUAL:
        if word not in mapping:
            mapping[word] = (word.replace("ae", "ä")
                                 .replace("oe", "ö")
                                 .replace("ue", "ü"))
    return mapping


def match_case(original: str, replacement: str) -> str:
    if original.isupper():
        return replacement.upper()
    if original[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def repair(text: str, mapping: dict[str, str]) -> str:
    def swap(match: re.Match) -> str:
        word = match.group(0)
        fixed = mapping.get(word.lower())
        return match_case(word, fixed) if fixed else word
    return WORD_RE.sub(swap, text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    mapping = build_mapping(cur)
    print(f"Wortformen zum Reparieren: {len(mapping)}")

    total_rows, samples = 0, []
    pending: list[tuple[str, str, str, str]] = []
    for table, column, key in TEXT_COLUMNS:
        cur.execute(f"SELECT {key}, {column} FROM {table}")
        for row_key, text in cur.fetchall():
            if not text:
                continue
            fixed = repair(text, mapping)
            if fixed != text:
                total_rows += 1
                if len(samples) < 12:
                    samples.append((table, text, fixed))
                pending.append((table, column, key, row_key, fixed))

    print(f"Zu ändernde Zeilen: {total_rows}\n")
    for table, before, after in samples:
        print(f"  [{table}] {before}\n       → {after}")

    if args.dry_run:
        print("\n(dry-run — nichts geschrieben)")
        return 0

    shutil.copy(DB, BACKUP)
    for table, column, key, row_key, fixed in pending:
        cur.execute(f"UPDATE {table} SET {column}=? WHERE {key}=?", (fixed, row_key))
    conn.commit()
    cur.execute("PRAGMA integrity_check")
    print(f"\nintegrity_check: {cur.fetchone()[0]}")
    print(f"Backup: {BACKUP}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
