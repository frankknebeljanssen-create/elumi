#!/usr/bin/env python3
"""
Adds topic categories to already-translated FLELex entries using GPT.
Reads from gpt_translate_progress.json, adds 'topic' field, saves back.

Topics are school-relevant categories for a French learning app.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
PROGRESS_PATH = os.path.join(SCRIPT_DIR, "gpt_translate_progress.json")

API_KEY = ""
MODEL = "gpt-4o-mini"
BATCH_SIZE = 80  # Topics are simpler, can do larger batches

VALID_TOPICS = [
    "Begrüßung & Höflichkeit",
    "Familie & Freunde",
    "Schule & Bildung",
    "Essen & Trinken",
    "Wohnen & Haus",
    "Körper & Gesundheit",
    "Kleidung & Mode",
    "Tiere & Natur",
    "Stadt & Verkehr",
    "Reisen & Urlaub",
    "Freizeit & Hobbys",
    "Sport",
    "Medien & Technik",
    "Arbeit & Beruf",
    "Einkaufen & Geld",
    "Wetter & Jahreszeiten",
    "Zeit & Datum",
    "Farben & Formen",
    "Zahlen & Mengen",
    "Gefühle & Charakter",
    "Kommunikation",
    "Grammatik & Struktur",
    "Allgemein",
]


def load_api_key():
    global API_KEY
    plist_path = os.path.join(PROJECT_DIR, "FRDEVocabMVP", "OpenAIConfig.plist")
    if os.path.exists(plist_path):
        import plistlib
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)
            key = plist.get("OPENAI_API_KEY", "")
            if key and not key.startswith("REPLACE"):
                API_KEY = key
                return True
    API_KEY = os.environ.get("OPENAI_API_KEY", "")
    return bool(API_KEY)


def call_gpt(words):
    """Send batch of words to GPT for topic categorization."""
    word_list = "\n".join(f"{i+1}. {w['fr']} → {w['de']} ({w['wc']})" for i, w in enumerate(words))

    topics_str = "\n".join(f"- {t}" for t in VALID_TOPICS)

    prompt = f"""Ordne diese französisch-deutschen Vokabeln jeweils EINEM Thema zu.

Erlaubte Themen:
{topics_str}

Antworte NUR als JSON-Array mit Strings (ein Thema pro Wort, gleiche Reihenfolge):
["Thema1", "Thema2", ...]

Wörter:
{word_list}"""

    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "Du kategorisierst Vokabeln nach Schulthemen. Antworte nur mit einem JSON-Array."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.0,
        "max_tokens": 2000,
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
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"].strip()
            if content.startswith("```"):
                content = content.split("\n", 1)[1]
                content = content.rsplit("```", 1)[0]
            return json.loads(content)
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return None


def main():
    if not load_api_key():
        print("❌ No API key found")
        sys.exit(1)

    with open(PROGRESS_PATH, "r") as f:
        progress = json.load(f)

    print(f"=== Topic Categorizer ===")
    print(f"Total entries: {len(progress)}")

    # Find entries without topic
    needs_topic = [(k, v) for k, v in progress.items() if not v.get("topic")]
    print(f"Need topics: {len(needs_topic)}\n")

    if not needs_topic:
        print("All entries already have topics!")
        return

    batches = [needs_topic[i:i+BATCH_SIZE] for i in range(0, len(needs_topic), BATCH_SIZE)]

    for batch_idx, batch in enumerate(batches):
        words = [{"fr": v["source_display"], "de": v["target"], "wc": v.get("word_class", "")} for _, v in batch]
        print(f"Batch {batch_idx+1}/{len(batches)} ({len(batch)} words)...", end=" ", flush=True)

        topics = call_gpt(words)
        if topics and len(topics) == len(batch):
            for (key, _), topic in zip(batch, topics):
                if topic in VALID_TOPICS:
                    progress[key]["topic"] = topic
                else:
                    progress[key]["topic"] = "Allgemein"
            print(f"✅")
        else:
            print(f"⚠️ Mismatch ({len(topics) if topics else 0} vs {len(batch)}), skipping")

        # Save progress after each batch
        with open(PROGRESS_PATH, "w") as f:
            json.dump(progress, f, ensure_ascii=False, indent=2)

        time.sleep(0.3)

    # Stats
    topic_counts = {}
    for v in progress.values():
        t = v.get("topic", "?")
        topic_counts[t] = topic_counts.get(t, 0) + 1

    print(f"\n=== Themen-Statistik ===")
    for t, c in sorted(topic_counts.items(), key=lambda x: -x[1]):
        print(f"  {t}: {c}")

    print(f"\nFertig!")


if __name__ == "__main__":
    main()
