#!/usr/bin/env python3
"""Download and validate complete Quran text and translation data."""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "assets" / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

ALQURAN = "https://api.alquran.cloud/v1"
MORPHOLOGY_URL = (
    "https://raw.githubusercontent.com/"
    "mustafa0x/quran-morphology/master/quran-morphology.txt"
)
MORPHOLOGY_LICENSE_URL = "https://corpus.quran.com/download/"
USER_AGENT = "AlQariAppEducationalBuild/1.0"


def fetch_json(url: str, attempts: int = 5) -> Any:
    last_error = None

    for attempt in range(attempts):
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()

            data = json.loads(body.decode("utf-8-sig"))

            if isinstance(data, dict) and "code" in data:
                if data.get("code") != 200:
                    raise RuntimeError(
                        f"API returned {data.get('code')}: "
                        f"{data.get('status')}"
                    )

            return data

        except Exception as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(min(2 ** attempt, 10))

    raise RuntimeError(f"Failed to download {url}: {last_error}")


def fetch_bytes(url: str, attempts: int = 5) -> bytes:
    last_error = None

    for attempt in range(attempts):
        request = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT},
        )

        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                body = response.read()

            if not body:
                raise RuntimeError("The server returned an empty file.")

            return body

        except Exception as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(min(2 ** attempt, 10))

    raise RuntimeError(f"Failed to download {url}: {last_error}")


def get_data(response: Any) -> Any:
    if isinstance(response, dict) and "data" in response:
        return response["data"]
    return response


def get_translation_edition(language: str) -> tuple[str, str, str]:
    preferred = {
        "en": ["en.sahih", "en.pickthall", "en.yusufali"],
        "ur": ["ur.jalandhry", "ur.junagarhi", "ur.ahmedali"],
        "sd": ["sd.amroti"],
    }[language]

    try:
        listing = get_data(
            fetch_json(f"{ALQURAN}/edition/language/{language}")
        )
    except Exception:
        listing = []

    if isinstance(listing, dict):
        listing = listing.get("editions", listing.get("data", []))

    if not isinstance(listing, list):
        listing = []

    translations = [
        edition
        for edition in listing
        if isinstance(edition, dict)
        and edition.get("identifier")
        and edition.get("format", "text") == "text"
        and edition.get("type", "translation") == "translation"
    ]

    by_id = {
        str(edition.get("identifier", "")): edition
        for edition in translations
    }

    for identifier in preferred:
        if identifier in by_id:
            edition = by_id[identifier]
            return (
                identifier,
                str(
                    edition.get("englishName")
                    or edition.get("name")
                    or identifier
                ),
                str(edition.get("version") or "edition listed by API"),
            )

    terms = {
        "en": ["sahih", "pickthall", "yusuf"],
        "ur": ["jalandhry", "junagarhi", "ahmed"],
        "sd": ["amroti", "sindhi"],
    }[language]

    for term in terms:
        for edition in translations:
            details = " ".join(
                str(edition.get(key, ""))
                for key in ("identifier", "name", "englishName")
            ).lower()

            if term in details:
                identifier = str(edition["identifier"])
                return (
                    identifier,
                    str(
                        edition.get("englishName")
                        or edition.get("name")
                        or identifier
                    ),
                    str(edition.get("version") or "edition listed by API"),
                )

    if translations:
        edition = translations[0]
        identifier = str(edition["identifier"])
        return (
            identifier,
            str(
                edition.get("englishName")
                or edition.get("name")
                or identifier
            ),
            str(edition.get("version") or "edition listed by API"),
        )

    fallback = {
        "en": ("en.sahih", "Saheeh International"),
        "ur": ("ur.jalandhry", "Fateh Muhammad Jalandhry"),
        "sd": ("sd.amroti", "Taj Mehmood Amroti"),
    }[language]

    return fallback[0], fallback[1], "fallback identifier; download must validate"


def fetch_quran_edition(identifier: str) -> dict[str, Any]:
    url = f"{ALQURAN}/quran/{urllib.parse.quote(identifier, safe='')}"
    data = get_data(fetch_json(url))

    if not isinstance(data, dict) or not isinstance(data.get("surahs"), list):
        raise RuntimeError(
            f"Unexpected Quran API response for edition {identifier}"
        )

    return data


def normalize_verses(
    quran: dict[str, Any],
    translations: dict[str, dict[str, Any]],
    edition_info: dict[str, dict[str, str]],
) -> dict[str, Any]:
    source_surahs = quran["surahs"]

    if len(source_surahs) != 114:
        raise RuntimeError(
            f"Arabic source contains {len(source_surahs)} surahs; expected 114."
        )

    for language, edition in translations.items():
        if len(edition.get("surahs", [])) != 114:
            raise RuntimeError(
                f"Translation {language} does not contain 114 surahs."
            )

    output_surahs = []
    total_verses = 0

    for index, arabic_surah in enumerate(source_surahs):
        surah_number = int(arabic_surah["number"])
        translations_by_language: dict[str, dict[int, str]] = {}

        for language, edition in translations.items():
            translated_surah = edition["surahs"][index]

            if int(translated_surah.get("number", surah_number)) != surah_number:
                raise RuntimeError(
                    f"Surah ordering mismatch for {language}, "
                    f"surah {surah_number}."
                )

            translations_by_language[language] = {
                int(ayah.get("numberInSurah", ayah_index + 1)):
                    str(ayah.get("text", ""))
                for ayah_index, ayah in enumerate(
                    translated_surah.get("ayahs", [])
                )
            }

        output_verses = []

        for ayah_index, ayah in enumerate(arabic_surah.get("ayahs", [])):
            ayah_number = int(
                ayah.get("numberInSurah", ayah_index + 1)
            )

            translated_texts = {}

            for language in ("en", "ur", "sd"):
                text = translations_by_language[language].get(
                    ayah_number, ""
                ).strip()

                if not text:
                    raise RuntimeError(
                        f"Missing {language} translation at "
                        f"{surah_number}:{ayah_number}."
                    )

                translated_texts[language] = text

            arabic_text = str(ayah.get("text", "")).strip()

            if not arabic_text:
                raise RuntimeError(
                    f"Missing Arabic text at {surah_number}:{ayah_number}."
                )

            output_verses.append({
                "number": ayah_number,
                "key": f"{surah_number}:{ayah_number}",
                "arabic": arabic_text,
                "translations": translated_texts,
                "juz": int(ayah.get("juz", 1)),
                "page": int(ayah.get("page", 0) or 0),
                "hizbQuarter": int(ayah.get("hizbQuarter", 0) or 0),
                "ruku": int(ayah.get("ruku", 0) or 0),
                "manzil": int(ayah.get("manzil", 0) or 0),
                "sajda": ayah.get("sajda"),
            })

        expected = int(
            arabic_surah.get("numberOfAyahs", len(output_verses))
        )

        if len(output_verses) != expected:
            raise RuntimeError(
                f"Surah {surah_number}: found {len(output_verses)} ayat; "
                f"expected {expected}."
            )

        output_surahs.append({
            "number": surah_number,
            "nameArabic": str(arabic_surah.get("name", "")),
            "nameEnglish": str(arabic_surah.get("englishName", "")),
            "nameMeaning": str(
                arabic_surah.get("englishNameTranslation", "")
            ),
            "revelationType": str(
                arabic_surah.get("revelationType", "")
            ),
            "numberOfAyahs": expected,
            "verses": output_verses,
        })

        total_verses += len(output_verses)

    if total_verses != 6236:
        raise RuntimeError(
            f"Downloaded {total_verses} ayat; expected 6,236. "
            "Build stopped."
        )

    return {
        "schemaVersion": 1,
        "generatedAtUtc": time.strftime(
            "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
        ),
        "datasetType": "complete_quran",
        "counts": {
            "surahs": len(output_surahs),
            "verses": total_verses,
        },
        "sources": {
            "arabic": (
                "AlQuran Cloud quran-uthmani API; "
                "retain Tanzil attribution: https://tanzil.net/"
            ),
            "translations": edition_info,
            "wordByWord": (
                "Detailed word meanings are requested online; "
                "they are not included in the bundled verse data."
            ),
            "morphology": (
                "Quranic Arabic Corpus / mustafa0x/quran-morphology; "
                "see DATA_SOURCES.md."
            ),
        },
        "surahs": output_surahs,
    }


def download_morphology() -> tuple[Path, int]:
    """Download the corpus and validate either supported location format."""

    print("Downloading Quranic morphology data...")
    data = fetch_bytes(MORPHOLOGY_URL)
    decoded = data.decode("utf-8-sig")
    lines = decoded.splitlines()

    # The source has used both parenthesized and unparenthesized locations.
    # Example:
    # (1:1:1:1) TAB FORM TAB TAG TAB FEATURES
    # 1:1:1:1   TAB FORM TAB TAG TAB FEATURES
    location_record = re.compile(
        r"^\s*\(?\d+:\d+:\d+:\d+\)?(?:\t|\s+)"
    )

    records = 0

    for line in lines:
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            continue

        if stripped.upper().startswith("LOCATION"):
            continue

        if location_record.match(line):
            records += 1

    if records < 70000:
        preview = "\n".join(lines[:8])[:500]
        raise RuntimeError(
            "Morphology source validation failed: "
            f"only {records} location records found; expected at least 70,000. "
            f"File preview: {preview!r}"
        )

    target = DATA_DIR / "quran-morphology.txt"

    # Preserve the downloaded source byte-for-byte.
    target.write_bytes(data)

    print(f"Validated {records:,} morphology records.")
    return target, records


def main() -> None:
    print("AlQariApp full Quran data builder")
    print("Fetching Arabic Quran text...")

    arabic = fetch_quran_edition("quran-uthmani")
    translations: dict[str, dict[str, Any]] = {}
    edition_info: dict[str, dict[str, str]] = {}

    for language in ("en", "ur", "sd"):
        print(f"Resolving complete {language} translation edition...")

        identifier, translator, version = get_translation_edition(language)
        print(f"Selected {identifier} — {translator}")

        translations[language] = fetch_quran_edition(identifier)

        edition_info[language] = {
            "identifier": identifier,
            "translator": translator,
            "version": version,
            "source": "AlQuran Cloud API (https://alquran.cloud/api)",
        }

    complete = normalize_verses(arabic, translations, edition_info)

    quran_path = DATA_DIR / "quran.json"
    quran_path.write_text(
        json.dumps(complete, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    print(
        f"Wrote Quran data: {quran_path} "
        f"({quran_path.stat().st_size:,} bytes)"
    )

    morphology_path, record_count = download_morphology()

    manifest = {
        "app": "AlQariApp",
        "status": "complete-quran-bundle",
        "generatedAtUtc": complete["generatedAtUtc"],
        "counts": {
            **complete["counts"],
            "morphologySegments": record_count,
        },
        "translations": edition_info,
        "morphologySource": MORPHOLOGY_URL,
        "morphologyLicenseReference": MORPHOLOGY_LICENSE_URL,
        "attributions": [
            (
                "Quran text: Tanzil Project "
                "(https://tanzil.net/); preserve attribution."
            ),
            (
                "Translation editions and translator identifiers are recorded "
                "in this manifest; verify the source terms before redistribution."
            ),
            (
                "Morphology: Quranic Arabic Corpus / mustafa0x/quran-morphology; "
                "source file is bundled verbatim."
            ),
            (
                "Word-by-word gloss lookup uses Quran Foundation API "
                "(https://api.quran.com/) at runtime."
            ),
        ],
    }

    manifest_path = DATA_DIR / "data_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Morphology saved: {morphology_path}")
    print(
        "Data validation passed: 114 surahs, 6,236 ayat, "
        "three translations and morphology source."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"DATA BUILD FAILED: {error}", file=sys.stderr)
        sys.exit(1)