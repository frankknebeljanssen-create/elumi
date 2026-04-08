#!/usr/bin/env python3
"""
Build-Script: Generiert das erweiterte Standardpaket aus FLELex + FreeDictSupplement.

Input:
  - Scripts/FleLex_TT_Beacco.tsv (13k+ FLE-Lehrwerk-Vokabeln mit GER-Levels)
  - FRDEVocabMVP/FRDEFreeDictSupplement.sqlite (78k FR-DE Übersetzungen mit Geschlecht)

Output:
  - FRDEVocabMVP/StandardpaketFLELex.tsv (gematchte Einträge für die App)
  - Konsolenausgabe mit Statistiken
"""

import csv
import sqlite3
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
FLELEX_PATH = os.path.join(SCRIPT_DIR, "FleLex_TT_Beacco.tsv")
SQLITE_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "FRDEFreeDictSupplement.sqlite")
OUTPUT_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "StandardpaketFLELex.tsv")

# Mapping FLELex tags to app CardType
TAG_TO_CARDTYPE = {
    "NOM": "words",
    "VER": "words",
    "ADJ": "words",
    "ADV": "words",
    "INT": "phrases",
    "PRO": "words",
    "PRP": "words",
    "KON": "words",
}

# Mapping FLELex tags to word class for training modes
TAG_TO_WORDCLASS = {
    "NOM": "noun",
    "VER": "verb",
    "ADJ": "adjective",
    "ADV": "adverb",
    "INT": "interjection",
    "PRO": "pronoun",
    "PRP": "preposition",
    "KON": "conjunction",
}

# Skip trivial function words that aren't useful for learning
SKIP_WORDS = {
    "a", "au", "aux", "ce", "ces", "de", "des", "du", "en", "et",
    "il", "je", "la", "le", "les", "ma", "me", "mes", "mon", "ne",
    "nos", "notre", "nous", "on", "ou", "par", "pas", "pour", "que",
    "qui", "sa", "se", "ses", "si", "son", "sur", "ta", "te", "tes",
    "ton", "tu", "un", "une", "vos", "votre", "vous", "y",
    "-ci", "-là", "c'", "d'", "j'", "l'", "m'", "n'", "qu'", "s'",
}

# Levels to include (school-relevant)
INCLUDE_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}

# Manual overrides for the most common words where FreeDictSupplement picks wrong translations
TRANSLATION_OVERRIDES = {
    "avoir": "haben", "être": "sein", "faire": "machen", "aller": "gehen",
    "dire": "sagen", "pouvoir": "können", "vouloir": "wollen", "devoir": "müssen",
    "savoir": "wissen", "voir": "sehen", "venir": "kommen", "prendre": "nehmen",
    "mettre": "setzen / stellen", "donner": "geben", "falloir": "müssen",
    "croire": "glauben", "tenir": "halten", "trouver": "finden",
    "parler": "sprechen", "aimer": "lieben / mögen", "passer": "vorbeigehen",
    "rester": "bleiben", "penser": "denken", "sortir": "hinausgehen",
    "suivre": "folgen", "connaître": "kennen", "sentir": "fühlen / riechen",
    "vivre": "leben", "perdre": "verlieren", "écrire": "schreiben",
    "lire": "lesen", "courir": "laufen", "ouvrir": "öffnen",
    "mourir": "sterben", "partir": "weggehen / abfahren", "dormir": "schlafen",
    "manger": "essen", "boire": "trinken", "entendre": "hören",
    "attendre": "warten", "rendre": "zurückgeben", "tomber": "fallen",
    "chercher": "suchen", "porter": "tragen", "montrer": "zeigen",
    "commencer": "anfangen", "jouer": "spielen", "appeler": "rufen / anrufen",
    "marcher": "gehen / laufen", "acheter": "kaufen", "envoyer": "schicken",
    "fermer": "schließen", "chanter": "singen", "danser": "tanzen",
    "nager": "schwimmen", "voyager": "reisen", "travailler": "arbeiten",
    "étudier": "studieren / lernen", "habiter": "wohnen",
    "demander": "fragen / bitten", "répondre": "antworten",
    "comprendre": "verstehen", "apprendre": "lernen",
    "essayer": "versuchen", "choisir": "wählen / aussuchen",
    "finir": "beenden", "remplir": "füllen", "réussir": "gelingen / schaffen",
    # Common non-verbs
    "dans": "in", "avec": "mit", "mais": "aber", "pour": "für",
    "sans": "ohne", "sous": "unter", "entre": "zwischen",
    "chez": "bei / zu Hause", "vers": "gegen / in Richtung",
    "bien": "gut", "très": "sehr", "aussi": "auch", "encore": "noch",
    "toujours": "immer", "souvent": "oft", "jamais": "nie",
    "beaucoup": "viel", "peu": "wenig", "trop": "zu viel",
    "tout": "alles / ganz", "autre": "andere(r)", "même": "gleich / selbst",
    "grand": "groß", "petit": "klein", "bon": "gut", "nouveau": "neu",
    "beau": "schön", "vieux": "alt", "jeune": "jung", "long": "lang",
    "premier": "erste(r)", "dernier": "letzte(r)", "seul": "allein / einzig",
    "elle": "sie", "lui": "ihm / er", "cela": "das / dies",
    "moi": "mir / ich", "rien": "nichts", "quelque": "einige",
    "homme": "Mann", "femme": "Frau", "enfant": "Kind",
    "temps": "Zeit", "jour": "Tag", "an": "Jahr", "vie": "Leben",
    "monde": "Welt", "pays": "Land", "ville": "Stadt", "maison": "Haus",
    "main": "Hand", "oeil": "Auge", "tête": "Kopf", "corps": "Körper",
    "eau": "Wasser", "terre": "Erde", "air": "Luft",
    "chose": "Sache / Ding", "travail": "Arbeit", "place": "Platz",
    "mot": "Wort", "heure": "Stunde", "fois": "Mal",
    "point": "Punkt", "part": "Teil", "coup": "Schlag",
}


def load_flelex():
    """Load FLELex entries."""
    entries = []
    with open(FLELEX_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            word = row["word"].strip()
            tag = row["tag"].strip()
            level = row.get("level", "").strip()

            if not word or not level:
                continue
            if level not in INCLUDE_LEVELS:
                continue
            if word.lower() in SKIP_WORDS:
                continue
            if tag.startswith("DET") or tag.startswith("PRP:"):
                continue
            if len(word) < 2:
                continue

            entries.append({
                "word": word,
                "tag": tag,
                "level": level,
                "card_type": TAG_TO_CARDTYPE.get(tag, "words"),
                "word_class": TAG_TO_WORDCLASS.get(tag, ""),
                "freq_total": float(row.get("freq_total", "0") or "0"),
            })

    print(f"FLELex loaded: {len(entries)} entries")
    return entries


def match_with_supplement(entries):
    """Match FLELex entries with FreeDictSupplement for German translations + gender."""
    db = sqlite3.connect(SQLITE_PATH)
    cursor = db.cursor()

    matched = []
    unmatched_count = 0

    for entry in entries:
        lookup_key = entry["word"].lower().strip()

        # Try exact match
        cursor.execute(
            "SELECT source_term, target_term, source_gender "
            "FROM lexicon_entries "
            "WHERE source_lookup_key = ? AND target_term != '' "
            "ORDER BY LENGTH(target_term) ASC "
            "LIMIT 8",
            (lookup_key,)
        )
        rows = cursor.fetchall()

        if not rows:
            compact_key = lookup_key.replace(" ", "")
            cursor.execute(
                "SELECT source_term, target_term, source_gender "
                "FROM lexicon_entries "
                "WHERE source_compact_key = ? AND target_term != '' "
                "ORDER BY LENGTH(target_term) ASC "
                "LIMIT 8",
                (compact_key,)
            )
            rows = cursor.fetchall()

        if rows:
            source_term, target_term, gender = pick_best_translation(rows, entry["tag"])

            # Apply manual override if available
            override_key = entry["word"].lower()
            if override_key in TRANSLATION_OVERRIDES:
                target_term = TRANSLATION_OVERRIDES[override_key]

            # For nouns, try to get the canonical source with article
            if entry["tag"] == "NOM" and gender:
                article = gender_to_article(gender, source_term)
                if article and not has_article(source_term):
                    source_display = f"{article} {source_term}"
                else:
                    source_display = source_term
            else:
                source_display = source_term

            matched.append({
                **entry,
                "source_display": source_display,
                "target": target_term,
                "gender": gender or "",
                "all_translations": " / ".join(r[1] for r in rows[:3]),
            })
        else:
            unmatched_count += 1

    db.close()
    print(f"Matched: {len(matched)}, Unmatched: {unmatched_count}")
    return matched


def pick_best_translation(rows, tag):
    """Pick the best German translation from multiple candidates."""
    if len(rows) == 1:
        return rows[0]

    candidates = [(src, tgt, gen) for src, tgt, gen in rows if len(tgt) > 1]
    if not candidates:
        candidates = rows

    if tag == "VER":
        # Prefer German verbs (ending in -en, -ern, -eln)
        verb_translations = [
            (s, t, g) for s, t, g in candidates
            if t.lower().endswith(("en", "ern", "eln"))
        ]
        if verb_translations:
            return verb_translations[0]

    if tag == "NOM":
        # Prefer translations with German articles or capitalized (nouns)
        noun_translations = [
            (s, t, g) for s, t, g in candidates
            if t[0].isupper() or t.lower().startswith(("der ", "die ", "das "))
        ]
        if noun_translations:
            return noun_translations[0]

    if tag == "ADJ":
        # Prefer lowercase adjectives
        adj_translations = [
            (s, t, g) for s, t, g in candidates
            if t[0].islower() and len(t) > 2
        ]
        if adj_translations:
            return adj_translations[0]

    # Fallback: prefer medium-length translations (not too short, not too long)
    candidates.sort(key=lambda x: abs(len(x[1]) - 8))
    return candidates[0]


def gender_to_article(gender, word):
    """Convert gender string to French article."""
    word_lower = word.lower().strip()
    vowels = set("aeiouyâêîôûéèëïüàùh")

    if word_lower and word_lower[0] in vowels:
        return "l'"

    if gender == "feminine":
        return "la"
    elif gender == "masculine":
        return "le"
    return None


def has_article(text):
    """Check if text already starts with a French article."""
    lower = text.lower().strip()
    articles = ["le ", "la ", "l'", "l'", "les ", "un ", "une ", "des ", "du "]
    return any(lower.startswith(a) for a in articles)


def write_output(matched):
    """Write matched entries to TSV."""
    # Sort by level priority, then frequency
    level_order = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}
    matched.sort(key=lambda x: (level_order.get(x["level"], 9), -x["freq_total"]))

    with open(OUTPUT_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow([
            "source_display", "target", "card_type", "level",
            "word_class", "gender", "flelex_word", "freq_total"
        ])

        for entry in matched:
            writer.writerow([
                entry["source_display"],
                entry["target"],
                entry["card_type"],
                entry["level"],
                entry["word_class"],
                entry["gender"],
                entry["word"],
                f"{entry['freq_total']:.2f}",
            ])

    print(f"\nOutput written to: {OUTPUT_PATH}")
    print(f"Total entries: {len(matched)}")

    # Stats
    print("\n=== Statistiken ===")
    by_level = {}
    by_class = {}
    by_level_class = {}
    for e in matched:
        l = e["level"]
        c = e["word_class"]
        by_level[l] = by_level.get(l, 0) + 1
        by_class[c] = by_class.get(c, 0) + 1
        key = f"{l}/{c}"
        by_level_class[key] = by_level_class.get(key, 0) + 1

    print("\nNach Level:")
    for l in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        count = by_level.get(l, 0)
        nouns = by_level_class.get(f"{l}/noun", 0)
        verbs = by_level_class.get(f"{l}/verb", 0)
        adjs = by_level_class.get(f"{l}/adjective", 0)
        print(f"  {l}: {count:5d} (Nomen: {nouns}, Verben: {verbs}, Adj: {adjs})")

    print("\nNach Wortart:")
    for c, count in sorted(by_class.items(), key=lambda x: -x[1]):
        print(f"  {c}: {count}")

    # Gender stats for nouns
    nouns_with_gender = sum(1 for e in matched if e["word_class"] == "noun" and e["gender"])
    nouns_total = sum(1 for e in matched if e["word_class"] == "noun")
    print(f"\nNomen mit Geschlecht: {nouns_with_gender}/{nouns_total} ({100*nouns_with_gender//max(1,nouns_total)}%)")


if __name__ == "__main__":
    print("=== FLELex Standardpaket Builder ===\n")
    entries = load_flelex()
    matched = match_with_supplement(entries)
    write_output(matched)
    print("\nFertig!")
