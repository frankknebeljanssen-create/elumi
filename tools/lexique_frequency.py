#!/usr/bin/env python3
"""Ordnet den Einträgen des FRDEMasterLexicon echte Korpusfrequenzen zu.

WARUM
─────
Die Spalte `entries.frequency_rank` ist KEINE Frequenz, sondern die
Reihenfolge des ursprünglichen Bulk-Imports (Befund 2026-08-06): Rang
1–25 sind lückenlos Verben, ab 146 beginnen die Adjektive, ab 2268
stehen thematisch gruppierte Nomen. Gemessen an echter Korpusfrequenz
sind die C-Stufen sogar minimal HÄUFIGER als B2 — sie waren nie
„fortgeschritten", nur spät importiert.

Ohne echte Frequenz lässt sich keine belastbare Niveau-Zuordnung bauen.
Dieses Skript beschafft sie.

BEKANNTE GRENZE — Homographen
─────────────────────────────
Das Matching läuft über die Wortform, nicht über die Bedeutung. Wo eine
Form mehreren Wörtern gehört, gewinnt die häufigste:
    „sur"   (Präposition, sehr häufig)  vs.  „sur" = sauer
    „allée" (Partizip von aller)        vs.  „l'allée" = der Weg
Deshalb steht `cgram` (Wortart laut Lexique) mit in der Ausgabe: Die
Zuordnung in Stufe 3 muss die Wortart gegen `entries.word_class`
prüfen und bei Abweichung misstrauisch sein.

LIZENZ — WICHTIG
────────────────
Quelle ist **Lexique 3** (New, Pallier, Brysbaert, Ferrand;
http://www.lexique.org), lizenziert unter **CC BY-SA 4.0**. Die
ShareAlike-Klausel würde auf eine ausgelieferte Datenbank durchschlagen,
die diese Werte enthält.

Deshalb die Produktentscheidung vom 2026-08-06:
**Lexique wird ausschließlich zur BAUZEIT genutzt.**

  • Die Lexique-Datei wird NICHT ins App-Bundle aufgenommen.
  • Die berechneten Frequenzwerte werden NICHT in die
    ausgelieferte `FRDEMasterLexicon.sqlite` geschrieben.
  • In die App wandert später nur unser **eigenes Niveau-Tag**
    (`entries.level`) — eine redaktionelle Einstufung, die Frequenz
    als EINES von mehreren Kriterien nutzt (siehe Konzept: Frequenz
    allein trifft nur 25 % — schlechter als Raten).

Ausgabe ist deshalb eine reine Arbeitsdatei unter `build-data/`, die
per .gitignore aus dem Repo bleibt und die Stufe-3-Zuordnung speist.

BENUTZUNG
─────────
    python3 tools/lexique_frequency.py --download   # holt Lexique383
    python3 tools/lexique_frequency.py              # erzeugt Mapping

Ausgabe: build-data/entry_frequency.tsv
    entry_id, lemma_fr, matched_form, freq_per_million, source, cgram, genre
"""
from __future__ import annotations

import argparse
import csv
import os
import sqlite3
import statistics
import sys
import unicodedata
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(REPO, "Elumi", "FRDEMasterLexicon.sqlite")
BUILD_DIR = os.path.join(REPO, "build-data")
LEXIQUE = os.path.join(BUILD_DIR, "Lexique383.tsv")
OUT = os.path.join(BUILD_DIR, "entry_frequency.tsv")
LEXIQUE_URL = "http://www.lexique.org/databases/Lexique383/Lexique383.tsv"

FRENCH_ARTICLES = (
    "le ", "la ", "les ", "l'", "l’",
    "un ", "une ", "des ", "du ", "de la ", "de l'",
)


def strip_article(text: str) -> str:
    t = text.strip().lower()
    for art in FRENCH_ARTICLES:
        if t.startswith(art):
            return t[len(art):].strip()
    return t


def normalize_variants(word: str) -> list[str]:
    """Schreibvarianten, unter denen ein Wort in Lexique stehen kann.

    Deckt die vier Miss-Klassen ab, die der Trefferquoten-Test gezeigt
    hat (81 % roh):
      • Ligaturen:      sœur → soeur, œuf → oeuf
      • Reflexivverben: s'habiller → habiller
      • Imperative:     excuse-moi → excuse
      • Akzentverlust:  creme → crème (über akzentfreien Vergleich)
    """
    out, seen = [], set()

    def add(w: str) -> None:
        w = w.strip()
        if w and w not in seen:
            seen.add(w)
            out.append(w)

    base = word.strip().lower()
    add(base)
    add(base.replace("œ", "oe").replace("æ", "ae"))

    for pref in ("s'", "s’", "se ", "m'", "t'"):
        if base.startswith(pref):
            add(base[len(pref):])
            add(base[len(pref):].replace("œ", "oe"))

    # Bindestrich NUR bei Imperativ + angehängtem Pronomen auflösen
    # („excuse-moi" → „excuse"). Ein naives Abschneiden am ersten
    # Bindestrich war ein Fehlgriff (2026-08-06): Es machte aus
    # „est-européen" das Verb „est" (32.236/Mio statt ~2), aus
    # „va-t-en-guerre" das „va" und aus „fait-main" das „fait" — also
    # aus seltenen Komposita scheinbare Hochfrequenzwörter. Genau die
    # Wörter, die eine Frequenz-basierte Einstufung dann fälschlich
    # nach A1 gezogen hätte.
    enclitics = {
        "moi", "toi", "lui", "nous", "vous", "leur",
        "le", "la", "les", "y", "en", "ce", "ci", "là", "t",
    }
    if "-" in base:
        head, _, tail = base.partition("-")
        if all(part in enclitics for part in tail.split("-") if part):
            add(head)

    add(base.replace("'", "’"))
    add(base.replace("’", "'"))
    return out


def deaccent(word: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", word)
        if unicodedata.category(c) != "Mn"
    )


def download() -> None:
    os.makedirs(BUILD_DIR, exist_ok=True)
    print(f"Lade Lexique 3.83 …\n  {LEXIQUE_URL}")
    urllib.request.urlretrieve(LEXIQUE_URL, LEXIQUE)
    size = os.path.getsize(LEXIQUE) / 1_000_000
    print(f"  → {LEXIQUE}  ({size:.1f} MB)")
    print("\n  ⚠️  CC BY-SA 4.0 — nur zur Bauzeit verwenden, nicht ins App-Bundle.")


def load_lexique() -> tuple[dict, dict]:
    """→ (exakte Formen, akzentfreier Index). Wert: (freq, cgram, genre)."""
    if not os.path.exists(LEXIQUE):
        sys.exit(f"Lexique fehlt: {LEXIQUE}\nErst mit --download holen.")

    exact: dict[str, tuple[float, str, str]] = {}
    with open(LEXIQUE, encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            form = row["ortho"].strip().lower()
            if not form:
                continue
            try:
                films = float(row["freqlemfilms2"] or 0)
                livres = float(row["freqlemlivres"] or 0)
            except ValueError:
                continue
            # Untertitel- UND Buchkorpus: das Maximum, weil ein Wort
            # schon dann lernrelevant ist, wenn es in EINEM der beiden
            # Register häufig vorkommt. „bonjour" ist in Büchern selten,
            # im gesprochenen Französisch aber unverzichtbar.
            freq = max(films, livres)
            prev = exact.get(form)
            if prev is None or freq > prev[0]:
                exact[form] = (freq, row["cgram"], row["genre"])

    loose: dict[str, tuple[float, str, str]] = {}
    for form, value in exact.items():
        key = deaccent(form)
        prev = loose.get(key)
        if prev is None or value[0] > prev[0]:
            loose[key] = value
    return exact, loose


def lookup(word: str, exact: dict, loose: dict):
    for variant in normalize_variants(word):
        if variant in exact:
            return variant, exact[variant], "exact"
    for variant in normalize_variants(word):
        key = deaccent(variant)
        if key in loose:
            return variant, loose[key], "deaccent"
    return None, None, None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true",
                        help="Lexique 3.83 nach build-data/ laden")
    args = parser.parse_args()

    if args.download:
        download()
        return 0

    os.makedirs(BUILD_DIR, exist_ok=True)
    exact, loose = load_lexique()
    print(f"Lexique geladen: {len(exact)} Formen")

    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("SELECT entry_id, lemma_fr, is_phrase, level FROM entries")
    rows = cur.fetchall()
    conn.close()

    matched, unmatched, phrases = [], [], 0
    for entry_id, lemma_fr, is_phrase, level in rows:
        core = strip_article(lemma_fr)
        if " " in core:
            # Mehrwort-Einträge: Lexique kennt nur Einzelwörter. Sie
            # bekommen keine eigene Frequenz — für die Niveau-Zuordnung
            # zählt später die Frequenz ihres seltensten Bestandteils
            # (eine Wendung ist höchstens so leicht wie ihr schwerstes
            # Wort). Das macht Stufe 3, nicht dieses Skript.
            phrases += 1
            continue
        form, value, how = lookup(core, exact, loose)
        if value is None:
            unmatched.append((entry_id, lemma_fr, level))
        else:
            freq, cgram, genre = value
            matched.append((entry_id, lemma_fr, form, freq, how, cgram, genre))

    with open(OUT, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["entry_id", "lemma_fr", "matched_form",
                         "freq_per_million", "match_type", "cgram", "genre"])
        writer.writerows(matched)

    total_single = len(matched) + len(unmatched)
    print(f"\nEinwort-Einträge:  {total_single}")
    print(f"  zugeordnet:      {len(matched)}  "
          f"({100 * len(matched) // max(total_single, 1)} %)")
    print(f"  ohne Treffer:    {len(unmatched)}")
    print(f"Mehrwort (übersprungen): {phrases}")
    print(f"\n→ {OUT}")

    print("\nPlausibilität — Median-Frequenz je bestehender Stufe (pro Mio.):")
    by_level: dict[str, list[float]] = {}
    level_of = {r[0]: r[3] for r in rows}
    for entry_id, _, _, freq, _, _, _ in matched:
        by_level.setdefault(level_of[entry_id], []).append(freq)
    for level in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        vals = by_level.get(level, [])
        if vals:
            print(f"  {level}: n={len(vals):6}  Median {statistics.median(vals):8.2f}")

    print("\nStichprobe nicht zugeordnet:")
    for entry_id, lemma, level in unmatched[:10]:
        print(f"  [{level}] {lemma}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
