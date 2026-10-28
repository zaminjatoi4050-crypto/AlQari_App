# AlQari 1.3.0 — Static review status

## Confirmed by source/static checks

- `pubspec.yaml` parses as YAML and defines `just_audio: ^0.10.6` with app version `1.3.0+4`.
- The source contains a Recitation page accessible from the drawer and a CTA on the Quran reader.
- Ten reciter edition IDs are configured from the Al Quran Cloud CDN documentation.
- The playlist maps each ayah's position in the validated canonical Quran list to the CDN's global ayah number (1–6,236), queues the selected Surah in order, and uses `just_audio`'s playlist API so the next ayah is selected automatically.
- The app has play/pause, previous/next, seeking, current-ayah text/translation, and retry/error handling.
- A local test of `scripts/patch_android_manifest.py` on a generated-style manifest added INTERNET permission and produced parseable XML for a loopback-only network security config.
- Source and test files were scanned for required audio wiring; `pubspec.yaml` and Python build script syntax were checked.

## Not yet verified

- Flutter analyzer, `flutter test`, Gradle release build, and live audio playback could not be run in this environment because Flutter/Dart SDK and internet package resolution were unavailable.
- Availability of every individual audio URL must be verified by trying the reciters and several Surahs on a real Android device with internet.
- Amiri Quran glyphs need visual inspection on device, especially Qur'anic marks.
- Verify current provider terms and permissions for recordings before public/commercial Play Store distribution. Publicly reachable CDN URLs are not a blanket statement of commercial rights.

Use `RELEASE_CHECKLIST_1.3.0.md` and require the GitHub Actions workflow to pass `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release` before installing the new APK.
