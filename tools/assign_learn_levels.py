#!/usr/bin/env python3
"""Vergibt das Lern-Niveau (`entries.learn_level`) neu.

WARUM EINE NEUE SPALTE
──────────────────────
`entries.level` bleibt unangetastet. Die Spalte wird an mehreren Stellen
für etwas anderes gelesen als für Lernlisten — `MCDistractorFilter`
leitet daraus die Distraktor-Schwierigkeit ab, `vocabularyLevel(for:)`
die App-weite `VocabularyLevel`, `AppDataStoreDictionary` die Gruppierung
im Wörterbuch. Würden wir sie überschreiben, änderten wir unbemerkt das
Verhalten dieser drei.

`learn_level` ist deshalb additiv: NUR die Lernlisten („Nach Lernstand")
lesen sie. NULL bedeutet „gehört in kein Lernpaket" — der Eintrag bleibt
über Wörterbuch und Themenlisten erreichbar. Rückgängig machen heißt:
Spalte ignorieren.

DIE REGELN (und warum)
──────────────────────
Reine Frequenz trifft das offizielle Referentiel nur zu 25 % — schlechter
als ein Dummy, der immer dieselbe Stufe rät (Pintard & François 2020).
Deshalb vier Kriterien statt einem:

 1. **Kuratiertes A1 gewinnt immer.** Die 949 A1-Einträge tragen als
    einzige `confidence`/`schulrelevanz` und haben eine Median-Frequenz
    von 143/Mio — da hat jemand sauber gearbeitet. Sie bleiben A1, auch
    wenn sie korpusselten sind: „la calculatrice" (0,56/Mio) ist ein
    *mot disponible* — im Korpus selten, im Klassenzimmer unverzichtbar.
    Genau diese Fälle verliert eine reine Frequenzliste.

 2. **Wortart muss übereinstimmen.** Das Matching läuft über die
    Wortform, nicht die Bedeutung. Ohne diese Prüfung erbt „l'été"
    (der Sommer) die Frequenz von „été" (Partizip von être, 32.236/Mio)
    und wird zum häufigsten Wort der App. 1.668 Einträge sind betroffen.

 3. **Frequenzbänder**, kalibriert auf die fachlichen Zielgrößen
    (Beacco/RLD kumuliert, Milton für Französisch):
        A1 ≈   950 kumulativ  →  ab 116/Mio
        A2 ≈ 1.500            →  ab  69/Mio
        B1 ≈ 2.700            →  ab  31/Mio
        B2 ≈ 5.000            →  ab  10,7/Mio
    Darunter: kein Lernpaket.

 4. **Wendungen erben von ihrem schwersten Wort, plus eine Stufe.**
    „aller à la bibliothèque" ist nicht schwerer als sein seltenstes
    Wort, aber auch nicht leichter — und als Mehrwort-Einheit eine
    Stufe anspruchsvoller als das Einzelwort.

ERWARTETE UNSCHÄRFE
───────────────────
±0,5 Stufen sind Stand der Technik (bestes ML-Modell: 54 % Trefferquote,
MAE 0,66 Stufen). Die A2/B1-Grenze ist die unzuverlässigste, weil die
Frequenzen dort stark überlappen. Das ist kein Fehler dieses Skripts,
sondern die Eigenschaft der Aufgabe — Niveaus sind Orientierung, keine
Prüfungswahrheit.

BENUTZUNG
─────────
    python3 tools/assign_learn_levels.py --dry-run   # nur Bericht
    python3 tools/assign_learn_levels.py             # schreibt in die DB
"""
from __future__ import annotations

import argparse
import csv
import os
import shutil
import sqlite3
import sys
from collections import Counter, defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(REPO, "FRDEVocabMVP", "FRDEMasterLexicon.sqlite")
FREQ_FILE = os.path.join(REPO, "build-data", "entry_frequency.tsv")
BACKUP = "/tmp/FRDEMasterLexicon.before_learn_levels.sqlite"

# Schwellen in Vorkommen pro Million (siehe Modul-Doc, Punkt 3).
#
# A1–B1 kalibriert am kumulativen Endstand: das traf mit den ersten drei
# Schwellen bereits Beacco/RLD (A1 827/1.442/2.776 kumuliert) und Milton.
#
# **2026-08-07, B2 nachjustiert** — User-Report: bei nur +1.378 Wörtern
# sah B2 „dünn" aus. Berechtigt: Beacco/RLD bringt für B2 +2.742 dazu,
# wir nur gut halb so viel. Schwelle 18 → 10 gesenkt (bringt ~600
# zusätzliche Einträge). Wortart-Filter (Regel 2, Homographen-Schutz)
# bleibt unverändert und hält bei der neuen, niedrigeren Schwelle
# weiterhin dieselben Homographen draußen (`un`, `sur`, `fait`, `en` …
# geprüft) — die Vergrößerung bringt also mehr Substanz, keinen neuen
# Datenmüll.
BANDS = [("A1", 200.0), ("A2", 100.0), ("B1", 45.0), ("B2", 10.0), ("XP", 4.0)]
ORDER = ["A1", "A2", "B1", "B2", "XP"]

# `XP` statt `C1`: bewusst KEIN GER-Etikett. Die offiziellen Europarat-
# Referenzbände für Französisch („Niveau A1/A2/B1/B2 pour le français")
# hören bei B2 auf — für C1/C2 gibt es kein Wortinventar, das eine
# Zuordnung begründen könnte. Ein Frequenzband unterhalb B2 als „C1" zu
# labeln wäre wieder eine unbelegte Setzung, nur diesmal mit
# amtlich klingendem Namen. „XP — Über den Schulstoff hinaus" sagt
# ehrlich, was es ist: mehr Wörter für alle, die weiterüben wollen,
# ohne einen Anspruch zu erheben, den wir nicht einlösen können.

# Aus wie geläufigen Wörtern darf eine Wendung höchstens bestehen, damit
# sie ins Lernpaket kommt? Eine Wendung aus lauter B1/B2-Wörtern ist kein
# Schulstoff, sondern Fachsprache — genau die maschinell erzeugten
# Konstrukte („die statistische Robustheit modellieren"), die B2 bisher
# zu 91 % füllten. Grenze bei A2 halbiert die Wendungszahl.
PHRASE_MAX_SOURCE = "A2"

# Lexique-Wortart → unsere `word_class`
POS_MAP = {
    "NOM": "noun", "VER": "verb", "ADJ": "adjective", "ADV": "adverb",
    "PRO": "pronoun", "PRE": "preposition", "CON": "conjunction",
    "ART": "determiner", "ONO": "interjection",
}

FRENCH_ARTICLES = ("le ", "la ", "les ", "l'", "l’", "un ", "une ",
                   "des ", "du ", "de la ", "de l'")


def strip_article(text: str) -> str:
    t = text.strip().lower()
    for art in FRENCH_ARTICLES:
        if t.startswith(art):
            return t[len(art):].strip()
    return t


def band_for(freq: float) -> str | None:
    for level, threshold in BANDS:
        if freq >= threshold:
            return level
    return None


def bump(level: str) -> str:
    """Eine Stufe schwerer, gedeckelt bei B2."""
    idx = ORDER.index(level)
    return ORDER[min(idx + 1, len(ORDER) - 1)]


def load_frequency() -> tuple[dict, dict]:
    if not os.path.exists(FREQ_FILE):
        sys.exit(f"Fehlt: {FREQ_FILE}\nErst tools/lexique_frequency.py laufen lassen.")
    freq, pos = {}, {}
    with open(FREQ_FILE, encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            entry_id = int(row["entry_id"])
            freq[entry_id] = float(row["freq_per_million"])
            pos[entry_id] = (row["cgram"] or "").split(",")[0].strip()
    return freq, pos


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="nur berichten, nichts schreiben")
    args = parser.parse_args()

    freq, lex_pos = load_frequency()
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("""SELECT entry_id, lemma_fr, lemma_de, word_class, level,
                          is_phrase, confidence, schulrelevanz
                   FROM entries""")
    rows = cur.fetchall()

    assigned: dict[int, str] = {}
    reason = Counter()

    # ── Regel 1: kuratiertes A1 gewinnt ──────────────────────────────
    for entry_id, _, _, _, level, _, confidence, relevance in rows:
        if level == "A1" and (confidence or relevance):
            assigned[entry_id] = "A1"
            reason["1_kuratiertes_A1"] += 1

    # ── Regel 2+3: Frequenzband, nur bei Wortart-Übereinstimmung ─────
    pos_conflict = 0
    for entry_id, lemma_fr, _, word_class, _, is_phrase, _, _ in rows:
        if entry_id in assigned or entry_id not in freq:
            continue
        raw_pos = lex_pos.get(entry_id, "")
        mapped = POS_MAP.get(raw_pos[:3].upper())
        if word_class and mapped and mapped != word_class:
            pos_conflict += 1
            continue                      # Homograph-Verdacht → nicht einstufen
        level = band_for(freq[entry_id])
        if level:
            assigned[entry_id] = level
            reason["3_frequenzband"] += 1

    # ── Regel 4: Wendungen erben vom schwersten Bestandteil ──────────
    # Nachschlagewerk Wortform → bestes (niedrigstes) zugewiesenes Niveau
    form_level: dict[str, str] = {}
    for entry_id, lemma_fr, *_ in rows:
        level = assigned.get(entry_id)
        if not level:
            continue
        form = strip_article(lemma_fr)
        if " " in form:
            continue
        prev = form_level.get(form)
        if prev is None or ORDER.index(level) < ORDER.index(prev):
            form_level[form] = level

    for entry_id, lemma_fr, _, _, _, is_phrase, _, _ in rows:
        if entry_id in assigned:
            continue
        words = [w for w in strip_article(lemma_fr).split() if w]
        if len(words) < 2:
            continue
        levels = [form_level.get(strip_article(w)) for w in words]
        known = [l for l in levels if l]
        # Nur einstufen, wenn WIRKLICH JEDES Wort bekannt ist. Sonst
        # wäre „modéliser la robustesse statistique" schon deshalb B1,
        # weil „la" bekannt ist — genau der Müll, den wir loswerden.
        if len(known) != len(words):
            continue
        hardest = max(known, key=ORDER.index)
        if ORDER.index(hardest) > ORDER.index(PHRASE_MAX_SOURCE):
            continue                      # zu speziell, siehe PHRASE_MAX_SOURCE
        assigned[entry_id] = bump(hardest)
        reason["4_wendung_abgeleitet"] += 1

    # ── Bericht ──────────────────────────────────────────────────────
    counts = Counter(assigned.values())
    cumulative, running = {}, 0
    for level in ORDER:
        running += counts[level]
        cumulative[level] = running

    print("Zuordnung nach Regel:")
    for key in sorted(reason):
        print(f"  {key:24} {reason[key]:6}")
    print(f"  {'wegen Wortart verworfen':24} {pos_conflict:6}")
    print()
    print(f"{'Stufe':6} {'neu':>7} {'kumulativ':>10} {'Zielgröße':>11}")
    # Zielgrößen sind Vergleichswerte aus Beacco/RLD (kumuliert), keine
    # Vorgabe — XP hat keinen offiziellen Referenzwert (siehe Modul-Doc).
    targets = {"A1": "827", "A2": "1.442", "B1": "2.776", "B2": "5.518", "XP": "—"}
    for level in ORDER:
        print(f"{level:6} {counts[level]:7} {cumulative[level]:10} {targets[level]:>11}")
    print(f"\nOhne Lernpaket (bleiben im Wörterbuch): "
          f"{len(rows) - len(assigned)} von {len(rows)}")

    if args.dry_run:
        print("\n(dry-run — nichts geschrieben)")
        return 0

    shutil.copy(DB, BACKUP)
    cur.execute("PRAGMA table_info(entries)")
    if "learn_level" not in {c[1] for c in cur.fetchall()}:
        cur.execute("ALTER TABLE entries ADD COLUMN learn_level TEXT")
        print("\nSpalte `learn_level` angelegt.")
    cur.execute("UPDATE entries SET learn_level = NULL")
    cur.executemany("UPDATE entries SET learn_level = ? WHERE entry_id = ?",
                    [(lvl, eid) for eid, lvl in assigned.items()])
    conn.commit()
    cur.execute("PRAGMA integrity_check")
    print(f"integrity_check: {cur.fetchone()[0]}")
    conn.close()
    print(f"Backup: {BACKUP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
