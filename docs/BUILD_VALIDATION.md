# APK build validation

The `Build complete AlQari APK` GitHub Actions workflow validates the generated Quran data, resolves Flutter packages, runs `flutter analyze`, runs `flutter test`, and builds the Android release APK. The workflow uploads `AlQari-Release-APK` only when the build succeeds.

For a device installation, use the APK artifact from a successful workflow run. Do not use artifacts from a failed run.