#!/usr/bin/env python3
"""Patch Android network settings and install AlQari launcher artwork."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    raise SystemExit(f"Android manifest not found: {manifest}")
s = manifest.read_text(encoding="utf-8")
needle = '<uses-permission android:name="android.permission.INTERNET" />'
if "android.permission.INTERNET" not in s:
    root_start = s.find("<manifest")
    root_end = s.find(">", root_start)
    if root_start < 0 or root_end < 0:
        raise SystemExit("Could not parse Android manifest root tag")
    s = s[:root_end + 1] + "\n    " + needle + s[root_end + 1:]

# just_audio can use a localhost proxy. Allow cleartext only for loopback hosts.
config_path = ROOT / "android/app/src/main/res/xml/network_security_config.xml"
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
""", encoding="utf-8")
if "android:networkSecurityConfig=" not in s:
    application_match = re.search(r"<application\b", s)
    if not application_match:
        raise SystemExit("Could not locate application element in Android manifest")
    insert_at = application_match.end()
    s = s[:insert_at] + ' android:networkSecurityConfig="@xml/network_security_config"' + s[insert_at:]
manifest.write_text(s, encoding="utf-8")

# Flutter's Android scaffold is freshly generated in CI, so install our icon
# assets after scaffold generation. PNGs are pre-sized; this script needs only
# Python's standard library and does not depend on Pillow/ImageMagick.
icon_root = ROOT / "assets/branding/android"
res_root = ROOT / "android/app/src/main/res"
densities = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
for density in densities:
    src_icon = icon_root / f"ic_launcher_{density}.png"
    src_foreground = icon_root / f"ic_launcher_foreground_{density}.png"
    if not src_icon.is_file() or not src_foreground.is_file():
        raise SystemExit(f"Missing launcher icon files for density {density}")
    dst = res_root / f"mipmap-{density}"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_icon, dst / "ic_launcher.png")
    shutil.copy2(src_foreground, dst / "ic_launcher_foreground.png")

background_values = res_root / "values/ic_launcher_background.xml"
background_values.parent.mkdir(parents=True, exist_ok=True)
background_values.write_text("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0D3B30</color>
</resources>
""", encoding="utf-8")
adaptive_dir = res_root / "mipmap-anydpi-v26"
adaptive_dir.mkdir(parents=True, exist_ok=True)
(adaptive_dir / "ic_launcher.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""", encoding="utf-8")

print("Android INTERNET permission is present.")
print("Local audio-proxy cleartext is limited to loopback hosts.")
# Set the visible application name shown by Android launcher and app settings.
if 'android:label="AlQari"' not in s:
    if re.search(r'android:label="[^"]*"', s):
        s = re.sub(r'android:label="[^"]*"', 'android:label="AlQari"', s, count=1)
    else:
        app_match = re.search(r"<application\b", s)
        if not app_match:
            raise SystemExit("Could not locate application element to set app label")
        insert_at = app_match.end()
        s = s[:insert_at] + ' android:label="AlQari"' + s[insert_at:]
    manifest.write_text(s, encoding="utf-8")

print("AlQari launcher label, icons and adaptive icon resources installed.")
