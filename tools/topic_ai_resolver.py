#!/usr/bin/env python3
"""
KI-basierte Themen-Neuzuordnung für den kaputten "Tiere"-Batch.

**Hintergrund**
`entries.topic = 'Tiere'` betrifft 3.814 Zeilen, aber nur eine kleine
Minderheit davon sind tatsächlich Tiervokabeln — der Rest ist offenbar
bei einem alphabetischen Import pauschal auf "Tiere" gesetzt worden
("la datation" → "Datierung", "l'hospitalité" → "Gastfreundschaft").
Das Thema ist eine direkt wählbare Lernkategorie in der App
(`UnifiedListCategoryPicker`) — Nutzer, die "Tiere" zum Üben wählen,
bekämen fast nur themenfremde Wörter.

**Zweiteiliger Ablauf** (analog zu `gender_ai_resolver.py`):
  1. `resolve`  — fragt Claude batchweise nach dem passenden Thema aus
     der bestehenden Themenliste, speichert inkrementell in eine
     Prüfdatei (`topic_ai_resolutions.json`). Kein DB-Schreibzugriff.
  2. `apply`    — liest die Prüfdatei und schreibt die neuen Themen in
     EINEM Durchgang in die DB. Getrennt von Schritt 1, damit die
     Ergebnisse vor dem Schreiben kontrollierbar sind und die 62-MB-DB
     nur einmal pro Lauf eine neue Git-Kopie erzeugt.

**Usage**:
    export ANTHROPIC_API_KEY="sk-ant-..."
    python3 tools/topic_ai_resolver.py resolve
    python3 tools/topic_ai_resolver.py apply           # nach Kontrolle
    python3 tools/topic_ai_resolver.py apply --dry-run # nur anzeigen

**Kosten (Haiku-Tarif)**: ~3.800 Wörter à 40/Batch ≈ 95 Calls, < 2 $.
"""

import argparse
import json
import os
import shutil
import sqlite3
import sys
import time
from datetime import datetime
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
DB_PATH = REPO_ROOT / "Elumi" / "ElumiMasterLexicon.sqlite"
RESOLUTIONS_PATH = REPO_ROOT / "tools" / "topic_ai_resolutions.json"
BATCH_SIZE = 40
MODEL = "claude-haiku-4-5"
MAX_BATCHES = 200

SOURCE_TOPIC = "Tiere"
CONFIDENCE_APPLY_CUTOFF = 0.6  # darunter: manuelle Prüfung statt Auto-Apply

# ---------------------------------------------------------------------------
# Themenliste — feste Taxonomie, die die App schon kennt
# ---------------------------------------------------------------------------

def fetch_valid_topics(conn):
    """Alle Themen außer der kaputten Quelle, plus 'Tiere' selbst als
    gültige Wahl für tatsächliche Tiervokabeln."""
    rows = conn.execute(
        "SELECT DISTINCT topic FROM entries WHERE topic IS NOT NULL AND topic != ''"
    ).fetchall()
    topics = sorted({r[0] for r in rows})
    return topics


# ---------------------------------------------------------------------------
# Kandidaten sammeln
# ---------------------------------------------------------------------------

def fetch_candidates(conn):
    rows = conn.execute(
        """SELECT entry_id, lemma_fr, lemma_de, word_class
           FROM entries WHERE topic = ? ORDER BY entry_id""",
        (SOURCE_TOPIC,),
    ).fetchall()
    return [
        {"entry_id": r[0], "lemma_fr": r[1], "lemma_de": r[2], "word_class": r[3]}
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Claude-Batch
# ---------------------------------------------------------------------------

def build_system_prompt(valid_topics):
    topic_list = "\n".join(f"- {t}" for t in valid_topics)
    return f"""Du ordnest französisch-deutsche Vokabelpaare einem Lernthema zu.

Wähle für jedes Wort GENAU EIN Thema aus dieser festen Liste (keine
neuen Themen erfinden, exakte Schreibweise übernehmen):

{topic_list}

Regeln:
- Ist das Wort wirklich ein Tier oder eng mit Tieren verbunden (z. B.
  "Fell", "Käfig", "Tierarzt"), wähle "Tiere".
- Sonst wähle das inhaltlich naheliegendste Thema aus der Liste.
- Gibt es keine klare Zuordnung, wähle "Allgemein" und senke die
  Confidence auf 0.5.
- Gib NUR valides JSON zurück, kein Fließtext.
- Format: [{{"word": "X", "topic": "Y", "confidence": 0.0-1.0}}]
- Gib die Liste IN DERSELBEN REIHENFOLGE wie die Eingabe zurück."""


def query_batch(client, system_prompt, entries):
    user_message = "Ordne diesen Wörtern ein Thema zu:\n\n"
    for i, e in enumerate(entries, 1):
        wc = e.get("word_class") or "?"
        user_message += f"{i}. {e['lemma_fr']} = {e['lemma_de']}  [{wc}]\n"
    user_message += "\nAntworte mit JSON-Array."

    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}],
    )
    text = response.content[0].text.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"JSON-Parse-Fehler: {e}")
        print(f"Antwort war:\n{text}")
        return []


# ---------------------------------------------------------------------------
# Prüfdatei
# ---------------------------------------------------------------------------

def load_resolutions():
    if not RESOLUTIONS_PATH.exists():
        return {}
    try:
        return json.loads(RESOLUTIONS_PATH.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"Warnung: Prüfdatei korrupt ({e}), starte frisch.")
        return {}


def save_resolutions(data):
    RESOLUTIONS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


# ---------------------------------------------------------------------------
# Schritt 1: resolve
# ---------------------------------------------------------------------------

def cmd_resolve(args):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("FEHLER: Umgebungsvariable ANTHROPIC_API_KEY fehlt.")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    client = Anthropic(api_key=api_key)

    valid_topics = fetch_valid_topics(conn)
    system_prompt = build_system_prompt(valid_topics)
    print(f"Gültige Themen ({len(valid_topics)}): {', '.join(valid_topics)}\n")

    candidates = fetch_candidates(conn)
    print(f"Kandidaten mit Thema '{SOURCE_TOPIC}': {len(candidates)}")

    existing = load_resolutions()
    print(f"Bereits aufgelöst: {len(existing)}")

    pending = [c for c in candidates if str(c["entry_id"]) not in existing]
    print(f"Noch offen: {len(pending)}\n")

    if not pending:
        print("Nichts zu tun — alle Kandidaten bereits aufgelöst.")
        return

    processed = 0
    for batch_idx in range(0, len(pending), BATCH_SIZE):
        if batch_idx // BATCH_SIZE >= MAX_BATCHES:
            print(f"MAX_BATCHES ({MAX_BATCHES}) erreicht — breche ab.")
            break

        batch = pending[batch_idx : batch_idx + BATCH_SIZE]
        print(f"Batch {batch_idx // BATCH_SIZE + 1}: {len(batch)} Wörter "
              f"(bisher {processed}/{len(pending)})")

        try:
            answers = query_batch(client, system_prompt, batch)
        except Exception as e:
            print(f"API-Fehler: {e} — pausiere 20 s und mache weiter.")
            time.sleep(20)
            continue

        for entry, answer in zip(batch, answers):
            topic = str(answer.get("topic", "")).strip()
            conf = float(answer.get("confidence", 0.0))
            if topic not in valid_topics:
                # Halluziniertes Thema — nicht übernehmen, für manuelle
                # Prüfung mit confidence 0 markieren statt zu raten.
                topic = ""
                conf = 0.0
            existing[str(entry["entry_id"])] = {
                "lemma_fr": entry["lemma_fr"],
                "lemma_de": entry["lemma_de"],
                "old_topic": SOURCE_TOPIC,
                "new_topic": topic,
                "confidence": round(conf, 3),
            }

        save_resolutions(existing)
        processed += len(batch)
        time.sleep(1.5)

    print(f"\nFertig. Aufgelöst gesamt: {len(existing)}")
    print(f"Prüfdatei: {RESOLUTIONS_PATH}")
    print("\nNächster Schritt: `python3 tools/topic_ai_resolver.py apply --dry-run`")


# ---------------------------------------------------------------------------
# Schritt 2: apply
# ---------------------------------------------------------------------------

def cmd_apply(args):
    resolutions = load_resolutions()
    if not resolutions:
        print("Keine Prüfdatei gefunden — erst `resolve` laufen lassen.")
        sys.exit(1)

    stays_animal = []
    reclassified = []
    low_confidence = []
    unresolved = []

    for entry_id_str, r in resolutions.items():
        eid = int(entry_id_str)
        new_topic = r.get("new_topic", "")
        conf = r.get("confidence", 0.0)
        if not new_topic:
            unresolved.append((eid, r))
        elif new_topic == SOURCE_TOPIC:
            stays_animal.append((eid, r))
        elif conf < CONFIDENCE_APPLY_CUTOFF:
            low_confidence.append((eid, r))
        else:
            reclassified.append((eid, r))

    print(f"Auflösungen gesamt:        {len(resolutions)}")
    print(f"  bleibt 'Tiere' (echt):   {len(stays_animal)}")
    print(f"  wird umgestellt:         {len(reclassified)}")
    print(f"  niedrige Confidence:     {len(low_confidence)} (nicht automatisch übernommen)")
    print(f"  nicht auflösbar:         {len(unresolved)} (nicht automatisch übernommen)")

    if low_confidence:
        print(f"\n--- Niedrige Confidence (< {CONFIDENCE_APPLY_CUTOFF}), zur Kontrolle ---")
        for eid, r in low_confidence[:20]:
            print(f"  {eid:6d} | {r['lemma_fr']:28s} | {r['lemma_de']:28s} -> {r['new_topic']} ({r['confidence']})")

    if unresolved:
        print(f"\n--- Nicht auflösbar, zur manuellen Prüfung ---")
        for eid, r in unresolved[:20]:
            print(f"  {eid:6d} | {r['lemma_fr']:28s} | {r['lemma_de']}")

    if args.dry_run:
        print("\n--dry-run: nichts geschrieben.")
        print("\nBeispiele der geplanten Umstellung:")
        for eid, r in reclassified[:15]:
            print(f"  {eid:6d} | {r['lemma_fr']:28s} | {r['lemma_de']:28s} -> {r['new_topic']} ({r['confidence']})")
        return

    if not reclassified:
        print("\nNichts zum Anwenden (0 Zeilen über der Confidence-Schwelle).")
        return

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"/tmp/ElumiMasterLexicon.before_topic_apply_{stamp}.sqlite"
    shutil.copy2(DB_PATH, backup)
    print(f"\nBackup: {backup}")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    for eid, r in reclassified:
        cur.execute("UPDATE entries SET topic=? WHERE entry_id=?", (r["new_topic"], eid))
    conn.commit()

    integrity = cur.execute("PRAGMA integrity_check").fetchone()[0]
    remaining_tiere = cur.execute(
        "SELECT COUNT(*) FROM entries WHERE topic=?", (SOURCE_TOPIC,)
    ).fetchone()[0]
    conn.close()

    print(f"\n{len(reclassified)} Zeilen umgestellt.")
    print(f"Integrität: {integrity}")
    print(f"'Tiere' verbleibend (echte + ungeklärte): {remaining_tiere}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("resolve", help="KI-Klassifizierung laufen lassen, Ergebnis in Prüfdatei")

    apply_parser = sub.add_parser("apply", help="Prüfdatei in die DB schreiben")
    apply_parser.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()
    if args.command == "resolve":
        cmd_resolve(args)
    elif args.command == "apply":
        cmd_apply(args)


if __name__ == "__main__":
    main()
