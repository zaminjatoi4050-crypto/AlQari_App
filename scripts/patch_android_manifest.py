#!/usr/bin/env python3
"""Ensure Android release builds have Internet permission for online word gloss."""
from pathlib import Path

p = Path("android/app/src/main/AndroidManifest.xml")
if not p.exists():
    raise SystemExit(f"Android manifest not found: {p}")
s = p.read_text(encoding="utf-8")
needle = '<uses-permission android:name="android.permission.INTERNET" />'
if "android.permission.INTERNET" not in s:
    root_start = s.find("<manifest")
    if root_start < 0:
        raise SystemExit("Could not locate Android manifest root tag")
    root_end = s.find(">", root_start)
    if root_end < 0:
        raise SystemExit("Could not parse Android manifest root tag")
    s = s[:root_end + 1] + "\n    " + needle + s[root_end + 1:]
    p.write_text(s, encoding="utf-8")
print("Android INTERNET permission is present.")
