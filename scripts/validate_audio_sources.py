#!/usr/bin/env python3
"""Validate live audio edition IDs and representative playable recitation URLs."""
from __future__ import annotations

import json
import time
import urllib.request

USER_AGENT = "AlQariAudioValidator/1.1"
EDITION_API = "https://api.alquran.cloud/v1/edition/format/audio"

# These URLs match the audio folders used by the word-timing dataset or the
# explicitly mapped Ajamy audio folder. Audio is streamed, not bundled.
EVERYAYAH_SAMPLES = {
    "ar.alafasy": "https://everyayah.com/data/Alafasy_128kbps/001001.mp3",
    "ar.abdulbasit": "https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/001001.mp3",
    "ar.abdulbasitmujawwad": "https://everyayah.com/data/Abdul_Basit_Mujawwad_128kbps/001001.mp3",
    "ar.husary": "https://everyayah.com/data/Husary_64kbps/001001.mp3",
    "ar.minshawi": "https://everyayah.com/data/Minshawy_Murattal_128kbps/001001.mp3",
    "ar.minshawimujawwad": "https://everyayah.com/data/Minshawy_Mujawwad_192kbps/001001.mp3",
    "ar.sudais": "https://everyayah.com/data/Abdurrahmaan_As-Sudais_192kbps/001001.mp3",
    "ar.shuraim": "https://everyayah.com/data/Saood_ash-Shuraym_128kbps/001001.mp3",
    "ar.ajamy": "https://everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/001001.mp3",
}

# Only this option depends on the Al Quran Cloud audio edition identifier.
QURAN_CLOUD_SAMPLES = {
    "ar.hudhaify": "https://cdn.islamic.network/quran/audio/128/ar.hudhaify/1.mp3",
}

SPOKEN_URDU_TRANSLATION_SAMPLES = {
    "Surah Al-Fatihah 1:1": "https://verse.mp3quran.net/data/Urdu%29%20Shamshad%20Ali%20Khan/001001.mp3",
    "Surah Al-Baqarah 2:14": "https://verse.mp3quran.net/data/Urdu%29%20Shamshad%20Ali%20Khan/002014.mp3",
    "Surah An-Nas 114:6": "https://verse.mp3quran.net/data/Urdu%29%20Shamshad%20Ali%20Khan/114006.mp3",
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
                if not response.read(1):
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
        raise RuntimeError("Al Quran Cloud audio edition endpoint did not return success")
    rows = response.get("data")
    if not isinstance(rows, list):
        raise RuntimeError("Al Quran Cloud response has no audio edition list")
    available = {str(row.get("identifier")) for row in rows if isinstance(row, dict)}
    missing = sorted(set(QURAN_CLOUD_SAMPLES) - available)
    if missing:
        raise RuntimeError("Al Quran Cloud fallback IDs are absent from the live edition list: " + ", ".join(missing))
    print(f"Validated {len(QURAN_CLOUD_SAMPLES)} Al Quran Cloud fallback edition ID(s).")

    for edition, url in {**EVERYAYAH_SAMPLES, **QURAN_CLOUD_SAMPLES}.items():
        probe_audio(url)
        print(f"  playable sample OK: {edition}")

    for label, url in SPOKEN_URDU_TRANSLATION_SAMPLES.items():
        probe_audio(url)
        print(f"  playable sample OK: human-recorded Urdu translation — {label}")
    print(f"Audio source validation passed ({len(EVERYAYAH_SAMPLES) + len(QURAN_CLOUD_SAMPLES) + len(SPOKEN_URDU_TRANSLATION_SAMPLES)} Arabic/Urdu sample files).")


if __name__ == "__main__":
    main()
