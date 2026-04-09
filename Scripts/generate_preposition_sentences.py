#!/usr/bin/env python3
"""
Generate short French sentences from verb+noun pairs, with a preposition/article as the blank word.
GPT creates a simple sentence, identifies which word to blank out (preposition, article, or short connector).

Usage: OPENAI_API_KEY=sk-... python3 generate_preposition_sentences.py
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
PAIRS_PATH = os.path.join(SCRIPT_DIR, "verb_noun_progress.json")
OUTPUT_PATH = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "FillBlankSentences.tsv")
PROGRESS_PATH = os.path.join(SCRIPT_DIR, "fill_blank_progress.json")

API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODEL = "gpt-4o-mini"
BATCH_SIZE = 30


def load_pairs():
    with open(PAIRS_PATH, "r", encoding="utf-8") as f:
        progress = json.load(f)

    pairs = []
    for verb_fr, data in progress.items():
        verb_de = data.get("verb_de", "")
        for noun in data.get("matched", []):
            pairs.append({
                "verb_fr": verb_fr,
                "verb_de": verb_de,
                "noun_fr": noun["fr"],
                "noun_de": noun["de"],
            })
    return pairs


def load_progress():
    if os.path.exists(PROGRESS_PATH):
        with open(PROGRESS_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"done_keys": [], "sentences": []}


def save_progress(progress):
    with open(PROGRESS_PATH, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def call_gpt(pair_batch):
    pair_list = "\n".join(
        f'{i+1}. {p["verb_fr"]} + {p["noun_fr"]} ({p["verb_de"]} + {p["noun_de"]})'
        for i, p in enumerate(pair_batch)
    )

    prompt = f"""Erstelle für jedes Verb+Nomen Paar einen kurzen, einfachen französischen Satz (A1-B1 Niveau).
Dann markiere EIN Wort im Satz als Lücke — bevorzugt eine Präposition, einen Artikel oder ein kurzes Verbindungswort.

Regeln:
- Satz max. 8 Wörter, einfache Grammatik
- Das Lückenwort muss ein kurzes Wort sein (à, de, du, dans, sur, avec, pour, le, la, les, un, une, en, au, aux, et, ou, ne, pas)
- Gib auch 3 falsche Alternativen an (andere Präpositionen/Artikel)
- Gib auch die deutsche Übersetzung des Satzes an

Antworte NUR als JSON-Array:
[{{
  "sentence_fr": "Je vais à l'école.",
  "sentence_de": "Ich gehe in die Schule.",
  "blank_word": "à",
  "distractors": ["de", "sur", "avec"],
  "verb_fr": "aller",
  "noun_fr": "l'école"
}}]

Paare:
{pair_list}"""

    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "Du erstellst einfache französische Lückentexte für ein Sprachlern-Quiz. Kurze Sätze, A1-B1 Niveau."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.3,
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

    all_pairs = load_pairs()
    print(f"📚 Loaded {len(all_pairs)} verb+noun pairs")

    # Sample ~1500 diverse pairs (not all 6550 — too many)
    import random
    random.seed(42)
    # Pick pairs with common verbs first
    common_verbs = ["aller", "faire", "avoir", "être", "prendre", "mettre", "voir",
                    "donner", "manger", "boire", "lire", "écrire", "ouvrir", "fermer",
                    "acheter", "vendre", "chercher", "trouver", "porter", "laver",
                    "nettoyer", "couper", "cuisiner", "conduire", "jouer", "regarder",
                    "écouter", "parler", "envoyer", "recevoir", "payer", "choisir",
                    "préparer", "utiliser", "construire", "réparer", "perdre", "gagner"]

    priority_pairs = [p for p in all_pairs if p["verb_fr"] in common_verbs]
    other_pairs = [p for p in all_pairs if p["verb_fr"] not in common_verbs]
    random.shuffle(other_pairs)

    selected = priority_pairs + other_pairs[:max(0, 1200 - len(priority_pairs))]
    random.shuffle(selected)
    print(f"📦 Selected {len(selected)} pairs for sentence generation")

    progress = load_progress()
    done_keys = set(progress["done_keys"])
    remaining = [p for p in selected if f'{p["verb_fr"]}|{p["noun_fr"]}' not in done_keys]
    print(f"✅ Already done: {len(done_keys)}, remaining: {len(remaining)}")

    total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_idx in range(total_batches):
        batch = remaining[batch_idx * BATCH_SIZE:(batch_idx + 1) * BATCH_SIZE]
        print(f"\n📦 Batch {batch_idx + 1}/{total_batches} ({len(batch)} pairs)...")

        result = call_gpt(batch)
        if not result:
            print("  ⚠️ Retrying...")
            time.sleep(3)
            result = call_gpt(batch)
            if not result:
                print("  ❌ Skipping batch")
                continue

        valid = 0
        for entry in result:
            sentence = entry.get("sentence_fr", "")
            blank = entry.get("blank_word", "")
            if sentence and blank and blank.lower() in sentence.lower():
                progress["sentences"].append(entry)
                valid += 1
            key = f'{entry.get("verb_fr", "")}|{entry.get("noun_fr", "")}'
            progress["done_keys"].append(key)

        print(f"  ✅ {valid}/{len(result)} valid sentences")
        save_progress(progress)
        time.sleep(0.5)

    # Write TSV
    print(f"\n📝 Writing {OUTPUT_PATH}...")
    sentences = progress["sentences"]
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("sentence_fr\tsentence_de\tblank_word\tdistractors\tverb_fr\tnoun_fr\n")
        for s in sentences:
            distractors = ",".join(s.get("distractors", []))
            f.write(f'{s["sentence_fr"]}\t{s["sentence_de"]}\t{s["blank_word"]}\t{distractors}\t{s.get("verb_fr","")}\t{s.get("noun_fr","")}\n')

    print(f"✅ Done! {len(sentences)} sentences written")


if __name__ == "__main__":
    main()
