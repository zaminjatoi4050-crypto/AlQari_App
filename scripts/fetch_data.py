#!/usr/bin/env python3
"""Fetch and validate full Quran data for AlQariApp build-time assets.

The app package does not ship a demo Quran. This script downloads the complete
Arabic text and three verse translations, then obtains the Quranic Arabic
Corpus morphology file as a verbatim source asset. It validates the expected
114 surahs / 6,236 ayat before a release build is allowed to continue.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "assets" / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
ALQURAN = "https://api.alquran.cloud/v1"
MORPHOLOGY_URL = "https://raw.githubusercontent.com/mustafa0x/quran-morphology/master/quran-morphology.txt"
MORPHOLOGY_LICENSE_URL = "https://corpus.quran.com/download/"
USER_AGENT = "AlQariAppEducationalBuild/1.0 (full-data-fetcher)"


def fetch_json(url: str, attempts: int = 5) -> Any:
    last_error: Exception | None = None
    for attempt in range(attempts):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                payload = response.read()
            data = json.loads(payload.decode("utf-8-sig"))
            if isinstance(data, dict) and "code" in data and data.get("code") != 200:
                raise RuntimeError(f"API returned {data.get('code')}: {data.get('status')}")
            return data
        except Exception as exc:  # network/API transient failures
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(min(2 ** attempt, 10))
    raise RuntimeError(f"Failed to download {url}: {last_error}")


def fetch_bytes(url: str, attempts: int = 5) -> bytes:
    last_error: Exception | None = None
    for attempt in range(attempts):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=90) as response:
                body = response.read()
            if not body:
                raise RuntimeError("empty response")
            return body
        except Exception as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(min(2 ** attempt, 10))
    raise RuntimeError(f"Failed to download {url}: {last_error}")


def get_data(wrapper: Any) -> Any:
    if isinstance(wrapper, dict) and "data" in wrapper:
        return wrapper["data"]
    return wrapper


def get_translation_edition(language: str) -> tuple[str, str, str]:
    """Return (identifier, translator/name, source version label)."""
    preferred = {
        "en": ["en.sahih", "en.pickthall", "en.yusufali"],
        "ur": ["ur.jalandhry", "ur.junagarhi", "ur.ahmedali"],
        "sd": ["sd.amroti"],
    }[language]
    try:
        listing = get_data(fetch_json(f"{ALQURAN}/edition/language/{language}"))
    except Exception:
        listing = []
    if isinstance(listing, dict):
        listing = listing.get("editions", listing.get("data", []))
    if not isinstance(listing, list):
        listing = []
    translations = [
        e for e in listing
        if isinstance(e, dict)
        and e.get("identifier")
        and e.get("format", "text") == "text"
        and e.get("type", "translation") == "translation"
    ]
    by_id = {str(e.get("identifier", "")): e for e in translations}
    for ident in preferred:
        if ident in by_id:
            e = by_id[ident]
            return ident, str(e.get("englishName") or e.get("name") or ident), str(e.get("version") or "edition listed by AlQuran Cloud")

    # Pick a known language edition if API identifiers differ or are revised.
    terms = {"en": ["sahih", "pickthall", "yusuf"], "ur": ["jalandhry", "junagarhi", "ahmed"], "sd": ["amroti", "sindhi"]}[language]
    for term in terms:
        for e in translations:
            haystack = " ".join(str(e.get(k, "")) for k in ("identifier", "name", "englishName")).lower()
            if term in haystack:
                ident = str(e["identifier"])
                return ident, str(e.get("englishName") or e.get("name") or ident), str(e.get("version") or "edition listed by AlQuran Cloud")
    if translations:
        e = translations[0]
        ident = str(e["identifier"])
        return ident, str(e.get("englishName") or e.get("name") or ident), str(e.get("version") or "edition listed by AlQuran Cloud")

    # If a language-specific listing endpoint is temporarily unavailable, try
    # the known published identifier. The full-edition download and verse-count
    # validation that follows is still mandatory, so this is not a silent
    # substitution or a success assumption.
    fallback = {
        "en": ("en.sahih", "Saheeh International"),
        "ur": ("ur.jalandhry", "Fateh Muhammad Jalandhry"),
        "sd": ("sd.amroti", "Taj Mehmood Amroti"),
    }[language]
    return fallback[0], fallback[1], "known edition identifier; validated by full Quran download"


def fetch_quran_edition(identifier: str) -> dict[str, Any]:
    data = get_data(fetch_json(f"{ALQURAN}/quran/{urllib.parse.quote(identifier, safe='')}"))
    if not isinstance(data, dict) or not isinstance(data.get("surahs"), list):
        raise RuntimeError(f"Unexpected Quran API response for edition {identifier}")
    return data


def normalize_verses(quran: dict[str, Any], translations: dict[str, dict[str, Any]], edition_info: dict[str, dict[str, str]]) -> dict[str, Any]:
    source_surahs = quran["surahs"]
    if len(source_surahs) != 114:
        raise RuntimeError(f"Arabic source contains {len(source_surahs)} surahs, expected 114")
    for lang, edition in translations.items():
        if len(edition.get("surahs", [])) != 114:
            raise RuntimeError(f"Translation {lang} does not contain 114 surahs")

    surahs_out: list[dict[str, Any]] = []
    total = 0
    for s_index, arabic_surah in enumerate(source_surahs):
        sn = int(arabic_surah["number"])
        translated_by_lang: dict[str, dict[int, str]] = {}
        for lang, edition in translations.items():
            tr_surah = edition["surahs"][s_index]
            if int(tr_surah.get("number", sn)) != sn:
                raise RuntimeError(f"Surah ordering mismatch for {lang} around surah {sn}")
            translated_by_lang[lang] = {
                int(a.get("numberInSurah", idx + 1)): str(a.get("text", ""))
                for idx, a in enumerate(tr_surah.get("ayahs", []))
            }

        verses_out: list[dict[str, Any]] = []
        for idx, ayah in enumerate(arabic_surah.get("ayahs", [])):
            an = int(ayah.get("numberInSurah", idx + 1))
            tr_texts: dict[str, str] = {}
            for lang in ("en", "ur", "sd"):
                text = translated_by_lang[lang].get(an, "").strip()
                if not text:
                    raise RuntimeError(f"Missing {lang} translation at {sn}:{an}; refusing to ship incomplete data")
                tr_texts[lang] = text
            arabic_text = str(ayah.get("text", "")).strip()
            if not arabic_text:
                raise RuntimeError(f"Missing Arabic Quran text at {sn}:{an}")
            verses_out.append({
                "number": an,
                "key": f"{sn}:{an}",
                "arabic": arabic_text,
                "translations": tr_texts,
                "juz": int(ayah.get("juz", 1)),
                "page": int(ayah.get("page", 0) or 0),
                "hizbQuarter": int(ayah.get("hizbQuarter", 0) or 0),
                "ruku": int(ayah.get("ruku", 0) or 0),
                "manzil": int(ayah.get("manzil", 0) or 0),
                "sajda": ayah.get("sajda"),
            })
        expected = int(arabic_surah.get("numberOfAyahs", len(verses_out)))
        if len(verses_out) != expected:
            raise RuntimeError(f"Surah {sn} has {len(verses_out)} verses; source metadata says {expected}")
        surahs_out.append({
            "number": sn,
            "nameArabic": str(arabic_surah.get("name", "")),
            "nameEnglish": str(arabic_surah.get("englishName", "")),
            "nameMeaning": str(arabic_surah.get("englishNameTranslation", "")),
            "revelationType": str(arabic_surah.get("revelationType", "")),
            "numberOfAyahs": expected,
            "verses": verses_out,
        })
        total += len(verses_out)

    if total != 6236:
        raise RuntimeError(f"Arabic source has {total} ayat, expected canonical Hafs/Kufan count 6,236. Build stopped.")
    return {
        "schemaVersion": 1,
        "generatedAtUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "datasetType": "complete_quran",
        "counts": {"surahs": len(surahs_out), "verses": total},
        "sources": {
            "arabic": "AlQuran Cloud API edition quran-uthmani; Quran text attribution: Tanzil Project (https://tanzil.net/).",
            "translations": edition_info,
            "wordByWord": "Detailed word meanings are looked up on demand from Quran Foundation API and are not copied into the bundled dataset.",
            "morphology": "Quranic Arabic Corpus / mustafa0x/quran-morphology; see DATA_SOURCES.md",
        },
        "surahs": surahs_out,
    }


def download_morphology() -> tuple[Path, int]:
    data = fetch_bytes(MORPHOLOGY_URL)
    # Check that this looks like the tab-separated corpus before saving it.
    decoded = data.decode("utf-8-sig")
    if "LOCATION" not in decoded[:300] or "(1:1:1:" not in decoded:
        raise RuntimeError("Downloaded morphology data did not match the expected corpus file")
    target = DATA_DIR / "quran-morphology.txt"
    # Keep the source file byte-for-byte verbatim; the app parses it locally.
    target.write_bytes(data)
    lines = decoded.splitlines()
    records = sum(1 for line in lines if re.match(r"^\(\d+:\d+:\d+:\d+\)\s*\t", line))
    if records < 70000:
        # The known format is tab-separated; allow a whitespace-delimited format as backup.
        records = sum(1 for line in lines if re.match(r"^\(\d+:\d+:\d+:\d+\)", line))
    if records < 70000:
        raise RuntimeError(f"Morphology source appears incomplete ({records} records); refusing to continue")
    return target, records


def main() -> None:
    print("AlQariApp full Quran data builder")
    print("Fetching Arabic Quran text...")
    arabic = fetch_quran_edition("quran-uthmani")
    translations: dict[str, dict[str, Any]] = {}
    edition_info: dict[str, dict[str, str]] = {}
    for lang in ("en", "ur", "sd"):
        print(f"Resolving complete {lang} translation edition...")
        ident, translator, version = get_translation_edition(lang)
        print(f"  Selected {ident} — {translator}")
        translations[lang] = fetch_quran_edition(ident)
        edition_info[lang] = {"identifier": ident, "translator": translator, "version": version, "source": "AlQuran Cloud API (https://alquran.cloud/api)"}

    complete = normalize_verses(arabic, translations, edition_info)
    out_path = DATA_DIR / "quran.json"
    out_path.write_text(json.dumps(complete, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote complete Quran data: {out_path} ({out_path.stat().st_size:,} bytes)")
    morph_path, morph_records = download_morphology()
    manifest = {
        "app": "AlQariApp",
        "status": "complete-quran-bundle",
        "generatedAtUtc": complete["generatedAtUtc"],
        "counts": {**complete["counts"], "morphologySegments": morph_records},
        "translations": edition_info,
        "morphologySource": MORPHOLOGY_URL,
        "morphologyLicenseReference": MORPHOLOGY_LICENSE_URL,
        "attributions": [
            "Quran text: Tanzil Project (https://tanzil.net/) — preserve the source text verbatim and retain attribution.",
            "Translation editions and translator identifiers are listed in this manifest; see AlQuran Cloud terms and translation rights.",
            "Word morphology: Quranic Arabic Corpus / mustafa0x/quran-morphology. The morphology source file is bundled verbatim at assets/data/quran-morphology.txt.",
            "Word-by-word gloss lookup: Quran Foundation API (https://api.quran.com/), requested online at runtime; not part of the bundled verse corpus.",
        ],
    }
    (DATA_DIR / "data_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved morphology source file ({morph_path.stat().st_size:,} bytes; {morph_records:,} records)")
    print("Data validation passed: 114 surahs, 6,236 ayat, three translations and full morphology source.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"DATA BUILD FAILED: {error}", file=sys.stderr)
        sys.exit(1)
