# AlQari v1.5.0 — UI/UX implementation notes

The latest generated poster was a visual concept, not a source of additional data or backend functionality. This implementation translates its feasible visual design into the real Flutter app while avoiding fake destinations.

Implemented screens/components:
- Persistent AlQari brand header and drawer with green/gold identity.
- Home dashboard: greeting, Quran-library counts, continue/start reading, six quick-action cards, and daily reflection from existing Quran data.
- Quran Reader remains backed by existing Quran repository, selector, translation, bookmarks and word-analysis sheet; Arabic words are individually tappable inside a single softly bordered reading panel.
- Quran Recitation remains connected to the existing `just_audio` playlist and supported reciter list.
- Search and Bookmarks retain their existing functionality.
- More page links to Search, Recitation, Continue Reading, Language/Translation settings, Appearance settings and About.
- Settings retains Light/Dark/System appearance, six accent colors, language, Arabic font-size control, data coverage and attribution.

Not advertised as implemented: full Tafsir library, user Notes workspace, offline recitation downloads, audio background controls/notification, or new sentence-level Nahw roles. These require additional data and engineering, so the UI does not present them as finished functionality.
