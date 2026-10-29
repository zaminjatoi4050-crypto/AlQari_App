#!/usr/bin/env python3
"""Validate audio edition IDs and representative playable CDN resources."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

USER_AGENT = "AlQariAudioValidator/1.0"
EDITION_API = "https://api.alquran.cloud/v1/edition/format/audio"

# These exact folders match the released quran-align timing dataset. For the
# other two editions, the Al Quran Cloud edition endpoint supplies the audio.
SAMPLES = {
    "ar.alafasy": "https://everyayah.com/data/Alafasy_128kbps/001001.mp3",
    "ar.abdulbasit": "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/001001.mp3",
    "ar.abdulbasitmujawwad": "https://everyayah.com/data/Abdul_Basit_Mujawwad_128kbps/001001.mp3",
    "ar.husary": "https://everyayah.com/data/Husary_64kbps/001001.mp3",
    "ar.minshawi": "https://everyayah.com/data/Minshawy_Murattal_128kbps/001001.mp3",
    "ar.minshawimujawwad": "https://everyayah.com/data/Minshawy_Mujawwad_192kbps/001001.mp3",
    "ar.sudais": "https://everyayah.com/data/Abdurrahmaan_As-Sudais_192kbps/001001.mp3",
    "ar.shuraim": "https://everyayah.com/data/Saood_ash-Shuraym_128kbps/001001.mp3",
    "ar.ajamy": "https://cdn.islamic.network/quran/audio/128/ar.ajamy/1.mp3",
    "ar.hudhaify": "https://cdn.islamic.network/quran/audio/128/ar.hudhaify/1.mp3",
}


def get_json(url: str) -> object:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8-sig"))


def probe_audio(url: str, attempts: int = 3) -> None:
    last_error: Exception | None = None
    for attempt in range(attempts):
        request = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                if response.status not in (200, 206):
                    raise RuntimeError(f"unexpected HTTP status {response.status}")
                sample = response.read(1)
                if not sample:
                    raise RuntimeError("empty audio response")
                return
        except Exception as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(attempt + 1)
    raise RuntimeError(f"Audio probe failed for {url}: {last_error}")


def main() -> None:
    response = get_json(EDITION_API)
    if not isinstance(response, dict) or response.get("code") != 200:
        raise RuntimeError("Al Quran Cloud audio edition endpoint did not return a success response")
    rows = response.get("data")
    if not isinstance(rows, list):
        raise RuntimeError("Al Quran Cloud audio edition response has no edition list")
    available = {str(row.get("identifier")) for row in rows if isinstance(row, dict)}
    missing = sorted(set(SAMPLES) - available)
    if missing:
        raise RuntimeError("Unknown/removed Al Quran Cloud audio edition IDs: " + ", ".join(missing))
    print(f"Validated all {len(SAMPLES)} configured audio edition IDs against Al Quran Cloud.")

    for edition, url in SAMPLES.items():
        probe_audio(url)
        print(f"  playable sample OK: {edition}")

    print("Audio source validation passed.")


if __name__ == "__main__":
    main()
