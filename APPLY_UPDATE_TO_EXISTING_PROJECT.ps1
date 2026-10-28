$ErrorActionPreference = "Stop"
$SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetRoot = "D:\Downloads\AlQariApp_Full_Project\AlQariApp_Full"
Write-Host "AlQari v1.5.0 updater" -ForegroundColor Cyan
if (!(Test-Path (Join-Path $TargetRoot ".git"))) {
  throw "Existing Git repository not found at $TargetRoot. Edit TargetRoot in this script to match your existing project folder."
}
$files = @(
  "lib\main.dart",
  "assets\branding\al_qari_icon.png",
  "assets\branding\al_qari_wordmark.png",
  "assets\branding\al_qari_play_store_icon_512.png",
  "assets\branding\android\ic_launcher_mdpi.png",
  "assets\branding\android\ic_launcher_hdpi.png",
  "assets\branding\android\ic_launcher_xhdpi.png",
  "assets\branding\android\ic_launcher_xxhdpi.png",
  "assets\branding\android\ic_launcher_xxxhdpi.png",
  "assets\branding\android\ic_launcher_foreground_mdpi.png",
  "assets\branding\android\ic_launcher_foreground_hdpi.png",
  "assets\branding\android\ic_launcher_foreground_xhdpi.png",
  "assets\branding\android\ic_launcher_foreground_xxhdpi.png",
  "assets\branding\android\ic_launcher_foreground_xxxhdpi.png",
  "pubspec.yaml",
  "scripts\patch_android_manifest.py",
  "scripts\fetch_data.py",
  "test\app_logic_test.dart",
  "README.md",
  "BRAND_GUIDE_1.5.0.md",
  "DATA_SOURCES.md",
  "BUILD_APK_ON_GITHUB.md",
  "LICENSE",
  ".github\workflows\build-apk.yml",
  "UPDATE_NOTES_1.5.0.md",
  "RELEASE_CHECKLIST_1.5.0.md",
  "UI_UX_IMPLEMENTATION_1.5.0.md"
)
foreach ($relative in $files) {
  $src = Join-Path $SourceRoot $relative
  if (!(Test-Path $src)) { throw "Source file missing: $relative" }
  $dst = Join-Path $TargetRoot $relative
  $parent = Split-Path -Parent $dst
  if (!(Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Write-Host "Updated $relative" -ForegroundColor Green
}
Write-Host "Done. Your .git folder and Android-generated files were not deleted." -ForegroundColor Cyan
Write-Host "Next: open PowerShell in the target folder and run git status, then review changes before committing." -ForegroundColor Yellow

# Remove obsolete branding files created by the earlier draft; the app does not reference these.
foreach ($stale in @("BRAND_GUIDE_1.4.0.md", "assets\branding\alqari_app_icon.png", "assets\branding\alqari_play_store_icon_512.png", "assets\branding\alqari_wordmark.svg", "assets\branding\alqari_wordmark.png", "assets\branding\alqari_wordmark_transparent.png")) {
  $path = Join-Path $TargetRoot $stale
  if (Test-Path $path) { Remove-Item -LiteralPath $path -Force; Write-Host "Removed obsolete unused brand asset $stale" -ForegroundColor DarkYellow }
}
