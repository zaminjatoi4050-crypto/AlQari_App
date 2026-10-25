# Data sources, notices, and attribution

This project packages Quran text, translations, and a morphology reference corpus. Preserve these notices in redistributions. Verify source terms before public or commercial distribution.

## Quran Arabic text

- Build source: AlQuran Cloud API, `quran-uthmani` edition: <https://api.alquran.cloud/v1/quran/quran-uthmani>
- Quran text attribution: Tanzil Project, <https://tanzil.net/>.
- Tanzil's download terms permit use in an application when its source is clearly indicated, a link is provided, and the Quran text is not altered. The application displays the Arabic source unchanged as supplied by the chosen API edition.
- AlQuran Cloud API documentation and terms: <https://alquran.cloud/api> and <https://alquran.cloud/terms-and-conditions>.

## Verse translations

The build selects full text editions from AlQuran Cloud's language-edition directory for English (`en`), Urdu (`ur`), and Sindhi (`sd`) and records the actual edition identifier and translator name in `assets/data/data_manifest.json`. The build stops if one of the languages or any ayah translation is missing; it does not silently substitute English for Urdu/Sindhi.

- API documentation: <https://alquran.cloud/api>
- Publisher terms: <https://alquran.cloud/terms-and-conditions>
- A translation is a human rendering of meaning, not a replacement for the Arabic Quran. Keep translator and edition attribution with the APK.

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
