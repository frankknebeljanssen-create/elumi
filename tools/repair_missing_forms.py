#!/usr/bin/env python3
"""Ergaenzt fehlende Zeilen in der `forms`-Tabelle des Master-Lexikons.

Hintergrund (2026-09-03): Nomen stehen im Lexikon MIT Artikel
(`l'enfant`, `la femme`). Auffindbar sind sie fuer die App nur ueber die
`forms`-Tabelle, in der neben dem vollen Lemma auch die artikelfreie
Variante steht (`chien` fuer `le chien`). Bei einem Teil der Eintraege
fehlt diese Verknuepfung — bei 29 Eintraegen fehlt sogar jede Zeile.

Betroffen waren ausgerechnet die haeufigsten Woerter: l'homme, la femme,
l'enfant, le garcon, la personne, les gens, le monde, le pays. Fuer die
App heisst das: `isNoun("enfant")` ist falsch, "des enfants" wird nicht
auf "enfant" zurueckgefuehrt, und das Genus fehlt im Artikel-Training.

Zwei Luecken werden geschlossen:
  A) Eintraege ohne jede forms-Zeile  -> lemma + variant + de_translation
  B) Nomen mit Artikel, aber ohne artikelfreie `variant` -> variant

Das Zeilenmuster ist von gesunden Eintraegen abgeschaut (`le chien`:
lemma / inflection / variant / de_translation). Alles kleingeschrieben,
so wie der Rest der Tabelle.

Aufruf:
    python3 tools/repair_missing_forms.py          # Bericht, aendert nichts
    python3 tools/repair_missing_forms.py --apply  # schreibt in die DB
"""

import os
import sqlite3
import sys
from typing import List, Optional, Tuple

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(REPO, "Elumi", "ElumiMasterLexicon.sqlite")

FRENCH_ARTICLES = ("le ", "la ", "les ", "l'", "l’")
GERMAN_ARTICLES = ("der ", "die ", "das ")


def strip_french_article(lemma):
    """Artikelfreier Kern, oder None wenn kein Artikel vorangeht."""
    low = lemma.lower()
    for art in FRENCH_ARTICLES:
        if low.startswith(art):
            return low[len(art):].strip()
    return None


def strip_german_article(lemma):
    low = lemma.lower()
    for art in GERMAN_ARTICLES:
        if low.startswith(art):
            return low[len(art):].strip()
    return None


def main():
    apply_changes = "--apply" in sys.argv
    con = sqlite3.connect(DB)
    cur = con.cursor()

    # --- A) Eintraege ganz ohne forms-Zeile -----------------------------
    cur.execute("""
        SELECT e.entry_id, e.lemma_fr, e.lemma_de, e.word_class
        FROM entries e
        WHERE NOT EXISTS (SELECT 1 FROM forms f WHERE f.entry_id = e.entry_id)
        ORDER BY e.lemma_fr
    """)
    orphans = cur.fetchall()

    new_rows = []
    for entry_id, lemma_fr, lemma_de, word_class in orphans:
        fr = (lemma_fr or "").strip().lower()
        if not fr:
            continue
        new_rows.append((fr, entry_id, "lemma"))
        bare = strip_french_article(fr)
        if bare and bare != fr:
            new_rows.append((bare, entry_id, "variant"))
        de = (lemma_de or "").strip().lower()
        if de:
            new_rows.append((de, entry_id, "de_translation"))
            de_bare = strip_german_article(de)
            if de_bare and de_bare != de:
                new_rows.append((de_bare, entry_id, "de_translation"))

    # --- B) Nomen mit Artikel, aber ohne artikelfreie Variante ----------
    cur.execute("""
        SELECT e.entry_id, e.lemma_fr
        FROM entries e
        WHERE e.word_class = 'noun'
          AND EXISTS (SELECT 1 FROM forms f WHERE f.entry_id = e.entry_id)
        ORDER BY e.lemma_fr
    """)
    missing_variant = []
    for entry_id, lemma_fr in cur.fetchall():
        bare = strip_french_article((lemma_fr or "").strip().lower())
        if not bare:
            continue
        cur.execute(
            "SELECT 1 FROM forms WHERE entry_id = ? AND form = ? LIMIT 1",
            (entry_id, bare),
        )
        if cur.fetchone() is None:
            missing_variant.append((entry_id, lemma_fr, bare))
            new_rows.append((bare, entry_id, "variant"))

    # --- Bericht --------------------------------------------------------
    print(f"A) Eintraege ohne jede forms-Zeile: {len(orphans)}")
    for _, lemma_fr, lemma_de, wc in orphans[:40]:
        print(f"     {lemma_fr:<24} {lemma_de:<24} [{wc}]")
    print(f"\nB) Nomen ohne artikelfreie Variante: {len(missing_variant)}")
    for _, lemma_fr, bare in missing_variant[:20]:
        print(f"     {lemma_fr:<28} -> {bare}")
    if len(missing_variant) > 20:
        print(f"     ... und {len(missing_variant) - 20} weitere")
    print(f"\nNeue forms-Zeilen insgesamt: {len(new_rows)}")

    if not apply_changes:
        print("\nDry-Run. Mit --apply schreiben.")
        con.close()
        return 0

    cur.executemany(
        "INSERT INTO forms (form, entry_id, form_type) VALUES (?, ?, ?)",
        new_rows,
    )
    con.commit()
    cur.execute("SELECT COUNT(*) FROM forms")
    print(f"\nGeschrieben. forms-Zeilen jetzt: {cur.fetchone()[0]}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
