#!/usr/bin/env python3
"""
Batch-translate FLELex words using GPT for clean, modern, school-relevant German translations.
Sends words in batches of 50 to minimize API calls.

Usage: OPENAI_API_KEY=sk-... python3 translate_flelex_with_gpt.py
"""

import csv
import json
import os
import sys
import time
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
FLELEX_PATH = os.path.join(SCRIPT_DIR, "FleLex_TT_Beacco.tsv")
OUTPUT_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "StandardpaketGPT.tsv")
PROGRESS_PATH = os.path.join(SCRIPT_DIR, "gpt_translate_progress.json")

API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODEL = "gpt-4o-mini"
BATCH_SIZE = 50

SKIP_WORDS = {
    "a", "au", "aux", "ce", "ces", "de", "des", "du", "en", "et",
    "il", "je", "la", "le", "les", "ma", "me", "mes", "mon", "ne",
    "nos", "notre", "nous", "on", "ou", "par", "pas", "que",
    "qui", "sa", "se", "ses", "si", "son", "sur", "ta", "te", "tes",
    "ton", "tu", "un", "une", "vos", "votre", "vous", "y",
    "-ci", "-là", "c'", "d'", "j'", "l'", "m'", "n'", "qu'", "s'",
}

TAG_TO_WORDCLASS = {
    "NOM": "noun", "VER": "verb", "ADJ": "adjective", "ADV": "adverb",
    "INT": "interjection", "PRO": "pronoun", "PRP": "preposition", "KON": "conjunction",
}

INCLUDE_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}


def load_flelex():
    entries = []
    with open(FLELEX_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            word = row["word"].strip()
            tag = row["tag"].strip()
            level = row.get("level", "").strip()
            if not word or not level or level not in INCLUDE_LEVELS:
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
                "word_class": TAG_TO_WORDCLASS.get(tag, ""),
                "freq_total": float(row.get("freq_total", "0") or "0"),
            })
    return entries


def load_progress():
    if os.path.exists(PROGRESS_PATH):
        with open(PROGRESS_PATH, "r") as f:
            return json.load(f)
    return {}


def save_progress(progress):
    with open(PROGRESS_PATH, "w") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def call_gpt(words_with_info):
    """Send a batch of words to GPT for translation."""
    word_list = "\n".join(
        f"{i+1}. {w['word']} ({w['tag']}, {w['level']})"
        for i, w in enumerate(words_with_info)
    )

    prompt = f"""Übersetze diese französischen Wörter ins Deutsche.
Gib die häufigste, modernste, schulrelevante Übersetzung.

Regeln:
- Bei Nomen: gib den deutschen Artikel mit an (der/die/das), z.B. "die Schule"
- Bei Verben: gib den Infinitiv, z.B. "machen"
- Bei Adjektiven: Grundform, z.B. "groß"
- Maximal 2-3 Wörter pro Übersetzung, keine langen Erklärungen
- Bei mehreren Bedeutungen: die häufigste zuerst, optional zweite mit / getrennt
- Französische Nomen: gib auch den frz. Artikel an, z.B. "le chien" → "der Hund"

Antworte NUR als JSON-Array mit Objekten:
{{"fr": "le chien", "de": "der Hund", "gender": "m", "topic": "Tiere & Natur"}}

gender: "m" für maskulin, "f" für feminin, "" wenn kein Nomen.
fr: das französische Wort MIT Artikel bei Nomen.
topic: eines von: Begrüßung & Höflichkeit, Familie & Freunde, Schule & Bildung, Essen & Trinken, Wohnen & Haus, Körper & Gesundheit, Kleidung & Mode, Tiere & Natur, Stadt & Verkehr, Reisen & Urlaub, Freizeit & Hobbys, Sport, Medien & Technik, Arbeit & Beruf, Einkaufen & Geld, Wetter & Jahreszeiten, Zeit & Datum, Farben & Formen, Zahlen & Mengen, Gefühle & Charakter, Kommunikation, Grammatik & Struktur, Allgemein

Wörter:
{word_list}"""

    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "Du bist ein Französisch-Deutsch Wörterbuch für Schüler. Gib präzise, moderne Übersetzungen."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.1,
        "max_tokens": 4000,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"].strip()
            # Extract JSON from response (might be wrapped in ```json...```)
            if content.startswith("```"):
                content = content.split("\n", 1)[1]
                content = content.rsplit("```", 1)[0]
            return json.loads(content)
    except (urllib.error.URLError, json.JSONDecodeError, KeyError, IndexError) as e:
        print(f"  ❌ API error: {e}")
        return None


def main():
    if not API_KEY:
        # Try reading from plist
        plist_path = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "OpenAIConfig.plist")
        if os.path.exists(plist_path):
            import plistlib
            with open(plist_path, "rb") as f:
                plist = plistlib.load(f)
                api_key = plist.get("OPENAI_API_KEY", "")
                if api_key and not api_key.startswith("REPLACE"):
                    globals()["API_KEY"] = api_key
                    print(f"API key loaded from plist")

    if not API_KEY:
        print("❌ No API key found. Set OPENAI_API_KEY or put it in OpenAIConfig.plist")
        sys.exit(1)

    print("=== FLELex GPT Translator ===\n")
    entries = load_flelex()
    print(f"Loaded {len(entries)} FLELex entries\n")

    # Deduplicate by word (keep highest frequency)
    seen = {}
    for e in entries:
        key = e["word"].lower()
        if key not in seen or e["freq_total"] > seen[key]["freq_total"]:
            seen[key] = e
    unique_entries = sorted(seen.values(), key=lambda x: -x["freq_total"])
    print(f"Unique words: {len(unique_entries)}\n")

    progress = load_progress()
    results = []

    # Resume from progress
    for key, val in progress.items():
        results.append(val)

    remaining = [e for e in unique_entries if e["word"].lower() not in progress]
    print(f"Already translated: {len(progress)}, Remaining: {len(remaining)}\n")

    batches = [remaining[i:i+BATCH_SIZE] for i in range(0, len(remaining), BATCH_SIZE)]
    total_batches = len(batches)

    for batch_idx, batch in enumerate(batches):
        print(f"Batch {batch_idx+1}/{total_batches} ({len(batch)} words)...", end=" ", flush=True)

        translations = call_gpt(batch)
        if translations and len(translations) == len(batch):
            for entry, trans in zip(batch, translations):
                result = {
                    "source_display": trans.get("fr", entry["word"]),
                    "target": trans.get("de", ""),
                    "card_type": "words",
                    "level": entry["level"],
                    "word_class": entry["word_class"],
                    "gender": trans.get("gender", ""),
                    "topic": trans.get("topic", "Allgemein"),
                    "flelex_word": entry["word"],
                    "freq_total": entry["freq_total"],
                }
                results.append(result)
                progress[entry["word"].lower()] = result

            save_progress(progress)
            print(f"✅ {len(translations)} translated")
        elif translations:
            # Partial match — try to salvage
            print(f"⚠️ Got {len(translations)} for {len(batch)} words, saving what we have")
            for trans in translations:
                fr_word = trans.get("fr", "").lower().replace("le ", "").replace("la ", "").replace("l'", "").replace("les ", "").strip()
                matching = [e for e in batch if e["word"].lower() == fr_word or e["word"].lower().startswith(fr_word[:4])]
                if matching:
                    entry = matching[0]
                    result = {
                        "source_display": trans.get("fr", entry["word"]),
                        "target": trans.get("de", ""),
                        "card_type": "words",
                        "level": entry["level"],
                        "word_class": entry["word_class"],
                        "gender": trans.get("gender", ""),
                        "flelex_word": entry["word"],
                        "freq_total": entry["freq_total"],
                    }
                    results.append(result)
                    progress[entry["word"].lower()] = result
            save_progress(progress)
        else:
            print(f"❌ Failed, will retry later")

        # Rate limiting
        time.sleep(0.5)

    # Write final output
    level_order = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}
    results.sort(key=lambda x: (level_order.get(x.get("level", ""), 9), -x.get("freq_total", 0)))

    with open(OUTPUT_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["source_display", "target", "card_type", "level", "word_class", "gender", "topic", "flelex_word", "freq_total"])
        for r in results:
            if r.get("target"):
                writer.writerow([
                    r["source_display"], r["target"], r["card_type"],
                    r["level"], r["word_class"], r["gender"],
                    r.get("topic", "Allgemein"),
                    r["flelex_word"], f"{r.get('freq_total', 0):.2f}"
                ])

    final_count = sum(1 for r in results if r.get("target"))
    print(f"\n=== Fertig ===")
    print(f"Total translated: {final_count}")
    print(f"Output: {OUTPUT_PATH}")

    # Stats
    by_level = {}
    for r in results:
        if r.get("target"):
            l = r.get("level", "?")
            by_level[l] = by_level.get(l, 0) + 1
    for l in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        print(f"  {l}: {by_level.get(l, 0)}")


if __name__ == "__main__":
    main()
