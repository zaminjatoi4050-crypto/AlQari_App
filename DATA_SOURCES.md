# Data sources, notices, and attribution

This project packages Quran text, translations, and a morphology reference corpus. Preserve these notices in redistributions. Verify source terms before public or commercial distribution.

## Quran Arabic text

- Build source: AlQuran Cloud API, `quran-uthmani` edition: <https://api.alquran.cloud/v1/quran/quran-uthmani>
- Quran text attribution: Tanzil Project, <https://tanzil.net/>.
- Tanzil's download terms permit use in an application when its source is clearly indicated, a link is provided, and the Quran text is not altered. The application displays the Arabic source unchanged as supplied by the chosen API edition.
- AlQuran Cloud API documentation and terms: <https://alquran.cloud/api> and <https://alquran.cloud/terms-and-conditions>.

## Verse translations

The build selects only the Urdu (`ur.jalandhry`) text translation from AlQuran Cloud and records the edition identifier and translator name in `assets/data/data_manifest.json`. The selected text edition is attributed to Fateh Muhammad Jalandhry. The build stops if the Urdu translation or any ayah is missing.

- API documentation: <https://alquran.cloud/api>
- Publisher terms: <https://alquran.cloud/terms-and-conditions>
- A translation is a human rendering of meaning, not a replacement for the Arabic Quran. Keep translator and edition attribution with the APK.
- Text translation: Fateh Muhammad Jalandhry, edition `ur.jalandhry`.

## Word-by-word gloss

- Requested on demand at runtime from the Quran Foundation API: <https://api.quran.com/>.
- The word gloss is not downloaded and repackaged by the data-generation script. If the service is offline, the app continues to show local morphology and the bundled verse translation.
- Quran Foundation API and data terms should be reviewed before making a public or commercial distribution: <https://quran.com/terms>.

## Word morphology

- Source file: `https://raw.githubusercontent.com/mustafa0x/quran-morphology/master/quran-morphology.txt`
- Upstream project: <https://github.com/mustafa0x/quran-morphology>
- Research source: Quranic Arabic Corpus, University of Leeds / Dr. Kais Dukes: <https://corpus.quran.com/> and <https://corpus.quran.com/download/>.
- The raw morphology text is copied verbatim to `assets/data/quran-morphology.txt` at build time, with no edits to the source file. The app parses its records locally to show word roots, lemmas, part-of-speech tags, and morphological features.
- Quranic Arabic Corpus terms require source attribution and the relevant license notices to travel with copies/derivatives. Review the corpus download page for the current terms, preserve this file verbatim, and include this notice in redistributed packages.

## Code license

The project source code in this repository is made available under the MIT license. This does not replace or override the independent terms for the Quran text, translations, API content, morphology corpus, Flutter packages, or fonts.


## Arabic typeface (v1.2.0)

- **Amiri Quran** (Amiri Project authors; accessed through Google Fonts) is used for Quran verse words, selected-word details, and the Settings preview. Project documentation describes support for Quranic notation; licensing is SIL Open Font License 1.1.
- Source text is not changed to fit the font. A font affects glyph rendering only.
- Google Fonts runtime fetching/cache requires a successful first online load; a first launch without connectivity can fall back to the system font. This should be checked before treating the release as fully offline-ready.
- References: https://aliftype.com/amiri/ and https://pub.dev/packages/google_fonts

## Ayah audio / recitation

- Audio is streamed by ayah from the Al Quran Cloud CDN. URL structure and edition examples are documented at https://alquran.cloud/cdn. The app does not bundle audio files. The edition IDs configured in the app include `ar.alafasy`, `ar.abdulbasit`, `ar.abdulbasitmujawwad`, `ar.husary`, `ar.minshawi`, `ar.minshawimujawwad`, `ar.sudais`, `ar.shuraim`, `ar.ajamy`, and `ar.hudhaify`.
- Audio stream URLs require an internet connection. Verify current provider terms and any required rights/permissions for the recitation recordings before public/commercial release; CDN availability alone should not be treated as a blanket commercial license.
- Spoken Urdu translation: streamed per ayah from `https://verse.mp3quran.net/data/Urdu%29%20Shamshad%20Ali%20Khan/`, with files named by three-digit Surah and Ayah numbers (for example `001001.mp3`). The voice is listed as Shamshad Ali Khan. This is a human recording, not AI or device text-to-speech. Audio is not bundled into the APK. Confirm the host terms and any reuse/public distribution permissions before public or commercial release.


## Additional feature sources
- Prayer times: AlAdhan Prayer Times API, method 1 (University of Islamic Sciences, Karachi), using device location: https://aladhan.com/prayer-times-api
- Adhan notification audio: “Beautiful adhan.ogg” by Adam-synagda, Wikimedia Commons, CC0 1.0: https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg
- Background playback and lock-screen media controls: just_audio_background / audio_service packages (MIT licenses).
- Scheduled notifications and device location: flutter_local_notifications (BSD-3-Clause), geolocator (MIT), flutter_timezone (Apache-2.0), timezone (BSD-2-Clause).
