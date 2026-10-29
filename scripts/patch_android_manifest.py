#!/usr/bin/env python3
"""Patch Android network settings and install AlQari launcher artwork."""
from pathlib import Path
import hashlib
import re
import shutil
import urllib.request

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


# Runtime requirements for background audio, geolocation, and scheduled reminders.
required_permissions = (
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.SCHEDULE_EXACT_ALARM",
)
missing = [permission for permission in required_permissions if permission not in s]
if missing:
    root_start = s.find("<manifest")
    root_end = s.find(">", root_start)
    if root_start < 0 or root_end < 0:
        raise SystemExit("Could not parse Android manifest root tag")
    s = s[:root_end + 1] + "\n    " + "\n    ".join(
        '<uses-permission android:name="' + permission + '" />' for permission in missing
    ) + s[root_end + 1:]

activity_match = re.search(r"<activity\b[^>]*>.*?</activity>", s, flags=re.S)
if not activity_match:
    raise SystemExit("Could not locate the launcher activity for background audio")
activity = re.sub(r'android:name="[^"]+"',
    'android:name="com.ryanheise.audioservice.AudioServiceActivity"',
    activity_match.group(0), count=1)
s = s[:activity_match.start()] + activity + s[activity_match.end():]
application_components = """
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback" android:exported="true">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService" /></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON" /></intent-filter>
        </receiver>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
"""
if "com.ryanheise.audioservice.AudioService" not in s:
    s = s.replace("</application>", application_components + "\n    </application>", 1)
manifest.write_text(s, encoding="utf-8")

for gradle_name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    gradle_path = ROOT / gradle_name
    if not gradle_path.exists():
        continue
    gradle = gradle_path.read_text(encoding="utf-8")
    kotlin_dsl = gradle_name.endswith(".kts")
    multidex = "multiDexEnabled = true" if kotlin_dsl else "multiDexEnabled true"
    desugaring = "isCoreLibraryDesugaringEnabled = true" if kotlin_dsl else "coreLibraryDesugaringEnabled true"
    dependency = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kotlin_dsl else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
    match = re.search(r"defaultConfig\s*\{", gradle)
    if match and "multiDexEnabled" not in gradle:
        gradle = gradle[:match.end()] + "\n        " + multidex + gradle[match.end():]
    match = re.search(r"compileOptions\s*\{", gradle)
    if match and "CoreLibraryDesugaringEnabled" not in gradle and "coreLibraryDesugaringEnabled" not in gradle:
        gradle = gradle[:match.end()] + "\n        " + desugaring + gradle[match.end():]
    if "desugar_jdk_libs" not in gradle:
        match = re.search(r"dependencies\s*\{", gradle)
        if match:
            gradle = gradle[:match.end()] + "\n    " + dependency + gradle[match.end():]
        else:
            # New Flutter scaffold templates may omit an empty dependencies block.
            gradle = gradle.rstrip() + "\n\ndependencies {\n    " + dependency + "\n}\n"
    gradle_path.write_text(gradle, encoding="utf-8")

adhan_url = "https://upload.wikimedia.org/wikipedia/commons/b/b0/Beautiful_adhan.ogg"
request = urllib.request.Request(adhan_url, headers={"User-Agent": "AlQari Android build"})
with urllib.request.urlopen(request, timeout=60) as response:
    adhan_bytes = response.read()
if len(adhan_bytes) < 200000 or hashlib.sha1(adhan_bytes).hexdigest() != "a1fa4fd942401922c5c3301816384aae86956522":
    raise SystemExit("Downloaded Adhan did not match the verified CC0 source file.")
raw_dir = ROOT / "android/app/src/main/res/raw"
raw_dir.mkdir(parents=True, exist_ok=True)
(raw_dir / "adhan.ogg").write_bytes(adhan_bytes)
print("Background audio, location permissions, scheduled notifications and CC0 Adhan installed.")

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
