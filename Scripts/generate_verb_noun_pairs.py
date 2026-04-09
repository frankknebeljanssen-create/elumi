#!/usr/bin/env python3
"""
Generate verb+noun combination pairs using GPT.
For each verb, GPT suggests 3-5 nouns that commonly go with it.
Only nouns that exist in the StandardpaketGPT.tsv are kept.

Usage: OPENAI_API_KEY=sk-... python3 generate_verb_noun_pairs.py
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
TSV_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "StandardpaketGPT.tsv")
OUTPUT_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "VerbNounPairs.tsv")
PROGRESS_PATH = os.path.join(SCRIPT_DIR, "verb_noun_progress.json")

API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODEL = "gpt-4o-mini"
BATCH_SIZE = 40


def load_vocabulary():
    """Load verbs and nouns from StandardpaketGPT.tsv"""
    verbs = []  # (fr_verb, de_verb)
    nouns_fr = {}  # fr_noun_lower -> (fr_display, de_display)
    nouns_de = {}  # de_noun_lower -> (fr_display, de_display)

    with open(TSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)
        for row in reader:
            if len(row) < 5:
                continue
            fr, de, card_type, level, word_class = row[0], row[1], row[2], row[3], row[4]
            if word_class == "verb":
                verbs.append((fr.strip(), de.strip()))
            elif word_class == "noun":
                fr_clean = fr.strip().lower()
                de_clean = de.strip().lower()
                nouns_fr[fr_clean] = (fr.strip(), de.strip())
                # Also index without article
                for art in ["le ", "la ", "l'", "les ", "un ", "une "]:
                    if fr_clean.startswith(art):
                        nouns_fr[fr_clean[len(art):].strip()] = (fr.strip(), de.strip())
                for art in ["der ", "die ", "das ", "ein ", "eine "]:
                    if de_clean.startswith(art):
                        nouns_de[de_clean[len(art):].strip()] = (fr.strip(), de.strip())
                nouns_de[de_clean] = (fr.strip(), de.strip())

    return verbs, nouns_fr, nouns_de


def load_progress():
    if os.path.exists(PROGRESS_PATH):
        with open(PROGRESS_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_progress(progress):
    with open(PROGRESS_PATH, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def call_gpt(verb_batch):
    """Send a batch of verbs to GPT, get back noun suggestions."""
    verb_list = "\n".join(
        f"{i+1}. {fr} ({de})"
        for i, (fr, de) in enumerate(verb_batch)
    )

    prompt = f"""Für jedes dieser französischen Verben: Nenne 3-5 Nomen die häufig mit diesem Verb verwendet werden.

Regeln:
- Gib die Nomen auf FRANZÖSISCH an (ohne Artikel)
- Nur die gebräuchlichsten, alltäglichen Kombinationen
- Beispiel: "manger" → ["pain", "pomme", "gâteau", "soupe", "fromage"]
- Beispiel: "écrire" → ["lettre", "email", "texte", "livre", "message"]
- Beispiel: "nettoyer" → ["fenêtre", "maison", "table", "voiture"]
- Keine abstrakten Konzepte, nur konkrete Nomen

Antworte NUR als JSON-Array:
[{{"verb_fr": "manger", "verb_de": "essen", "nouns": ["pain", "pomme", "gâteau"]}}]

Verben:
{verb_list}"""

    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "Du generierst Verb+Nomen Kombinationen für ein Sprachlern-Quiz. Nur alltägliche, häufige Kombinationen."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.2,
        "max_tokens": 8000,
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
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"].strip()
            if content.startswith("```"):
                content = content.split("\n", 1)[1]
                content = content.rsplit("```", 1)[0]
            return json.loads(content)
    except (urllib.error.URLError, json.JSONDecodeError, KeyError, IndexError) as e:
        print(f"  ❌ API error: {e}")
        return None


def main():
    if not API_KEY:
        print("❌ Set OPENAI_API_KEY environment variable")
        sys.exit(1)

    verbs, nouns_fr, nouns_de = load_vocabulary()
    print(f"📚 Loaded {len(verbs)} verbs, {len(nouns_fr)} French nouns, {len(nouns_de)} German nouns")

    progress = load_progress()
    done_verbs = set(progress.keys())
    remaining = [(fr, de) for fr, de in verbs if fr not in done_verbs]
    print(f"✅ Already done: {len(done_verbs)}, remaining: {len(remaining)}")

    # Process in batches
    total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_idx in range(total_batches):
        batch = remaining[batch_idx * BATCH_SIZE:(batch_idx + 1) * BATCH_SIZE]
        print(f"\n📦 Batch {batch_idx + 1}/{total_batches} ({len(batch)} verbs)...")

        result = call_gpt(batch)
        if not result:
            print("  ⚠️ Skipping batch due to error, retrying in 5s...")
            time.sleep(5)
            result = call_gpt(batch)
            if not result:
                print("  ❌ Skipping batch permanently")
                continue

        matched_count = 0
        for entry in result:
            verb_fr = entry.get("verb_fr", "")
            verb_de = entry.get("verb_de", "")
            suggested_nouns = entry.get("nouns", [])

            # Match suggested nouns against our vocabulary
            matched_nouns = []
            for noun in suggested_nouns:
                noun_lower = noun.strip().lower()
                if noun_lower in nouns_fr:
                    fr_noun, de_noun = nouns_fr[noun_lower]
                    matched_nouns.append({"fr": fr_noun, "de": de_noun})

            progress[verb_fr] = {
                "verb_fr": verb_fr,
                "verb_de": verb_de,
                "suggested": suggested_nouns,
                "matched": matched_nouns,
            }
            matched_count += len(matched_nouns)

        print(f"  ✅ {len(result)} verbs processed, {matched_count} noun matches found")
        save_progress(progress)
        time.sleep(0.5)  # Rate limit

    # Write final TSV
    print(f"\n📝 Writing {OUTPUT_PATH}...")
    pairs = []
    for verb_fr, data in progress.items():
        for noun in data.get("matched", []):
            pairs.append((
                data["verb_fr"],
                data["verb_de"],
                noun["fr"],
                noun["de"],
            ))

    pairs.sort(key=lambda p: (p[0].lower(), p[2].lower()))

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("verb_fr\tverb_de\tnoun_fr\tnoun_de\n")
        for verb_fr, verb_de, noun_fr, noun_de in pairs:
            f.write(f"{verb_fr}\t{verb_de}\t{noun_fr}\t{noun_de}\n")

    print(f"✅ Done! {len(pairs)} verb+noun pairs written")

    # Stats
    verbs_with_matches = sum(1 for d in progress.values() if d.get("matched"))
    print(f"📊 {verbs_with_matches}/{len(progress)} verbs have matched nouns")


if __name__ == "__main__":
    main()
