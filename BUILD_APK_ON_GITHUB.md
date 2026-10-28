# Build the AlQari APK with GitHub Actions

This project uses GitHub-hosted runners, so you do **not** need Flutter installed on your Windows PC to build the APK.

## First time only

1. Download and extract `AlQari_Full.zip`.
2. Create an empty GitHub repository at https://github.com/new. Name it `AlQari`.
3. Open PowerShell in the extracted `AlQari_Full` directory.
4. Run these commands, replacing `YOUR_GITHUB_USERNAME` with your GitHub username:

```powershell
git init -b main
git add .
git commit -m "Add full AlQari source"
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/AlQari.git
git push -u origin main
```

GitHub may ask you to sign in. Use Git Credential Manager / browser sign-in; never paste a password or personal access token into this project or a public file.

## Download the APK

1. Open the repository on GitHub.
2. Select **Actions**.
3. Choose **Build complete AlQari APK**.
4. Open the run triggered by your push. If it has not started, choose **Run workflow**.
5. Wait for a successful green check mark; open that run.
6. Under **Artifacts**, download `AlQari-Release-APK` and extract it.
7. Install `app-release.apk` on your Android phone. Android may ask you to allow installs from your browser/file manager.

## What the workflow does

It downloads the full Quran and English/Urdu/Sindhi ayah translations, checks the expected 114 surahs and 6,236 ayat, downloads attributed Quranic Arabic Corpus morphology, generates Android scaffolding, runs tests and builds a release APK. The APK artifact is created by GitHub Actions; the source ZIP itself is not an APK.

## If the workflow fails

Open the failed step and read its error. A data-source outage, changed translation identifier, API rate limit, or source-count mismatch intentionally stops the build rather than creating an incomplete Quran APK. Share the failing log (hide secrets, if any) for troubleshooting.
