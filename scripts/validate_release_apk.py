#!/usr/bin/env python3
"""Validate that the release APK contains the exact complete Quran assets and Adhan audio."""
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path

EXPECTED_ADHAN_SHA1 = "a1fa4fd942401922c5c3301816384aae86956522"
REQUIRED_ASSETS = (
    "assets/flutter_assets/assets/data/quran.json",
    "assets/flutter_assets/assets/data/quran-morphology.txt",
    "assets/flutter_assets/assets/data/word_timings.json",
    "assets/flutter_assets/assets/data/data_manifest.json",
)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: validate_release_apk.py path/to/app-release.apk", file=sys.stderr)
        return 2
    apk_path = Path(sys.argv[1])
    if not apk_path.is_file():
        print(f"APK not found: {apk_path}", file=sys.stderr)
        return 2
    if not zipfile.is_zipfile(apk_path):
        print("Release output is not a valid ZIP/APK archive.", file=sys.stderr)
        return 2

    try:
        with zipfile.ZipFile(apk_path) as apk:
            names = set(apk.namelist())
            missing = [name for name in REQUIRED_ASSETS if name not in names]
            if missing:
                raise RuntimeError("Missing bundled Quran asset(s): " + ", ".join(missing))
            adhan_entry = None
            adhan_sha1 = None
            for info in apk.infolist():
                if info.is_dir():
                    continue
                with apk.open(info) as stream:
                    header = stream.read(4)
                if header != b"OggS":
                    continue
                digest = hashlib.sha1(apk.read(info.filename)).hexdigest()
                if digest == EXPECTED_ADHAN_SHA1:
                    adhan_entry = info.filename
                    adhan_sha1 = digest
                    break
            if adhan_entry is None:
                raise RuntimeError(
                    "The CC0 Adhan audio is not present in the built APK. "
                    "The prayer notification resource must survive Android resource processing."
                )
            size = apk_path.stat().st_size
            if size < 20 * 1024 * 1024:
                raise RuntimeError(f"APK size ({size} bytes) is unexpectedly small for full Quran data/audio.")
            print(f"APK archive valid: {apk_path} ({size:,} bytes)")
            print(f"Required Quran assets present: {len(REQUIRED_ASSETS)}/{len(REQUIRED_ASSETS)}")
            print(f"CC0 Adhan audio present: {adhan_entry} (SHA-1 {adhan_sha1})")
            return 0
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        print(f"Release APK validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
