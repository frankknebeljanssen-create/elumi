#!/usr/bin/env python3
"""
Phase-2-Pipeline: KI-basiertes Genus-Fallback für französische Nomen.

**Ziel**
Für die Residual-Nomen, bei denen die Swift-Pipeline (Artikel-Parse +
DB-Plural-Lookup + Endungs-Heuristik) kein Genus bestimmen konnte, bzw.
nur mit niedriger Confidence (< 0.85), rufen wir Claude Haiku in Batches
und generieren eine Override-Datei im App-Bundle-Pfad.

**Output**: `FRDEVocabMVP/gender_ai_overrides.json` — wird vom
`StandardVocabularyLoader` beim App-Start automatisch konsumiert.

**Usage**:
    export ANTHROPIC_API_KEY="sk-ant-..."
    python3 tools/gender_ai_resolver.py

**Inkrementelle Läufe**: Das Skript liest bestehende Overrides und
überspringt bereits vorhandene Keys. So lassen sich Residuals in
mehreren Sitzungen abarbeiten.

**Kosten (Haiku-Tarif Stand April 2026)**: ~$0.80 pro 1000 Einträge,
also ca. 5 $ für alle ~6000 genuslosen Nomen.
"""

import json
import os
import sqlite3
import sys
import time
from pathlib import Path

try:
    from anthropic import Anthropic
except ImportError:
    print("FEHLER: `anthropic` Python-Paket fehlt.")
    print("Installiere mit: pip install anthropic")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / "FRDEVocabMVP" / "FRDEMasterLexicon.sqlite"
OVERRIDES_PATH = REPO_ROOT / "FRDEVocabMVP" / "gender_ai_overrides.json"
BATCH_SIZE = 40  # 40 Wörter pro API-Call — ausreichend Kontext + schnell
MODEL = "claude-haiku-4-5"
MAX_BATCHES = 200  # Kosten-Safety-Limit

CONFIDENCE_CUTOFF = 0.85  # unter diesem Wert gilt Heuristik als unsicher

# ---------------------------------------------------------------------------
# SQLite-Residuals-Sammlung
# ---------------------------------------------------------------------------

def fetch_residual_nouns(conn):
    """
    Liefert alle Nomen-Lemmas, bei denen:
      • gender_fr leer ist UND
      • der Core-Wortteil entweder Apostroph-Artikel ('l'…') oder
        kein Artikel hat (Singular-Lookup mit Artikel fällt aus)

    Der Core wird als Lookup-Key zurückgegeben — das ist, was der
    Swift-Loader später in der Overrides-Map sucht.
    """
    sql = """
        SELECT lemma_fr, lemma_de
        FROM entries
        WHERE word_class='noun'
          AND (gender_fr IS NULL OR gender_fr='')
          AND (lemma_fr LIKE 'l''%' OR lemma_fr LIKE 'l' || char(8217) || '%'
               OR (lemma_fr NOT LIKE 'le %' AND lemma_fr NOT LIKE 'la %'
                   AND lemma_fr NOT LIKE 'les %' AND lemma_fr NOT LIKE 'un %'
                   AND lemma_fr NOT LIKE 'une %' AND lemma_fr NOT LIKE 'des %'))
        ORDER BY frequency_rank ASC
    """
    rows = conn.execute(sql).fetchall()
    residuals = []
    for lemma_fr, lemma_de in rows:
        core = extract_core(lemma_fr)
        if core:
            residuals.append({
                "core": core.lower(),
                "lemma_fr_raw": lemma_fr,
                "lemma_de": lemma_de,
            })
    # Deduplicate auf Core-Ebene
    seen = set()
    deduped = []
    for r in residuals:
        if r["core"] in seen:
            continue
        seen.add(r["core"])
        deduped.append(r)
    return deduped


def extract_core(lemma_fr):
    """Entfernt Artikel-Präfix und nimmt das erste Wort."""
    s = lemma_fr.strip()
    # Apostroph-Artikel
    for prefix in ["l'", "l\u2019", "L'", "L\u2019", "d'", "d\u2019"]:
        if s.lower().startswith(prefix.lower()):
            s = s[len(prefix):]
            break
    # Space-Artikel
    for prefix in ["le ", "la ", "les ", "un ", "une ", "des ", "Le ", "La "]:
        if s.lower().startswith(prefix.lower()):
            s = s[len(prefix):]
            break
    s = s.strip()
    # Erstes Wort
    if " " in s:
        s = s.split(" ", 1)[0]
    return s


# ---------------------------------------------------------------------------
# Claude-Batch
# ---------------------------------------------------------------------------

BATCH_SYSTEM_PROMPT = """Du bist ein französischer Sprachexperte. Bestimme für jede gegebene Nomenform das grammatikalische Genus (m oder f) plus Confidence (0.0 bis 1.0).

Regeln:
- Gib NUR valides JSON zurück, kein Fließtext.
- Format: [{"word": "X", "gender": "m"|"f", "confidence": 0.0-1.0}]
- Wenn das Wort mehrere Genus haben kann, nimm das häufigste und senke Confidence auf 0.6.
- Wenn du dir unsicher bist, senke die Confidence.
- Gib die Liste IN DERSELBEN REIHENFOLGE wie die Eingabe zurück.
- Benutze keine Artikel in der Ausgabe, nur das Wort selbst."""


def query_batch(client, words):
    """Ein Claude-Call für bis zu BATCH_SIZE Wörter."""
    user_message = "Bestimme Genus für diese französischen Nomen:\n\n"
    for i, w in enumerate(words, 1):
        user_message += f"{i}. {w}\n"
    user_message += "\nAntworte mit JSON-Array."

    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        system=BATCH_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )
    text = response.content[0].text.strip()
    # Bei Bedarf Markdown-Code-Fencing entfernen
    if text.startswith("```"):
        text = text.split("```", 2)[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"JSON-Parse-Fehler: {e}")
        print(f"Antwort war:\n{text}")
        return []
    return parsed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_existing_overrides():
    if not OVERRIDES_PATH.exists():
        return {}
    try:
        return json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"Warnung: bestehende Overrides-Datei korrupt ({e}), starte frisch.")
        return {}


def save_overrides(data):
    OVERRIDES_PATH.parent.mkdir(parents=True, exist_ok=True)
    OVERRIDES_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def main():
    if not DB_PATH.exists():
        print(f"FEHLER: DB nicht gefunden unter {DB_PATH}")
        sys.exit(1)

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("FEHLER: Umgebungsvariable ANTHROPIC_API_KEY fehlt.")
        sys.exit(1)

    client = Anthropic(api_key=api_key)
    conn = sqlite3.connect(DB_PATH)

    existing = load_existing_overrides()
    print(f"Bestehende Overrides: {len(existing)}")

    residuals = fetch_residual_nouns(conn)
    print(f"Residuals aus DB: {len(residuals)}")

    # Bereits bearbeitete überspringen
    pending = [r for r in residuals if r["core"] not in existing]
    print(f"Noch zu bearbeiten: {len(pending)}")

    if not pending:
        print("Alle Residuals bereits abgedeckt — nichts zu tun.")
        return

    total_cost_words = 0
    for batch_idx in range(0, len(pending), BATCH_SIZE):
        if batch_idx // BATCH_SIZE >= MAX_BATCHES:
            print(f"MAX_BATCHES ({MAX_BATCHES}) erreicht — breche ab. Overrides gespeichert.")
            break

        batch = pending[batch_idx : batch_idx + BATCH_SIZE]
        words = [r["core"] for r in batch]
        print(f"Batch {batch_idx // BATCH_SIZE + 1}: {len(words)} Wörter (total bisher: {total_cost_words})")

        try:
            answers = query_batch(client, words)
        except Exception as e:
            print(f"API-Fehler: {e} — pausiere 20 s und mache weiter.")
            time.sleep(20)
            continue

        # Antworten zurückmappen.
        for r, ans in zip(batch, answers):
            gender = str(ans.get("gender", "")).lower()
            conf = float(ans.get("confidence", 0.0))
            if gender not in ("m", "f"):
                continue
            existing[r["core"]] = {
                "gender": gender,
                "confidence": round(conf, 3),
            }

        # Nach jedem Batch speichern — falls was abstürzt, haben wir den
        # bisherigen Stand schon auf Platte.
        save_overrides(existing)
        total_cost_words += len(words)

        # Rate-Limit-freundliche Pause
        time.sleep(1.5)

    print(f"\nFertig. Overrides gesamt: {len(existing)}")
    print(f"Datei: {OVERRIDES_PATH}")
    print("\nNächster Schritt: `gender_ai_overrides.json` muss im Xcode-")
    print("Projekt als Resource (Copy-Bundle-Resources) registriert sein.")
    print("Falls noch nicht, einmalig: Xcode → FRDEVocabMVP Target → ")
    print("Build Phases → Copy Bundle Resources → + → Datei auswählen.")


if __name__ == "__main__":
    main()
