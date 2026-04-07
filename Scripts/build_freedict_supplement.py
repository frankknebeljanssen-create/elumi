#!/usr/bin/env python3
import io
import re
import sqlite3
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
import xml.etree.ElementTree as ET

VARIANT_SEPARATOR = "\x1f"
NS = {"tei": "http://www.tei-c.org/ns/1.0"}
DEFAULT_REVERSE_ARCHIVE = Path("/tmp/freedict-deu-fra.src.tar.xz")


def cleaned_quiz_display_text(text: str) -> str:
    text = re.sub(r"\[[^\[\]]+\]", " ", text)
    text = re.sub(r"\/[^\/]+\/", " ", text)
    text = re.sub(r"(?iu)^\s*\[[^\]]*$", "", text)
    text = re.sub(r"(?iu)(^|\s)\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ'’\-\.\,]+\b", " ", text)
    text = re.sub(r"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+\s+", "", text)
    text = re.sub(r"(?iu)\s+\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$", "", text)
    text = re.sub(r"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$", "", text)
    text = re.sub(r"(?iu)^\s*[\[/][^\s]+\s+", "", text)
    text = re.sub(r"(?iu)^\s*[^\s]*[ˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ][^\s]*\s+", "", text)
    text = re.sub(r"(?u)^\s*[\[\]/]+|[\[\]/]+\s*$", "", text)
    text = re.sub(r"(?u)[*†‡•●▪◦※§]+", " ", text)
    text = re.sub(r"(?u)(^|\s)[~^_#]+(?=\s|$)", " ", text)
    text = re.sub(r"(?u)(^|\s)['’`]+(?=\w)", r"\1", text)
    text = re.sub(r"(?u)^['’`]+", "", text)
    text = re.sub(r"(?u)['’`]+$", "", text)
    text = re.sub(r"(?u)(^|\s)[^\w'’\-]+(?=\s|$)", " ", text)
    text = re.sub(r"(?u)^[^\w]+|[^\w]+$", "", text)
    text = re.sub(r" +", " ", text)
    return text.strip()


def restoring_french_elisions(text: str) -> str:
    cleaned = cleaned_quiz_display_text(text)
    if not cleaned:
        return cleaned
    apostrophe_vowels = "aeiouyhàâäæéèêëîïôöœùûü"
    cleaned = re.sub(rf"(?iu)\b([cdjlmnst])\s+(?=[{apostrophe_vowels}])", r"\1’", cleaned)
    cleaned = re.sub(rf"(?iu)\b(qu|jusqu|lorsqu|puisqu)\s+(?=[{apostrophe_vowels}])", r"\1’", cleaned)
    return cleaned


def normalized_lookup_text(text: str) -> str:
    import unicodedata

    folded = cleaned_quiz_display_text(text)
    folded = unicodedata.normalize("NFD", folded)
    folded = "".join(ch for ch in folded if unicodedata.category(ch) != "Mn")
    folded = folded.lower()
    folded = re.sub(r"[^a-z0-9 ]+", " ", folded)
    folded = re.sub(r" +", " ", folded)
    return folded.strip()


def compact_lookup_key(text: str) -> str:
    return normalized_lookup_text(text).replace(" ", "")


def should_display_french_question_mark(original: str, cleaned: str) -> bool:
    normalized_words = normalized_lookup_text(cleaned).split()
    if not normalized_words:
        return "?" in original
    first_word = normalized_words[0]
    first_two_words = " ".join(normalized_words[:2])
    first_three_words = " ".join(normalized_words[:3])
    single_word_question_starts = {
        "comment", "ou", "où", "pourquoi", "quand", "combien",
        "quel", "quelle", "quels", "quelles", "qui", "que",
    }
    multi_word_question_starts = {
        "puis je", "pouvez vous", "est ce", "est ce que", "est ce qu",
        "ou est", "où est", "ou sont", "où sont",
        "ou habites", "où habites", "ou puis", "où puis",
        "combien de temps", "quelle heure",
    }
    if (
        first_word in single_word_question_starts
        or first_two_words in multi_word_question_starts
        or first_three_words in multi_word_question_starts
    ):
        return True
    if re.search(r"(?iu)\b(?:est|faut|peut|doit|va|vient|habites|avez|pouvez|souhaitez)\s+(?:t\s+)?(?:il|elle|on|tu|vous|nous|je)\b", cleaned):
        return True
    if "?" in original:
        return len(normalized_words) > 1
    return False


def source_display_text(text: str) -> str:
    restored = restoring_french_elisions(text)
    if not restored:
        return restored
    if should_display_french_question_mark(text, restored):
        restored = re.sub(r"\s*\?$", "", restored).strip()
        return restored + " ?"
    return re.sub(r"\s*\?$", "", restored).strip()


def normalized_gender(raw_value: str) -> Optional[str]:
    value = (raw_value or "").strip().lower()
    if not value:
        return None
    if value.startswith("masc"):
        return "masculine"
    if value.startswith("fem"):
        return "feminine"
    if value.startswith("neut"):
        return "neuter"
    if value.startswith("pl"):
        return "plural"
    return None


def suggested_french_article(gender: Optional[str]) -> Optional[str]:
    return {
        "masculine": "le",
        "feminine": "la",
        "plural": "les",
    }.get(gender)


def suggested_german_article(gender: Optional[str]) -> Optional[str]:
    return {
        "masculine": "der",
        "feminine": "die",
        "neuter": "das",
        "plural": "die",
    }.get(gender)


def deduplicated_lookup_variants(candidates):
    seen = set()
    result = []
    for candidate in candidates:
        normalized = normalized_lookup_text(candidate)
        if normalized and normalized not in seen:
            seen.add(normalized)
            result.append(normalized)
    return result


def deduplicated_compact_lookup_variants(candidates):
    seen = set()
    result = []
    for candidate in candidates:
        compact = compact_lookup_key(candidate)
        if compact and compact not in seen:
            seen.add(compact)
            result.append(compact)
    return result


def french_lookup_candidates(text: str):
    canonical = source_display_text(text)
    apostrophe_spaces = canonical.replace("’", " ").replace("'", " ")
    apostrophe_removed = canonical.replace("’", "").replace("'", "")
    return [text, cleaned_quiz_display_text(text), restoring_french_elisions(text), canonical, apostrophe_spaces, apostrophe_removed]


def german_lookup_candidates(text: str):
    return [text, cleaned_quiz_display_text(text)]


def leading_german_article(text: str):
    german_article_hints = {
        "der", "die", "das", "ein", "eine", "einer", "einem", "einen", "den", "dem", "des", "kein", "keine"
    }
    words = normalized_lookup_text(text).split()
    if words and words[0] in german_article_hints:
        return words[0]
    return None


def inferred_card_type(source: str, target: str, part_of_speech: str) -> str:
    if any(symbol in source for symbol in "?!") or any(symbol in target for symbol in "?!"):
        return "phrases"
    source_words = len(normalized_lookup_text(source).split())
    target_words = len(normalized_lookup_text(target).split())
    if part_of_speech in {"n", "adj", "adv", "v", "pn"}:
        return "words" if source_words <= 2 and target_words <= 3 else "phrases"
    return "phrases"


def exact_display_lookup_key(text: str) -> str:
    return cleaned_quiz_display_text(text).casefold()


def load_reverse_german_gender_map(archive_path: Path) -> tuple[dict[str, str], dict[str, str]]:
    with tarfile.open(archive_path, "r:xz") as tar:
        member = tar.extractfile("deu-fra/deu-fra.tei")
        if member is None:
            raise RuntimeError("deu-fra/deu-fra.tei not found in archive")
        xml_bytes = member.read()

    context = ET.iterparse(io.BytesIO(xml_bytes), events=("end",))
    exact_gender_map: dict[str, str] = {}
    normalized_gender_map: dict[str, str] = {}

    for _, elem in context:
        if elem.tag != f"{{{NS['tei']}}}entry":
            continue

        orth = elem.findtext("./tei:form/tei:orth", default="", namespaces=NS)
        exact_key = exact_display_lookup_key(orth)
        lookup_key = normalized_lookup_text(orth)
        gender = normalized_gender(elem.findtext("./tei:gramGrp/tei:gen", default="", namespaces=NS))

        if exact_key and gender and exact_key not in exact_gender_map:
            exact_gender_map[exact_key] = gender
        if lookup_key and gender and lookup_key not in normalized_gender_map:
            normalized_gender_map[lookup_key] = gender

        elem.clear()

    return exact_gender_map, normalized_gender_map


def extract_records(archive_path: Path, reverse_german_gender_maps: tuple[dict[str, str], dict[str, str]]):
    with tarfile.open(archive_path, "r:xz") as tar:
        member = tar.extractfile("fra-deu/fra-deu.tei")
        if member is None:
            raise RuntimeError("fra-deu/fra-deu.tei not found in archive")
        xml_bytes = member.read()

    context = ET.iterparse(io.BytesIO(xml_bytes), events=("end",))
    records = []
    seen = set()
    reverse_german_exact_gender_map, reverse_german_normalized_gender_map = reverse_german_gender_maps

    for _, elem in context:
        if elem.tag != f"{{{NS['tei']}}}entry":
            continue

        orth = elem.findtext("./tei:form/tei:orth", default="", namespaces=NS)
        pos = elem.findtext("./tei:gramGrp/tei:pos", default="", namespaces=NS).strip()
        source_gender = normalized_gender(elem.findtext("./tei:gramGrp/tei:gen", default="", namespaces=NS))
        source_article = suggested_french_article(source_gender)
        source = source_display_text(orth)
        if not source:
            elem.clear()
            continue

        translation_quotes = []
        for cit in elem.findall(".//tei:cit[@type='trans']", NS):
            language = cit.attrib.get("{http://www.w3.org/XML/1998/namespace}lang", "") or cit.attrib.get("lang", "")
            if language != "de":
                continue
            for quote in cit.findall("./tei:quote", NS):
                target = cleaned_quiz_display_text("".join(quote.itertext()))
                if target:
                    translation_quotes.append(target)

        for target in sorted(set(translation_quotes)):
            card_type = inferred_card_type(source, target, pos)
            source_lookup_variants = deduplicated_lookup_variants([source] + french_lookup_candidates(source))
            source_compact_variants = deduplicated_compact_lookup_variants(source_lookup_variants)
            target_lookup_variants = deduplicated_lookup_variants([target] + german_lookup_candidates(target))
            target_lookup_key = target_lookup_variants[0] if target_lookup_variants else normalized_lookup_text(target)
            target_gender = (
                reverse_german_exact_gender_map.get(exact_display_lookup_key(target))
                or reverse_german_normalized_gender_map.get(target_lookup_key)
            )
            target_article = leading_german_article(target) or suggested_german_article(target_gender)

            source_lookup_key = source_lookup_variants[0] if source_lookup_variants else normalized_lookup_text(source)
            unique_key = f"{source_lookup_key}|{target_lookup_key}|{card_type}"
            if unique_key in seen:
                continue
            seen.add(unique_key)

            records.append(
                (
                    source,
                    target,
                    card_type,
                    source_lookup_key,
                    source_compact_variants[0] if source_compact_variants else compact_lookup_key(source_lookup_key),
                    VARIANT_SEPARATOR.join(source_lookup_variants),
                    VARIANT_SEPARATOR.join(source_compact_variants),
                    target_lookup_key,
                    compact_lookup_key(target_lookup_key),
                    1 if pos == "n" or leading_german_article(target) else 0,
                    1 if should_display_french_question_mark(orth, source) else 0,
                    source_gender,
                    target_gender,
                    source_article,
                    target_article,
                )
            )

        elem.clear()

    return records


def build_database(records, output_path: Path, schema_path: Path):
    if output_path.exists():
        output_path.unlink()

    schema_sql = schema_path.read_text(encoding="utf-8")
    connection = sqlite3.connect(output_path)
    try:
        connection.executescript(schema_sql)
        connection.executemany(
            """
            INSERT INTO lexicon_entries (
                source_term,
                target_term,
                card_type,
                source_lookup_key,
                source_compact_key,
                source_lookup_variants,
                source_compact_variants,
                target_lookup_key,
                target_compact_key,
                is_german_noun,
                is_french_question,
                source_gender,
                target_gender,
                source_article,
                target_leading_article
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            records,
        )
        metadata = [
            ("schema_version", "2"),
            ("record_count", str(len(records))),
            ("generated_at", datetime.now(timezone.utc).isoformat()),
            ("source", "FreeDict fra-deu 2025.11.23"),
        ]
        connection.executemany(
            """
            INSERT INTO metadata (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            metadata,
        )
        connection.commit()
    finally:
        connection.close()


def main():
    script_dir = Path(__file__).resolve().parent
    archive_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/freedict-fra-deu.src.tar.xz")
    reverse_archive_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_REVERSE_ARCHIVE
    output_path = Path(sys.argv[3]) if len(sys.argv) > 3 else script_dir.parent / "FRDEVocabMVP" / "FRDEFreeDictSupplement.sqlite"
    schema_path = Path(sys.argv[4]) if len(sys.argv) > 4 else script_dir / "FRDEKnowledgePoolSchema.sql"

    reverse_german_gender_map = load_reverse_german_gender_map(reverse_archive_path)
    records = extract_records(archive_path, reverse_german_gender_map)
    build_database(records, output_path, schema_path)
    print(f"Built {len(records)} FreeDict supplement rows at {output_path}")


if __name__ == "__main__":
    main()
