import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const Color forest = Color(0xFF153D33);
const Color green = Color(0xFF236B55);
const Color gold = Color(0xFFD8B56A);
const Color paper = Color(0xFFF7F5EF);
const String quranFontFamily = 'Amiri Quran';
const String appLogoAsset = 'assets/branding/al_qari_icon.png';

/// Shared current ayah key so the Reader can follow the active recitation.
final ValueNotifier<String?> activeRecitationAyahKey = ValueNotifier<String?>(null);
const List<Color> appAccentColors = <Color>[
  Color(0xFF236B55), // Forest green
  Color(0xFF0F766E), // Teal
  Color(0xFF2563EB), // Blue
  Color(0xFF7C3AED), // Violet
  Color(0xFFB45309), // Amber
  Color(0xFFBE123C), // Rose
];
const List<String> appAccentNames = <String>[
  'Forest', 'Teal', 'Blue', 'Violet', 'Amber', 'Rose',
];


/// A Quran audio edition exposed by the Al Quran Cloud ayah-audio CDN.
/// Audio is streamed; recordings are not bundled into the application.
class QuranReciter {
  final String id;
  final String name;
  final String arabicName;
  final int bitrate;
  /// Exact EveryAyah folder whose audio has matching word timing annotations.
  final String? timingFolder;
  /// Exact audio folder when EveryAyah is the source but timings are unavailable.
  final String? everyAyahFolder;

  const QuranReciter({
    required this.id,
    required this.name,
    required this.arabicName,
    required this.bitrate,
    this.timingFolder,
    this.everyAyahFolder,
  });
}

const List<QuranReciter> supportedReciters = <QuranReciter>[
  QuranReciter(id: 'ar.alafasy', name: 'Mishary Rashid Alafasy', arabicName: 'مشاري راشد العفاسي', bitrate: 128, timingFolder: 'Alafasy_128kbps'),
  QuranReciter(id: 'ar.abdulbasit', name: 'Abdul Basit Abdul Samad · Murattal', arabicName: 'عبد الباسط عبد الصمد', bitrate: 64, timingFolder: 'Abdul_Basit_Murattal_64kbps'),
  QuranReciter(id: 'ar.abdulbasitmujawwad', name: 'Abdul Basit · Mujawwad', arabicName: 'عبد الباسط عبد الصمد', bitrate: 128, timingFolder: 'Abdul_Basit_Mujawwad_128kbps'),
  QuranReciter(id: 'ar.husary', name: 'Mahmoud Khalil Al-Husary', arabicName: 'محمود خليل الحصري', bitrate: 64, timingFolder: 'Husary_64kbps'),
  QuranReciter(id: 'ar.minshawi', name: 'Mohamed Siddiq Al-Minshawi · Murattal', arabicName: 'محمد صديق المنشاوي', bitrate: 128, timingFolder: 'Minshawy_Murattal_128kbps'),
  QuranReciter(id: 'ar.minshawimujawwad', name: 'Al-Minshawi · Mujawwad', arabicName: 'محمد صديق المنشاوي', bitrate: 192, timingFolder: 'Minshawy_Mujawwad_192kbps'),
  QuranReciter(id: 'ar.sudais', name: 'Abdul Rahman Al-Sudais', arabicName: 'عبدالرحمن السدیس', bitrate: 192, everyAyahFolder: 'Abdurrahmaan_As-Sudais_192kbps'),
  QuranReciter(id: 'ar.shuraim', name: 'Saud Al-Shuraim', arabicName: 'سعود الشريم', bitrate: 128, timingFolder: 'Saood_ash-Shuraym_128kbps'),
  QuranReciter(id: 'ar.ajamy', name: 'Ahmed Al-Ajamy', arabicName: 'أحمد العجمي', bitrate: 128, everyAyahFolder: 'ahmed_ibn_ali_al_ajamy_128kbps'),
  QuranReciter(id: 'ar.hudhaify', name: 'Ali Al-Hudhaify', arabicName: 'علي بن عبدالرحمن الحذيفي', bitrate: 128),
];

/// Build the official Al Quran Cloud CDN ayah URL using the global ayah index (1–6236).
String ayahAudioUrl(String edition, int globalAyahNumber, {int bitrate = 128}) {
  if (globalAyahNumber < 1 || globalAyahNumber > 6236) {
    throw RangeError.range(globalAyahNumber, 1, 6236, 'globalAyahNumber');
  }
  if (!supportedReciters.any((reciter) => reciter.id == edition)) {
    throw ArgumentError.value(edition, 'edition', 'Unsupported reciter edition');
  }
  return 'https://cdn.islamic.network/quran/audio/$bitrate/$edition/$globalAyahNumber.mp3';
}

/// Returns the exact audio source paired with timing data when available.
/// EveryAyah's per-ayah filenames use three-digit surah and ayah numbers.
String recitationAudioUrl(QuranReciter reciter, int surahNumber, int ayahNumber, int globalAyahNumber) {
  if (surahNumber < 1 || surahNumber > 114 || ayahNumber < 1 || ayahNumber > 286) {
    throw RangeError('Invalid surah/ayah: $surahNumber:$ayahNumber');
  }
  final folder = reciter.everyAyahFolder ?? reciter.timingFolder;
  if (folder != null) {
    final surah = surahNumber.toString().padLeft(3, '0');
    final ayah = ayahNumber.toString().padLeft(3, '0');
    return 'https://everyayah.com/data/$folder/$surah$ayah.mp3';
  }
  return ayahAudioUrl(reciter.id, globalAyahNumber, bitrate: reciter.bitrate);
}

class RecitationTimingSegment {
  final int wordStartIndex;
  final int wordEndIndex;
  final int startMs;
  final int endMs;

  const RecitationTimingSegment({
    required this.wordStartIndex,
    required this.wordEndIndex,
    required this.startMs,
    required this.endMs,
  });

  factory RecitationTimingSegment.fromList(List<dynamic> values) => RecitationTimingSegment(
        wordStartIndex: (values[0] as num).toInt(),
        wordEndIndex: (values[1] as num).toInt(),
        startMs: (values[2] as num).toInt(),
        endMs: (values[3] as num).toInt(),
      );
}

/// Which word(s) are currently being recited; word indices are zero-based.
class ActiveRecitationWord {
  final String ayahKey;
  final int wordStartIndex;
  final int wordEndIndex;

  const ActiveRecitationWord({
    required this.ayahKey,
    required this.wordStartIndex,
    required this.wordEndIndex,
  });

  bool sameAs(ActiveRecitationWord? other) =>
      other != null &&
      ayahKey == other.ayahKey &&
      wordStartIndex == other.wordStartIndex &&
      wordEndIndex == other.wordEndIndex;
}

Map<String, List<RecitationTimingSegment>> parseWordTimingData(
  Map<String, dynamic> root,
  String edition,
) {
  final rawReciters = root['reciters'];
  if (rawReciters is! Map) return const {};
  final rawEdition = rawReciters[edition];
  if (rawEdition is! Map) return const {};
  final rawVerses = rawEdition['verses'];
  if (rawVerses is! Map) return const {};
  final parsed = <String, List<RecitationTimingSegment>>{};
  for (final entry in rawVerses.entries) {
    if (entry.value is! List) continue;
    final segments = <RecitationTimingSegment>[];
    for (final raw in entry.value as List) {
      if (raw is! List || raw.length < 4) continue;
      try {
        final segment = RecitationTimingSegment.fromList(raw);
        if (segment.wordStartIndex >= 0 &&
            segment.wordEndIndex > segment.wordStartIndex &&
            segment.startMs >= 0 &&
            segment.endMs > segment.startMs) {
          segments.add(segment);
        }
      } catch (_) {
        // Skip malformed rows without affecting the remaining timing data.
      }
    }
    if (segments.isNotEmpty) {
      segments.sort((a, b) => a.startMs.compareTo(b.startMs));
      parsed[entry.key.toString()] = segments;
    }
  }
  return parsed;
}

final ValueNotifier<ActiveRecitationWord?> activeRecitationWord = ValueNotifier<ActiveRecitationWord?>(null);

int globalAyahNumberFor(QuranRepository repository, Ayah ayah) {
  final index = repository.allAyahs.indexWhere((candidate) => candidate.key == ayah.key);
  if (index < 0) throw ArgumentError.value(ayah.key, 'ayah', 'Ayah is not in this Quran repository');
  return index + 1;
}

Color _mutedColor(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
Color _borderColor(BuildContext context) => Theme.of(context).dividerColor;
Color _softSurfaceColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF252D29)
    : const Color(0xFFF0EEE7);
Color _arabicWordSurfaceColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF252D29)
    : const Color(0xFFFFFCF4);


/// The same brand mark is used in the splash/loading screen, navigation drawer,
/// reader header and About dialog. The icon fallback prevents a blank UI if an
/// asset is accidentally omitted from a development build.
Widget alQariBrandMark({double size = 56, double radius = 16}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        appLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: forest,
          child: Icon(Icons.menu_book_rounded, color: gold, size: size * 0.58),
        ),
      ),
    );

/// Quran-focused Arabic typeface with Quranic notation support.
/// google_fonts caches the downloaded font after its first successful load.
TextStyle quranTextStyle(BuildContext context, {
  required double fontSize,
  double height = 2.0,
  Color? color,
  FontWeight fontWeight = FontWeight.normal,
}) {
  final fallback = TextStyle(
    fontSize: fontSize,
    height: height,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontWeight: fontWeight,
    fontFamilyFallback: const ['Noto Naskh Arabic', 'Noto Sans Arabic', 'serif'],
  );
  return GoogleFonts.getFont(quranFontFamily, textStyle: fallback);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
  }
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.alqari.app.channel.audio',
    androidNotificationChannelName: 'Quran recitation',
    androidNotificationOngoing: true,
  );
  runApp(const AlQari());
}

/// Removes Arabic harakat for tolerant local search; it never modifies the
/// source text shown in the Quran reader.
String removeQuranMarks(String value) => value
    .replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
    .replaceAll('ـ', '')
    .trim();

String uiText(String language, String key) {
  const values = <String, Map<String, String>>{
    'app': {'en': 'AlQari', 'ur': 'القرآن سیکھیں', 'sd': 'القرآن سکو'},
    'tagline': {'en': 'Read • Understand • Reflect', 'ur': 'پڑھیں • سمجھیں • غور کریں', 'sd': 'پڙهو • سمجھو • غور ڪريو'},
    'reader': {'en': 'Quran Reader', 'ur': 'قرآن ریڈر', 'sd': 'قرآن پڙهڻ'},
    'readSubtitle': {'en': 'Choose a Surah or Juz to continue.', 'ur': 'جاری رکھنے کے لیے سورت یا پارہ منتخب کریں۔', 'sd': 'جاري رکڻ لاءِ سورت يا پارو چونڊيو.'},
    'versesInSection': {'en': 'ayat in this section', 'ur': 'آیات اس حصے میں', 'sd': 'آيتون هن حصي ۾'},
    'settingsAppearance': {'en': 'Settings & appearance', 'ur': 'ترتیبات اور ظاہری شکل', 'sd': 'سيٽنگون ۽ ظاهر'},
    'recitation': {'en': 'Quran recitation', 'ur': 'قرآن کی تلاوت', 'sd': 'قرآن جي تلاوت'},
    'listenRecitation': {'en': 'Listen to recitation', 'ur': 'تلاوت سنیں', 'sd': 'تلاوت ٻڌو'},
    'chooseReciter': {'en': 'Choose a Qari', 'ur': 'قاری منتخب کریں', 'sd': 'قاري چونڊيو'},
    'chooseAudioSurah': {'en': 'Choose Surah', 'ur': 'سورۃ منتخب کریں', 'sd': 'سورت چونڊيو'},
    'streamAudioNote': {'en': 'Streaming needs an internet connection. Ayat play in order and advance automatically.', 'ur': 'آڈیو چلانے کے لیے انٹرنیٹ درکار ہے۔ آیات ترتیب سے خود بخود چلیں گی۔', 'sd': 'آڊيو لاءِ انٽرنيٽ گهرجي. آيتون ترتيب سان پاڻمرادو هلنديون.'},
    'loadingAudio': {'en': 'Preparing recitation…', 'ur': 'تلاوت تیار ہو رہی ہے…', 'sd': 'تلاوت تيار ٿي رهي آهي…'},
    'audioError': {'en': 'Audio could not be loaded. Check your internet connection and try again.', 'ur': 'آڈیو نہیں چل سکی۔ انٹرنیٹ چیک کرکے دوبارہ کوشش کریں۔', 'sd': 'آڊيو نه هلي سگهي. انٽرنيٽ چيڪ ڪري ٻيهر ڪوشش ڪريو.'},
    'currentAyah': {'en': 'Now reciting', 'ur': 'اس وقت تلاوت', 'sd': 'هن وقت تلاوت'},
    'audioSourceNote': {'en': 'Ayah audio streams from Al Quran Cloud CDN or EveryAyah depending on the selected reciter. Word timings are from cpfair/quran-align (CC BY 4.0). Recordings remain subject to their respective rights and provider terms; verify permission before public/commercial release.', 'ur': 'منتخب قاری کے مطابق آیات کی آڈیو Al Quran Cloud CDN یا EveryAyah سے چلتی ہے۔ لفظوں کے اوقات cpfair/quran-align (CC BY 4.0) سے ہیں۔ ریکارڈنگز کے حقوق اور فراہم کنندہ کی شرائط لاگو رہتی ہیں؛ عوامی ریلیز سے پہلے اجازت کی تصدیق کریں۔', 'sd': 'چونڊيل قاري موجب آيتن جو آڊيو Al Quran Cloud CDN يا EveryAyah تان هلي ٿو. لفظن جا وقت cpfair/quran-align (CC BY 4.0) مان آهن. رڪارڊنگ جا حق ۽ فراهم ڪندڙ جون شرطون لاڳو آهن؛ عوامي رليز کان اڳ اجازت پڪ ڪريو.'},
    'search': {'en': 'Search', 'ur': 'تلاش', 'sd': 'ڳولا'},
    'bookmarks': {'en': 'Bookmarks', 'ur': 'محفوظ آیات', 'sd': 'محفوظ آيتون'},
    'settings': {'en': 'Settings', 'ur': 'ترتیبات', 'sd': 'سيٽنگون'},
    'continueReading': {'en': 'Continue reading', 'ur': 'پڑھنا جاری رکھیں', 'sd': 'پڙهڻ جاري رکو'},
    'home': {'en': 'Home', 'ur': 'ہوم', 'sd': 'گهر'},
    'homeTab': {'en': 'Home', 'ur': 'ہوم', 'sd': 'گهر'},
    'quranTab': {'en': 'Quran', 'ur': 'قرآن', 'sd': 'قرآن'},
    'more': {'en': 'More', 'ur': 'مزید', 'sd': 'وڌيڪ'},
    'homeHeadline': {'en': 'Your Quran journey, made calmer.', 'ur': 'قرآن کے سفر کو آسان بنائیں۔', 'sd': 'قرآن جو سفر وڌيڪ آسان بڻايو.'},
    'welcomeHome': {'en': 'Read. Understand. Reflect.', 'ur': 'پڑھیں۔ سمجھیں۔ غور کریں۔', 'sd': 'پڙهو. سمجھو. غور ڪريو.'},
    'quickAccess': {'en': 'Quick access', 'ur': 'فوری رسائی', 'sd': 'جلدي رسائي'},
    'dailyReflection': {'en': 'A verse to reflect on', 'ur': 'غور و فکر کے لیے ایک آیت', 'sd': 'غور ڪرڻ لاءِ هڪ آيت'},
    'libraryStats': {'en': 'Your Quran library', 'ur': 'قرآن کا ذخیرہ', 'sd': 'قرآن جو ذخيرو'},
    'startReading': {'en': 'Start reading', 'ur': 'پڑھنا شروع کریں', 'sd': 'پڙهڻ شروع ڪريو'},
    'searchQuran': {'en': 'Search Quran', 'ur': 'قرآن میں تلاش', 'sd': 'قرآن ۾ ڳولا'},
    'translationTools': {'en': 'Language & translation', 'ur': 'زبان اور ترجمہ', 'sd': 'ٻولي ۽ ترجمو'},
    'wordTapHint': {'en': 'Tap any Arabic word while reading to open its available word analysis.', 'ur': 'قرآن پڑھتے ہوئے کسی عربی لفظ پر ٹیپ کریں تاکہ دستیاب لفظی تجزیہ کھلے۔', 'sd': 'پڙهندي ڪنهن عربي لفظ تي ٽيپ ڪريو ته موجود لفظي تجزيو کلي.'},
    'savedAyat': {'en': 'saved ayat', 'ur': 'محفوظ آیات', 'sd': 'محفوظ آيتون'},
    'surahs': {'en': 'Surahs', 'ur': 'سورتیں', 'sd': 'سورتون'},
    'ayat': {'en': 'Ayat', 'ur': 'آیات', 'sd': 'آيتون'},
    'languagesCount': {'en': 'Languages', 'ur': 'زبانیں', 'sd': 'ٻوليون'},
    'noProgress': {'en': 'Your last-read ayah will appear here after you open a verse.', 'ur': 'آیت کھولنے کے بعد آپ کی آخری پڑھی گئی آیت یہاں دکھائی دے گی۔', 'sd': 'آيت کولڻ کان پوءِ آخري پڙهيل آيت هتي ڏيکاري ويندي.'},
    'browseFeatures': {'en': 'Explore reading, listening, and saved ayat.', 'ur': 'تلاوت، سننے اور محفوظ آیات کو دیکھیں۔', 'sd': 'پڙهڻ، ٻڌڻ ۽ محفوظ آيتون ڏسو.'},
    'appearance': {'en': 'Appearance & themes', 'ur': 'ظاہری شکل اور تھیم', 'sd': 'رنگ ۽ ٿيم'},
    'systemTheme': {'en': 'System', 'ur': 'سسٹم', 'sd': 'سسٽم'},
    'lightTheme': {'en': 'Light', 'ur': 'لائٹ', 'sd': 'روشن'},
    'darkTheme': {'en': 'Dark', 'ur': 'ڈارک', 'sd': 'اونداهو'},
    'accentColor': {'en': 'Accent colour', 'ur': 'رنگ منتخب کریں', 'sd': 'رنگ چونڊيو'},
    'lastRead': {'en': 'Last opened ayah', 'ur': 'آخری کھولی گئی آیت', 'sd': 'آخري کوليل آيت'},
    'selectJuz': {'en': 'Select Juz / Para', 'ur': 'پارہ منتخب کریں', 'sd': 'پارو چونڊيو'},
    'selectSurah': {'en': 'Select Surah', 'ur': 'سورۃ منتخب کریں', 'sd': 'سورت چونڊيو'},
    'juzMode': {'en': 'Juz / Para', 'ur': 'پارہ', 'sd': 'پارو'},
    'surahMode': {'en': 'Surah', 'ur': 'سورۃ', 'sd': 'سورت'},
    'translation': {'en': 'Translation of meaning', 'ur': 'ترجمۂ مفہوم', 'sd': 'مفهوم جو ترجمو'},
    'translationLanguage': {'en': 'Translation language', 'ur': 'ترجمے کی زبان', 'sd': 'ترجمي جي ٻولي'},
    'wordAnalysis': {'en': 'Quranic Linguistics', 'ur': 'لسانیاتِ قرآن', 'sd': 'قرآن جي لسانيات'},
    'wordMeaning': {'en': 'Word meaning', 'ur': 'لفظی معنی', 'sd': 'لفظي معنيٰ'},
    'root': {'en': 'Root (Jذر)', 'ur': 'مادہ', 'sd': 'مادو'},
    'lemma': {'en': 'Lemma / dictionary form', 'ur': 'اصل لغوی صورت', 'sd': 'لغوي اصل صورت'},
    'pos': {'en': 'Part of speech (Nahw aid)', 'ur': 'قسمِ کلمہ (نحو میں مدد)', 'sd': 'ڪلمي جو قسم (نحو لاءِ مدد)'},
    'sarf': {'en': 'Sarf · morphology', 'ur': 'صرف · ساختِ لفظ', 'sd': 'صرف · لفظي بناوت'},
    'nahw': {'en': 'Nahw · syntax aid', 'ur': 'نحو · ترکیب میں مدد', 'sd': 'نحو · جملي جي بناوت'},
    'irab': {'en': 'I‘rab · case / mood tags', 'ur': 'اعراب · حالت / صیغے کی علامات', 'sd': 'اعراب · حالت / صيغو'},
    'morphology': {'en': 'Source morphology segments', 'ur': 'ماخذ میں لفظی اجزاء', 'sd': 'ماخذ ۾ لفظ جا جزا'},
    'onlineGloss': {'en': 'Online word-by-word gloss', 'ur': 'آن لائن لفظی معنی', 'sd': 'آن لائن لفظي معنيٰ'},
    'glossLoading': {'en': 'Looking up the word meaning…', 'ur': 'لفظی معنی تلاش ہو رہے ہیں…', 'sd': 'لفظي معنيٰ ڳوليا پيا وڃن…'},
    'glossUnavailable': {'en': 'Word gloss is not available right now. The local morphology and verse translation remain available.', 'ur': 'اس وقت لفظی معنی دستیاب نہیں۔ مقامی صرفی تجزیہ اور آیت کا ترجمہ موجود ہے۔', 'sd': 'هن وقت لفظي معنيٰ موجود نه آهي. مقامي صرفي تجزيو ۽ آيت جو ترجمو موجود آهي.'},
    'glossLanguageNote': {'en': 'Word-by-word gloss may be available only in English or Urdu from the online source. The selected-language verse translation is shown separately.', 'ur': 'آن لائن ماخذ سے لفظی معنی صرف انگریزی یا اردو میں دستیاب ہو سکتے ہیں۔ منتخب زبان کا آیت ترجمہ الگ دکھایا گیا ہے۔', 'sd': 'آن لائن ماخذ مان لفظي معنيٰ رڳو انگريزي يا اردو ۾ ملي سگهن ٿا. چونڊيل ٻوليءَ ۾ آيت جو ترجمو الڳ ڏيکاريل آهي.'},
    'searchHint': {'en': 'Search Arabic or a translation…', 'ur': 'عربی یا ترجمے میں تلاش کریں…', 'sd': 'عربي يا ترجمي ۾ ڳوليو…'},
    'searchPrompt': {'en': 'Type at least two characters to search all 6,236 ayat.', 'ur': 'تمام 6,236 آیات میں تلاش کے لیے کم از کم دو حروف لکھیں۔', 'sd': 'سڀني 6,236 آيتن ۾ ڳولڻ لاءِ گهٽ ۾ گهٽ ٻه اکر لکو.'},
    'noResults': {'en': 'No matching ayat found.', 'ur': 'کوئی مطابقت رکھنے والی آیت نہیں ملی۔', 'sd': 'ڪا به ملندڙ آيت نه ملي.'},
    'removeBookmark': {'en': 'Remove bookmark', 'ur': 'محفوظ فہرست سے ہٹائیں', 'sd': 'محفوظ فهرست مان هٽايو'},
    'bookmark': {'en': 'Bookmark ayah', 'ur': 'آیت محفوظ کریں', 'sd': 'آيت محفوظ ڪريو'},
    'bookmarked': {'en': 'Bookmarked', 'ur': 'محفوظ ہے', 'sd': 'محفوظ آهي'},
    'language': {'en': 'Interface language', 'ur': 'ایپ کی زبان', 'sd': 'ايپ جي ٻولي'},
    'english': {'en': 'English', 'ur': 'English', 'sd': 'English'},
    'urdu': {'en': 'Urdu', 'ur': 'اردو', 'sd': 'اردو'},
    'sindhi': {'en': 'Sindhi', 'ur': 'سندھی', 'sd': 'سنڌي'},
    'arabicSize': {'en': 'Arabic text size', 'ur': 'عربی متن کا سائز', 'sd': 'عربي متن جو ماپ'},
    'about': {'en': 'About this app', 'ur': 'ایپ کے بارے میں', 'sd': 'ايپ بابت'},
    'fullCoverage': {'en': 'Complete Quran data', 'ur': 'مکمل قرآن کا مواد', 'sd': 'مڪمل قرآن جو مواد'},
    'verseCount': {'en': '6,236 ayat · 114 surahs', 'ur': '6,236 آیات · 114 سورتیں', 'sd': '6,236 آيتون · 114 سورتون'},
    'offlineNote': {'en': 'Reader, translations, search, bookmarks, and corpus morphology work offline. Word-by-word gloss lookup needs an internet connection.', 'ur': 'قرآن، تراجم، تلاش، محفوظ آیات اور صرفی معلومات آف لائن کام کرتی ہیں۔ لفظی معنی کے لیے انٹرنیٹ درکار ہے۔', 'sd': 'قرآن، ترجما، ڳولا، محفوظ آيتون ۽ صرفي ڄاڻ آف لائن ڪم ڪن ٿا. لفظي معنيٰ لاءِ انٽرنيٽ کپي.'},
    'sourceNotice': {'en': 'Sources & attribution', 'ur': 'مآخذ اور حوالہ', 'sd': 'ذريعا ۽ حوالا'},
    'loading': {'en': 'Preparing the Quran library…', 'ur': 'قرآن کا ذخیرہ تیار ہو رہا ہے…', 'sd': 'قرآن جو ذخيرو تيار ٿي رهيو آهي…'},
    'loadError': {'en': 'The full Quran data is missing from this build.', 'ur': 'اس بلڈ میں مکمل قرآن کا مواد موجود نہیں۔', 'sd': 'هن بلڊ ۾ قرآن جو مڪمل مواد موجود ناهي.'},
    'tryAgain': {'en': 'Try again', 'ur': 'دوبارہ کوشش کریں', 'sd': 'ٻيهر ڪوشش ڪريو'},
    'verseMeaning': {'en': 'Ayah meaning', 'ur': 'آیت کا ترجمہ', 'sd': 'آيت جو ترجمو'},
    'surah': {'en': 'Surah', 'ur': 'سورۃ', 'sd': 'سورت'},
    'juz': {'en': 'Juz / Para', 'ur': 'پارہ', 'sd': 'پارو'},
    'verse': {'en': 'Ayah', 'ur': 'آیت', 'sd': 'آيت'},
    'noMorph': {'en': 'No corpus morphology entry was found for this token.', 'ur': 'اس لفظ کے لیے ماخذ میں صرفی اندراج نہیں ملا۔', 'sd': 'هن لفظ لاءِ ماخذ ۾ صرفي داخلا نه ملي.'},
    'noRoot': {'en': 'Not tagged with a root in the source.', 'ur': 'ماخذ میں مادہ درج نہیں۔', 'sd': 'ماخذ ۾ مادو درج ناهي.'},
    'selectedVerse': {'en': 'Selected ayah', 'ur': 'منتخب آیت', 'sd': 'چونڊيل آيت'},
    'change': {'en': 'Change', 'ur': 'تبدیل کریں', 'sd': 'تبديل ڪريو'},
    'prayerTimes': {'en': 'Prayer Times & Adhan', 'ur': 'نماز کے اوقات اور اذان', 'sd': 'نماز جا وقت ۽ اذان'},
    'prayerSubtitle': {'en': 'Local prayer times and scheduled Adhan reminders.', 'ur': 'مقامی نماز کے اوقات اور اذان یاددہانیاں۔', 'sd': 'مقامي نماز جا وقت ۽ اذان ياد ڏيارڻ.'},
    'enablePrayerAlerts': {'en': 'Use location & schedule Adhan', 'ur': 'مقام سے اذان مقرر کریں', 'sd': 'هنڌ سان اذان مقرر ڪريو'},
    'updatePrayerAlerts': {'en': 'Refresh location & reminders', 'ur': 'مقام اور یاددہانی تازہ کریں', 'sd': 'هنڌ ۽ ياد ڏيارڻ اپڊيٽ ڪريو'},
    'prayerLoading': {'en': 'Loading prayer times…', 'ur': 'نماز کے اوقات لوڈ ہو رہے ہیں…', 'sd': 'نماز جا وقت لوڊ ٿي رهيا آهن…'},
    'prayerLocationNote': {'en': 'Your coordinates calculate times and schedule reminders on this device. They are not sent to AlQari servers.', 'ur': 'آپ کے مقام سے اوقات نکال کر اسی ڈیوائس پر یاددہانیاں لگائی جاتی ہیں؛ مقام AlQari سرور کو نہیں بھیجا جاتا۔', 'sd': 'هنڌ مان وقت ڪڍي هن ئي ڊوائيس تي ياد ڏيارڻ لڳايا وڃن ٿا؛ هنڌ AlQari سرور ڏانهن نٿو وڃي.'},
    'prayerReminderNote': {'en': 'Notifications require permission. Delivery depends on Android alarm, battery and device settings; the OS may shorten a long notification sound.', 'ur': 'یاددہانی کے لیے نوٹیفکیشن اجازت ضروری ہے۔ وقت Android الارم، بیٹری اور فون کی سیٹنگز پر منحصر ہے؛ نظام لمبی آواز مختصر کر سکتا ہے۔', 'sd': 'ياد ڏيارڻ لاءِ نوٽيفڪيشن اجازت کپي. وقت Android الارم، بيٽري ۽ فون جي سيٽنگن تي دارومدار رکي ٿو؛ نظام ڊگهي آواز مختصر ڪري سگهي ٿو.'},
    'fajr': {'en': 'Fajr', 'ur': 'فجر', 'sd': 'فجر'},
    'dhuhr': {'en': 'Dhuhr', 'ur': 'ظہر', 'sd': 'ظهر'},
    'asr': {'en': 'Asr', 'ur': 'عصر', 'sd': 'عصر'},
    'maghrib': {'en': 'Maghrib', 'ur': 'مغرب', 'sd': 'مغرب'},
    'isha': {'en': 'Isha', 'ur': 'عشاء', 'sd': 'عشاء'},
  };
  return values[key]?[language] ?? values[key]?['en'] ?? key;
}

bool isRtl(String language) => language == 'ur' || language == 'sd';

class Ayah {
  final int surahNumber;
  final int number;
  final String key;
  final String arabic;
  final Map<String, String> translations;
  final int juz;
  final int page;
  final int hizbQuarter;
  final int ruku;
  final int manzil;
  final dynamic sajda;

  const Ayah({
    required this.surahNumber,
    required this.number,
    required this.key,
    required this.arabic,
    required this.translations,
    required this.juz,
    required this.page,
    required this.hizbQuarter,
    required this.ruku,
    required this.manzil,
    required this.sajda,
  });

  factory Ayah.fromJson(int surahNumber, Map<String, dynamic> json) => Ayah(
        surahNumber: surahNumber,
        number: (json['number'] as num).toInt(),
        key: json['key'] as String,
        arabic: json['arabic'] as String,
        translations: (json['translations'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        juz: (json['juz'] as num?)?.toInt() ?? 1,
        page: (json['page'] as num?)?.toInt() ?? 0,
        hizbQuarter: (json['hizbQuarter'] as num?)?.toInt() ?? 0,
        ruku: (json['ruku'] as num?)?.toInt() ?? 0,
        manzil: (json['manzil'] as num?)?.toInt() ?? 0,
        sajda: json['sajda'],
      );

  String translationFor(String language) => translations['ur'] ?? '';
}

class Surah {
  final int number;
  final String nameArabic;
  final String nameEnglish;
  final String nameMeaning;
  final String revelationType;
  final int numberOfAyahs;
  final List<Ayah> ayahs;

  const Surah({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.nameMeaning,
    required this.revelationType,
    required this.numberOfAyahs,
    required this.ayahs,
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    final number = (json['number'] as num).toInt();
    final rawAyahs = json['verses'] as List<dynamic>;
    final ayahs = rawAyahs
        .map((e) => Ayah.fromJson(number, e as Map<String, dynamic>))
        .toList(growable: false);
    return Surah(
      number: number,
      nameArabic: json['nameArabic']?.toString() ?? '',
      nameEnglish: json['nameEnglish']?.toString() ?? '',
      nameMeaning: json['nameMeaning']?.toString() ?? '',
      revelationType: json['revelationType']?.toString() ?? '',
      numberOfAyahs: (json['numberOfAyahs'] as num).toInt(),
      ayahs: ayahs,
    );
  }
}

class MorphSegment {
  final String form;
  final String tag;
  final String features;
  const MorphSegment(this.form, this.tag, this.features);
}

class WordMorphology {
  final String root;
  final String lemma;
  final String pos;
  final List<String> features;
  final List<MorphSegment> segments;

  const WordMorphology({
    this.root = '',
    this.lemma = '',
    this.pos = '',
    this.features = const [],
    this.segments = const [],
  });

  String featureLine(String language) {
    if (features.isEmpty) return uiText(language, 'noMorph');
    return features.join(' · ');
  }

  String sarfDescription(String language) {
    final list = features;
    final found = <String>[];
    if (list.contains('PERF')) found.add(_label(language, 'PERF'));
    if (list.contains('IMPF')) found.add(_label(language, 'IMPF'));
    if (list.contains('IMPV')) found.add(_label(language, 'IMPV'));
    for (final form in const ['(II)', '(III)', '(IV)', '(V)', '(VI)', '(VII)', '(VIII)', '(IX)', '(X)', '(XI)', '(XII)']) {
      if (list.contains(form)) found.add('${_label(language, 'VERB_FORM')} ${form.substring(1, form.length - 1)}');
    }
    if (list.contains('PASS')) found.add(_label(language, 'PASS'));
    if (list.contains('ACT')) found.add(_label(language, 'ACT'));
    final person = list.where((f) => RegExp(r'^[123][MSFDP]{1,2}$').hasMatch(f)).toList();
    found.addAll(person);
    return found.isEmpty ? featureLine(language) : found.join(' · ');
  }

  String irabDescription(String language) {
    final result = <String>[];
    if (features.contains('NOM') || features.contains('CASE:NOM')) result.add(_label(language, 'NOM'));
    if (features.contains('ACC') || features.contains('CASE:ACC')) result.add(_label(language, 'ACC'));
    if (features.contains('GEN') || features.contains('CASE:GEN')) result.add(_label(language, 'GEN'));
    if (features.contains('MOOD:SUBJ') || features.contains('SUBJ')) result.add(_label(language, 'SUBJ'));
    if (features.contains('MOOD:JUS') || features.contains('JUS')) result.add(_label(language, 'JUS'));
    if (features.contains('MOOD:IND') || features.contains('IND')) result.add(_label(language, 'IND'));
    if (features.contains('DEF') || features.contains('STATE:DEF')) result.add(_label(language, 'DEF'));
    if (features.contains('INDEF') || features.contains('STATE:INDEF')) result.add(_label(language, 'INDEF'));
    return result.isEmpty ? _label(language, 'CASE_NOT_TAGGED') : result.join(' · ');
  }

  static String _label(String lang, String key) {
    const words = {
      'PERF': {'en': 'Perfect (past) verb', 'ur': 'فعلِ ماضی', 'sd': 'فعل ماضي'},
      'IMPF': {'en': 'Imperfect (present/future) verb', 'ur': 'فعلِ مضارع', 'sd': 'فعل مضارع'},
      'IMPV': {'en': 'Imperative verb', 'ur': 'فعلِ امر', 'sd': 'فعل امر'},
      'VERB_FORM': {'en': 'Form', 'ur': 'باب', 'sd': 'باب'},
      'PASS': {'en': 'Passive voice', 'ur': 'مجہول', 'sd': 'مجهول'},
      'ACT': {'en': 'Active voice', 'ur': 'معروف', 'sd': 'معلوم'},
      'NOM': {'en': 'Nominative / marfūʿ', 'ur': 'مرفوع', 'sd': 'مرفوع'},
      'ACC': {'en': 'Accusative / manṣūb', 'ur': 'منصوب', 'sd': 'منصوب'},
      'GEN': {'en': 'Genitive / majrūr', 'ur': 'مجرور', 'sd': 'مجرور'},
      'SUBJ': {'en': 'Subjunctive mood', 'ur': 'منصوب صیغہ', 'sd': 'منصوب صيغو'},
      'JUS': {'en': 'Jussive mood', 'ur': 'مجزوم صیغہ', 'sd': 'مجزوم صيغو'},
      'IND': {'en': 'Indicative mood', 'ur': 'مرفوع صیغہ', 'sd': 'مرفوع صيغو'},
      'DEF': {'en': 'Definite', 'ur': 'معرفہ', 'sd': 'معرفو'},
      'INDEF': {'en': 'Indefinite', 'ur': 'نکرہ', 'sd': 'نڪرو'},
      'CASE_NOT_TAGGED': {'en': 'No case or mood tag is recorded for this token.', 'ur': 'اس لفظ کے لیے اعرابی حالت کی علامت درج نہیں۔', 'sd': 'هن لفظ لاءِ اعرابي حالت جي نشاني درج ناهي.'},
    };
    return words[key]?[lang] ?? words[key]?['en'] ?? key;
  }
}

class QuranRepository {
  final List<Surah> surahs;
  final Map<String, WordMorphology> morphology;
  final Map<String, dynamic> dataManifest;
  final Map<int, Surah> _surahIndex;
  final List<Ayah> allAyahs;

  QuranRepository._(this.surahs, this.morphology, this.dataManifest)
      : _surahIndex = {for (final s in surahs) s.number: s},
        allAyahs = surahs.expand((s) => s.ayahs).toList(growable: false);

  static Future<QuranRepository> load() async {
    final quranRaw = await rootBundle.loadString('assets/data/quran.json');
    final quran = jsonDecode(quranRaw) as Map<String, dynamic>;
    final rawSurahs = quran['surahs'] as List<dynamic>;
    final surahs = rawSurahs
        .map((s) => Surah.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
    final total = surahs.fold<int>(0, (sum, s) => sum + s.ayahs.length);
    if (surahs.length != 114 || total != 6236) {
      throw FormatException('Full Quran data validation failed: ${surahs.length} surahs / $total ayat. Expected 114 / 6236.');
    }
    final morphologyRaw = await rootBundle.loadString('assets/data/quran-morphology.txt');
    final manifestRaw = await rootBundle.loadString('assets/data/data_manifest.json');
    final morphology = _parseMorphology(morphologyRaw);
    return QuranRepository._(surahs, morphology, jsonDecode(manifestRaw) as Map<String, dynamic>);
  }

  Surah? surah(int number) => _surahIndex[number];
  WordMorphology? wordMorphology(int surahNumber, int ayahNumber, int wordNumber) =>
      morphology['$surahNumber:$ayahNumber:$wordNumber'];

  static Map<String, WordMorphology> _parseMorphology(String source) {
    final grouped = <String, List<MorphSegment>>{};
    final rootByKey = <String, String>{};
    final lemmaByKey = <String, String>{};
    final posByKey = <String, String>{};
    final featureSetByKey = <String, Set<String>>{};
    final locationPattern = RegExp(r'^\(?(\d+):(\d+):(\d+):(\d+)\)?$');
    for (final line in const LineSplitter().convert(source)) {
      if (line.trim().isEmpty || line.trimLeft().toUpperCase().startsWith('LOCATION')) continue;
      List<String> parts = line.split('\t');
      if (parts.length < 4) {
        final m = RegExp(r'^\(?(\d+:\d+:\d+:\d+)\)?\s+(\S+)\s+(\S+)\s+(.+)$').firstMatch(line);
        if (m == null) continue;
        parts = [m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!];
      }
      if (parts.length < 4) continue;
      final location = parts[0].trim();
      final match = locationPattern.firstMatch(location);
      if (match == null) continue;
      final s = int.tryParse(match.group(1)!);
      final a = int.tryParse(match.group(2)!);
      final w = int.tryParse(match.group(3)!);
      if (s == null || a == null || w == null) continue;
      final key = '$s:$a:$w';
      final form = parts[1].trim();
      final tag = parts[2].trim();
      final rawFeatures = parts.sublist(3).join('\t').trim();
      grouped.putIfAbsent(key, () => <MorphSegment>[]).add(MorphSegment(form, tag, rawFeatures));
      for (final token in rawFeatures.split('|')) {
        final feature = token.trim();
        if (feature.isEmpty) continue;
        if (feature.startsWith('ROOT:')) {
          rootByKey.putIfAbsent(key, () => _buckwalterToArabic(feature.substring(5)));
        } else if (feature.startsWith('LEM:')) {
          lemmaByKey.putIfAbsent(key, () => _buckwalterToArabic(feature.substring(4)));
        } else if (feature.startsWith('POS:')) {
          posByKey[key] = feature.substring(4);
        }
        if (!feature.startsWith('ROOT:') && !feature.startsWith('LEM:') && !feature.startsWith('POS:') &&
            feature != 'STEM' && feature != 'PREFIX' && feature != 'SUFFIX') {
          featureSetByKey.putIfAbsent(key, () => <String>{}).add(feature);
        }
      }
      if (tag.isNotEmpty) posByKey.putIfAbsent(key, () => tag);
    }
    final result = <String, WordMorphology>{};
    for (final entry in grouped.entries) {
      final sorted = featureSetByKey[entry.key]?.toList() ?? <String>[];
      result[entry.key] = WordMorphology(
        root: rootByKey[entry.key] ?? '',
        lemma: lemmaByKey[entry.key] ?? '',
        pos: posByKey[entry.key] ?? '',
        features: sorted,
        segments: entry.value,
      );
    }
    if (result.length < 70000) {
      throw FormatException('Morphology file appears incomplete (${result.length} token positions).');
    }
    return result;
  }

  static String _buckwalterToArabic(String value) {
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(value)) return value;
    
const map = <String, String>{
  "'": 'ء',
  '>': 'أ',
  '&': 'ؤ',
  '<': 'إ',
  '}': 'ئ',
  'A': 'ا',
  'b': 'ب',
  'p': 'ة',
  't': 'ت',
  'v': 'ث',
  'j': 'ج',
  'H': 'ح',
  'x': 'خ',
  'd': 'د',
  '*': 'ذ',
  'r': 'ر',
  'z': 'ز',
  's': 'س',
  r'$': 'ش',
  'S': 'ص',
  'D': 'ض',
  'T': 'ط',
  'Z': 'ظ',
  'E': 'ع',
  'g': 'غ',
  'f': 'ف',
  'q': 'ق',
  'k': 'ك',
  'l': 'ل',
  'm': 'م',
  'n': 'ن',
  'h': 'ه',
  'w': 'و',
  'Y': 'ى',
  'y': 'ي',
  '`': 'ٰ',
  '{': 'ٱ',
  '|': 'آ',
  '^': 'ٓ',
  '~': 'ْ',
  'o': 'ٌ',
  'a': 'َ',
  'u': 'ُ',
  'i': 'ِ',
};

    final out = StringBuffer();
    for (final rune in value.runes) {
      final c = String.fromCharCode(rune);
      out.write(map[c] ?? c);
    }
    return out.toString();
  }
}

class OnlineWordGloss {
  final String? gloss;
  final String? transliteration;
  final String? root;
  final String? lemma;
  final String? grammar;
  const OnlineWordGloss({this.gloss, this.transliteration, this.root, this.lemma, this.grammar});
}

Future<OnlineWordGloss?> fetchWordGloss(String verseKey, int position, String language) async {
  // Word-by-word gloss is requested on demand; it is not redistributed in the APK.
  // Quran Foundation's endpoint currently reliably supplies English and Urdu glosses.
  final glossLanguage = language == 'ur' ? 'ur' : 'en';
  final uri = Uri.https('api.quran.com', '/api/v4/verses/by_key/$verseKey', {
    'words': 'true',
    'word_fields': 'text_uthmani,translation,transliteration',
    'word_translation_language': glossLanguage,
  });
  try {
    final response = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final verse = body['verse'] as Map<String, dynamic>? ?? body['data'] as Map<String, dynamic>?;
    if (verse == null) return null;
    final words = verse['words'] as List<dynamic>? ?? const [];
    Map<String, dynamic>? match;
    for (var i = 0; i < words.length; i++) {
      final item = words[i] as Map<String, dynamic>;
      final itemPosition = (item['position'] as num?)?.toInt() ?? i + 1;
      if (itemPosition == position && (item['char_type_name']?.toString() != 'end')) {
        match = item;
        break;
      }
    }
    if (match == null) return null;
    final translation = match['translation'];
    String? gloss;
    if (translation is Map<String, dynamic>) gloss = translation['text']?.toString();
    if (translation is String) gloss = translation;
    final transliterationRaw = match['transliteration'];
    final transliteration = transliterationRaw is Map<String, dynamic>
        ? transliterationRaw['text']?.toString()
        : transliterationRaw?.toString();
    final grammar = match['grammar'];
    return OnlineWordGloss(
      gloss: gloss,
      transliteration: transliteration,
      root: match['root']?.toString(),
      lemma: match['lemma']?.toString(),
      grammar: grammar is Map<String, dynamic> ? grammar.entries.map((e) => '${e.key}: ${e.value}').join('\n') : grammar?.toString(),
    );
  } catch (_) {
    return null;
  }
}

class AlQari extends StatefulWidget {
  const AlQari({super.key});

  @override
  State<AlQari> createState() => _AlQariState();
}

class _AlQariState extends State<AlQari> {
  late Future<QuranRepository> _repository = QuranRepository.load();
  ThemeMode _themeMode = ThemeMode.system;
  int _accentIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreAppearance();
  }

  Future<void> _restoreAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedMode = prefs.getString('themeMode') ?? 'system';
    final savedAccent = (prefs.getInt('accentIndex') ?? 0).clamp(0, appAccentColors.length - 1).toInt();
    setState(() {
      _themeMode = savedMode == 'dark'
          ? ThemeMode.dark
          : savedMode == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
      _accentIndex = savedAccent;
    });
  }

  String get _themeModeKey => _themeMode == ThemeMode.dark
      ? 'dark'
      : _themeMode == ThemeMode.light
          ? 'light'
          : 'system';

  Future<void> _setThemeMode(String value) async {
    setState(() {
      _themeMode = value == 'dark'
          ? ThemeMode.dark
          : value == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', value);
  }

  Future<void> _setAccentIndex(int value) async {
    final index = value.clamp(0, appAccentColors.length - 1).toInt();
    setState(() => _accentIndex = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentIndex', index);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seed = appAccentColors[_accentIndex];
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
      secondary: gold,
      surface: isDark ? const Color(0xFF171E1A) : Colors.white,
      onSurface: isDark ? const Color(0xFFE8EFEA) : const Color(0xFF212923),
      onSurfaceVariant: isDark ? const Color(0xFFB7C5BC) : const Color(0xFF59665D),
    );
    final outline = isDark ? const Color(0xFF3B4941) : const Color(0xFFE5E1D7);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xFF101613) : paper,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF171E1A) : scheme.primary,
        foregroundColor: isDark ? scheme.onSurface : scheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 70,
        centerTitle: false,
        titleTextStyle: TextStyle(color: isDark ? scheme.onSurface : scheme.onPrimary, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF171E1A) : Colors.white,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF171E1A) : const Color(0xFFFDFCF9),
        indicatorColor: scheme.primary.withAlpha(34),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26)))),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      dividerTheme: DividerThemeData(color: outline),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF202823) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF252D29) : const Color(0xFFF2E8CF),
        selectedColor: scheme.primary.withAlpha(34),
        side: BorderSide(color: outline),
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AlQari',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _themeMode,
        home: FutureBuilder<QuranRepository>(
          future: _repository,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DataErrorScreen(
                error: snapshot.error.toString(),
                onRetry: () => setState(() => _repository = QuranRepository.load()),
              );
            }
            if (!snapshot.hasData) {
              return const _LoadingScreen();
            }
            return HomeShell(
              repository: snapshot.data!,
              themeMode: _themeModeKey,
              accentIndex: _accentIndex,
              onThemeMode: _setThemeMode,
              onAccentIndex: _setAccentIndex,
            );
          },
        ),
      );
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _assemblyController;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat(reverse: true);
    _assemblyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..forward();
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _fade = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: 0.12, end: 0.38).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _assemblyController.dispose();
    super.dispose();
  }

  Widget _logoFragment(Alignment alignment, double dx, double dy, double progress) {
    return Transform.translate(
      offset: Offset(dx * (1 - progress), dy * (1 - progress)),
      child: ClipRect(
        child: SizedBox(
          width: 50,
          height: 50,
          child: Align(
            alignment: alignment,
            widthFactor: 0.5,
            heightFactor: 0.5,
            child: SizedBox(
              width: 100,
              height: 100,
              child: Image.asset(
                appLogoAsset,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: forest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.menu_book_rounded, color: gold, size: 58),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _assemblingBrandMark() => AnimatedBuilder(
        animation: _assemblyController,
        builder: (context, child) {
          final double progress = Curves.easeOutBack.transform(_assemblyController.value).clamp(0.0, 1.0).toDouble();
          return SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(left: 0, top: 0, child: _logoFragment(Alignment.topLeft, -34, -34, progress)),
                Positioned(right: 0, top: 0, child: _logoFragment(Alignment.topRight, 34, -34, progress)),
                Positioned(left: 0, bottom: 0, child: _logoFragment(Alignment.bottomLeft, -34, 34, progress)),
                Positioned(right: 0, bottom: 0, child: _logoFragment(Alignment.bottomRight, 34, 34, progress)),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: forest,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B2922), forest, Color(0xFF205D49)],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _fade.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: gold.withAlpha((_glow.value * 255).round()),
                              blurRadius: 38,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: _assemblingBrandMark(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'AlQari',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'READ  •  UNDERSTAND  •  REFLECT',
                    style: TextStyle(
                      color: Color(0xFFE5D3A4),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    uiText('en', 'loading'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: gold,
                        backgroundColor: Color(0x55FFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DataErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _DataErrorScreen({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AlQari')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_off_rounded, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(uiText('en', 'loadError'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('Release APKs must be built with the GitHub Actions workflow so that the full Quran and morphology assets are generated and validated first.', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            SelectableText(error, style: TextStyle(fontSize: 11, color: _mutedColor(context))),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: Text(uiText('en', 'tryAgain'))),
          ]),
        ),
      );
}

class HomeShell extends StatefulWidget {
  final QuranRepository repository;
  final String themeMode;
  final int accentIndex;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<int> onAccentIndex;

  const HomeShell({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.accentIndex,
    required this.onThemeMode,
    required this.onAccentIndex,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _selectedBottomIndex = 0;
  String _language = 'en';
  String _translationLanguage = 'ur';
  double _arabicScale = 32;
  String _readerMode = 'juz';
  int _readerSelectedJuz = 20;
  int _readerSelectedSurah = 27;
  int _lastReadJuz = 20;
  int _lastReadSurah = 27;
  double _readerScrollOffset = 0;
  String? _lastReadKey;
  bool _lastReadFromReader = true;
  final Set<String> _bookmarks = <String>{};

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('geminiApiKey');
    if (!mounted) return;
    setState(() {
      final lang = prefs.getString('language') ?? 'en';
      _language = const ['en', 'ur', 'sd'].contains(lang) ? lang : 'en';
      _arabicScale = (prefs.getDouble('arabicScale') ?? 32).clamp(26, 50).toDouble();
      _readerMode = prefs.getString('readerMode') == 'surah' ? 'surah' : 'juz';
      _readerSelectedJuz = (prefs.getInt('readerJuz') ?? 20).clamp(1, 30).toInt();
      _readerSelectedSurah = (prefs.getInt('readerSurah') ?? 27).clamp(1, 114).toInt();
      _lastReadJuz = (prefs.getInt('lastReadJuz') ?? _readerSelectedJuz).clamp(1, 30).toInt();
      _lastReadSurah = (prefs.getInt('lastReadSurah') ?? _readerSelectedSurah).clamp(1, 114).toInt();
      _readerScrollOffset = (prefs.getDouble('readerScrollOffset') ?? 0).clamp(0, double.infinity).toDouble();
      _lastReadKey = prefs.getString('lastReadKey');
      _lastReadFromReader = prefs.getBool('lastReadFromReader') ?? true;
      _bookmarks
        ..clear()
        ..addAll(prefs.getStringList('bookmarks') ?? const []);
    });
  }

  Future<void> _setLanguage(String value) async {
    setState(() => _language = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
  }

  Future<void> _setArabicScale(double value) async {
    setState(() => _arabicScale = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('arabicScale', value);
  }

  Future<void> _setReaderLocation(String mode, int surah, int juz) async {
    final selectedSurah = surah.clamp(1, 114).toInt();
    final selectedJuz = juz.clamp(1, 30).toInt();
    final lastReadSectionStillSelected = mode == 'surah'
        ? selectedSurah == _lastReadSurah
        : selectedJuz == _lastReadJuz;
    setState(() {
      _readerMode = mode;
      _readerSelectedSurah = selectedSurah;
      _readerSelectedJuz = selectedJuz;
      if (_lastReadKey != null && !lastReadSectionStillSelected) {
        _lastReadFromReader = false;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('readerMode', mode);
    await prefs.setInt('readerSurah', _readerSelectedSurah);
    await prefs.setInt('readerJuz', _readerSelectedJuz);
    await prefs.setBool('lastReadFromReader', _lastReadFromReader);
  }

  Future<void> _setReaderScrollOffset(double value) async {
    _readerScrollOffset = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('readerScrollOffset', _readerScrollOffset);
  }

  Future<void> _markRead(Ayah ayah, {bool fromReader = false}) async {
    setState(() {
      _lastReadKey = ayah.key;
      _lastReadSurah = ayah.surahNumber;
      _lastReadJuz = ayah.juz;
      _lastReadFromReader = fromReader;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastReadKey', ayah.key);
    await prefs.setInt('lastReadSurah', ayah.surahNumber);
    await prefs.setInt('lastReadJuz', ayah.juz);
    await prefs.setBool('lastReadFromReader', fromReader);
  }

  Future<void> _toggleBookmark(Ayah ayah) async {
    setState(() {
      if (!_bookmarks.add(ayah.key)) _bookmarks.remove(ayah.key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bookmarks', _bookmarks.toList()..sort());
  }

  int _bottomIndexForTab(int tab) {
    if (tab == 0) return 0; // Home
    if (tab == 1) return 1; // Quran
    if (tab == 2) return 2; // Recitation
    if (tab == 4) return 3; // Bookmarks
    return 4; // More holds Search and Settings too
  }

  void _selectTab(int tab, {bool closeDrawer = true}) {
    if (closeDrawer) Navigator.of(context).maybePop();
    setState(() {
      _tab = tab;
      _selectedBottomIndex = _bottomIndexForTab(tab);
    });
  }

  void _continueReading() {
    final key = _lastReadKey;
    if (key != null && key.contains(':') && !_lastReadFromReader) {
      _setReaderLocation('surah', _lastReadSurah, _lastReadJuz);
      _setReaderScrollOffset(0);
    }
    _selectTab(1);
  }

  void _openRecitation() {
    _selectTab(2, closeDrawer: false);
  }

  void _openPrayerTimes() => _selectTab(7, closeDrawer: false);

  void _openRecitationFromDrawer() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectTab(2, closeDrawer: false);
    });
  }

  void _showAbout() async {
    await Navigator.of(context).maybePop();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'AlQari',
      applicationVersion: '1.8.0',
      applicationIcon: alQariBrandMark(size: 58, radius: 14),
      children: const [
        Text('Read the Holy Quran in Arabic with Urdu translation and listen to verse-by-verse recitation.'),
      ],
    );
  }

  Widget _drawerItem({required IconData icon, required String title, String? subtitle, required VoidCallback onTap, bool selected = false}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      selected: selected,
      selectedColor: scheme.primary,
      selectedTileColor: scheme.primary.withAlpha(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = _language;
    final scheme = Theme.of(context).colorScheme;
    final appBarForeground = Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    final pageTitle = switch (_tab) {
      0 => 'AlQari',
      1 => uiText(lang, 'reader'),
      2 => uiText(lang, 'recitation'),
      3 => uiText(lang, 'searchQuran'),
      4 => uiText(lang, 'bookmarks'),
      5 => uiText(lang, 'more'),
      7 => uiText(lang, 'prayerTimes'),
      _ => uiText(lang, 'settings'),
    };

    return Directionality(
      textDirection: isRtl(lang) ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: _tab == 0
              ? Row(children: [
                  alQariBrandMark(size: 38, radius: 11),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('AlQari', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.35)),
                    Text(uiText(lang, 'tagline'), style: TextStyle(fontSize: 10, color: appBarForeground.withAlpha(190), fontWeight: FontWeight.w400)),
                  ])),
                ])
              : Text(pageTitle, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _language,
                  dropdownColor: scheme.surface,
                  iconEnabledColor: appBarForeground,
                  style: TextStyle(color: appBarForeground, fontWeight: FontWeight.w700),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('EN')),
                    DropdownMenuItem(value: 'ur', child: Text('اردو')),
                    DropdownMenuItem(value: 'sd', child: Text('سنڌي')),
                  ],
                  onChanged: (value) { if (value != null) _setLanguage(value); },
                ),
              ),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D3B30), Color(0xFF195746), Color(0xFF236B55)]),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    alQariBrandMark(size: 58, radius: 17),
                    const SizedBox(width: 13),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('AlQari', style: TextStyle(color: Color(0xFFFFF8E7), fontWeight: FontWeight.w800, fontSize: 25, letterSpacing: -0.5)),
                      SizedBox(height: 4),
                      Text('Read • Understand • Reflect', style: TextStyle(color: Color(0xFFE2D4A9), fontSize: 11)),
                    ])),
                  ]),
                  const SizedBox(height: 18),
                  Text(uiText(lang, 'browseFeatures'), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 16), children: [
                  Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Text(lang == 'ur' ? 'قرآن' : lang == 'sd' ? 'قرآن' : 'QURAN', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
                  _drawerItem(icon: Icons.home_rounded, title: uiText(lang, 'homeTab'), selected: _tab == 0, onTap: () => _selectTab(0)),
                  _drawerItem(icon: Icons.menu_book_rounded, title: uiText(lang, 'quranTab'), selected: _tab == 1, onTap: () => _selectTab(1)),
                  _drawerItem(icon: Icons.play_lesson_outlined, title: uiText(lang, 'continueReading'), subtitle: _lastReadKey == null ? '${uiText(lang, 'surah')} $_lastReadSurah' : '${uiText(lang, 'verse')} $_lastReadKey', onTap: _continueReading),
                  _drawerItem(icon: Icons.headphones_rounded, title: uiText(lang, 'recitation'), onTap: _openRecitationFromDrawer),
                  _drawerItem(icon: Icons.access_time_rounded, title: uiText(lang, 'prayerTimes'), onTap: _openPrayerTimes),
                  _drawerItem(icon: Icons.search_rounded, title: uiText(lang, 'searchQuran'), selected: _tab == 3, onTap: () => _selectTab(3)),
                  _drawerItem(icon: Icons.bookmark_rounded, title: uiText(lang, 'bookmarks'), selected: _tab == 4, onTap: () => _selectTab(4)),
                  const SizedBox(height: 8),
                  Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: Text(lang == 'ur' ? 'ذاتی ترجیحات' : lang == 'sd' ? 'ذاتي ترجيحون' : 'PERSONALIZE', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
                  _drawerItem(icon: Icons.tune_rounded, title: uiText(lang, 'settingsAppearance'), selected: _tab == 6, onTap: () => _selectTab(6)),
                  _drawerItem(icon: Icons.more_horiz_rounded, title: uiText(lang, 'more'), selected: _tab == 5, onTap: () => _selectTab(5)),
                  _drawerItem(icon: Icons.info_outline_rounded, title: uiText(lang, 'about'), onTap: _showAbout),
                ]),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Text('AlQari · Version 1.8.0', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11))),
            ]),
          ),
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            HomeDashboard(
              repository: widget.repository,
              language: lang,
              translationLanguage: _translationLanguage,
              lastReadKey: _lastReadKey,
              lastReadSurah: _lastReadSurah,
              bookmarkCount: _bookmarks.length,
              onContinueReading: _continueReading,
              onReadQuran: () => _selectTab(1, closeDrawer: false),
              onRecitation: _openRecitation,
              onSearch: () => _selectTab(3, closeDrawer: false),
              onBookmarks: () => _selectTab(4, closeDrawer: false),
              onSettings: () => _selectTab(6, closeDrawer: false),
              onWordAnalysis: () => _selectTab(1, closeDrawer: false),
            ),
            ReaderPage(
              repository: widget.repository,
              language: lang,
              translationLanguage: _translationLanguage,
              bookmarks: _bookmarks,
              arabicScale: _arabicScale,
              onBookmark: _toggleBookmark,
              onReadAyah: (ayah) => _markRead(ayah, fromReader: true),
              onOpenRecitation: _openRecitation,
              initialMode: _readerMode,
              initialJuz: _readerSelectedJuz,
              initialSurah: _readerSelectedSurah,
              onLocationChanged: _setReaderLocation,
              lastReadKey: _lastReadKey,
              initialScrollOffset: _readerScrollOffset,
              onScrollOffsetChanged: _setReaderScrollOffset,
            ),
            RecitationPage(
              repository: widget.repository,
              language: lang,
              translationLanguage: _translationLanguage,
              onTranslationLanguage: _setTranslationLanguage,
              arabicScale: _arabicScale,
              initialSurah: _readerMode == 'surah' ? _readerSelectedSurah : _lastReadSurah,
              active: _tab == 2,
            ),
            SearchPage(repository: widget.repository, language: lang, translationLanguage: _translationLanguage, bookmarks: _bookmarks, arabicScale: _arabicScale, onBookmark: _toggleBookmark, onReadAyah: (ayah) => _markRead(ayah)),
            BookmarksPage(repository: widget.repository, language: lang, translationLanguage: _translationLanguage, bookmarks: _bookmarks, arabicScale: _arabicScale, onBookmark: _toggleBookmark, onReadAyah: (ayah) => _markRead(ayah)),
            MorePage(
              language: lang,
              bookmarkCount: _bookmarks.length,
              onSearch: () => _selectTab(3, closeDrawer: false),
              onSettings: () => _selectTab(6, closeDrawer: false),
              onRecitation: _openRecitation,
              onContinueReading: _continueReading,
              onAbout: _showAbout,
              onReadQuran: () => _selectTab(1, closeDrawer: false),
              onPrayerTimes: _openPrayerTimes,
            ),
            SettingsPage(
              language: lang,
              arabicScale: _arabicScale,
              manifest: widget.repository.dataManifest,
              onLanguage: _setLanguage,
              onArabicScale: _setArabicScale,
              themeMode: widget.themeMode,
              accentIndex: widget.accentIndex,
              onThemeMode: widget.onThemeMode,
              onAccentIndex: widget.onAccentIndex,
            ),
            PrayerTimesPage(language: lang),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedBottomIndex,
          onDestinationSelected: (value) {
            final destination = switch (value) {
              0 => 0,
              1 => 1,
              2 => 2,
              3 => 4,
              _ => 5,
            };
            _selectTab(destination, closeDrawer: false);
          },
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: uiText(lang, 'homeTab')),
            NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book_rounded), label: uiText(lang, 'quranTab')),
            NavigationDestination(icon: const Icon(Icons.headphones_outlined), selectedIcon: const Icon(Icons.headphones_rounded), label: uiText(lang, 'recitation')),
            NavigationDestination(icon: const Icon(Icons.bookmark_border_rounded), selectedIcon: const Icon(Icons.bookmark_rounded), label: uiText(lang, 'bookmarks')),
            NavigationDestination(icon: const Icon(Icons.grid_view_rounded), selectedIcon: const Icon(Icons.grid_view_rounded), label: uiText(lang, 'more')),
          ],
        ),
      ),
    );
  }

}


class HomeDashboard extends StatelessWidget {
  final QuranRepository repository;
  final String language;
  final String translationLanguage;
  final String? lastReadKey;
  final int lastReadSurah;
  final int bookmarkCount;
  final VoidCallback onContinueReading;
  final VoidCallback onReadQuran;
  final VoidCallback onRecitation;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;
  final VoidCallback onWordAnalysis;

  const HomeDashboard({
    super.key,
    required this.repository,
    required this.language,
    required this.translationLanguage,
    required this.lastReadKey,
    required this.lastReadSurah,
    required this.bookmarkCount,
    required this.onContinueReading,
    required this.onReadQuran,
    required this.onRecitation,
    required this.onSearch,
    required this.onBookmarks,
    required this.onSettings,
    required this.onWordAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final dayIndex = now.difference(DateTime(now.year, 1, 1)).inDays;
    final dailyAyah = repository.allAyahs[dayIndex % repository.allAyahs.length];
    Ayah? lastAyah;
    if (lastReadKey != null) {
      for (final ayah in repository.allAyahs) {
        if (ayah.key == lastReadKey) {
          lastAyah = ayah;
          break;
        }
      }
    }
    final continueSurah = repository.surah(lastAyah?.surahNumber ?? lastReadSurah);
    final targetTitle = lastAyah == null
        ? (continueSurah?.nameEnglish ?? 'Al-Fatihah')
        : '${continueSurah?.nameEnglish ?? ''} · ${uiText(language, 'verse')} ${lastAyah.number}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D3B30), Color(0xFF155542), Color(0xFF236B55)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: const Color(0xFF0D3B30).withAlpha(isDark ? 70 : 34), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              alQariBrandMark(size: 54, radius: 17),
              const SizedBox(width: 13),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AlQari', style: TextStyle(color: Color(0xFFFFF7E4), fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                SizedBox(height: 4),
                Text('READ  •  UNDERSTAND  •  REFLECT', style: TextStyle(color: Color(0xFFE5D3A4), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.05)),
              ])),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(35))),
                child: const Icon(Icons.auto_awesome_rounded, color: gold, size: 22),
              ),
            ]),
            const SizedBox(height: 22),
            Text(language == 'ur' ? 'السلام علیکم' : language == 'sd' ? 'السلام عليڪم' : 'Assalamu Alaikum', style: const TextStyle(color: Color(0xFFE7D8B4), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(uiText(language, 'homeHeadline'), style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -0.35)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _homeHeroStat('114', uiText(language, 'surahs'))),
              Container(width: 1, height: 34, color: Colors.white.withAlpha(35)),
              Expanded(child: _homeHeroStat('6,236', uiText(language, 'ayat'))),
              Container(width: 1, height: 34, color: Colors.white.withAlpha(35)),
              Expanded(child: _homeHeroStat('3', uiText(language, 'languagesCount'))),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        _homeSectionHeading(context, uiText(language, 'continueReading'), subtitle: lastAyah == null ? uiText(language, 'noProgress') : uiText(language, 'browseFeatures')),
        const SizedBox(height: 10),
        Card(
          color: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23), side: BorderSide(color: _borderColor(context))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: scheme.primary.withAlpha(17), borderRadius: BorderRadius.circular(17)),
                  child: Icon(Icons.menu_book_rounded, color: scheme.primary, size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(targetTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text(lastAyah == null ? (continueSurah?.nameArabic ?? '') : '${uiText(language, 'juz')} ${lastAyah.juz}  ·  ${uiText(language, 'surah')} ${lastAyah.surahNumber}', style: TextStyle(color: _mutedColor(context), fontSize: 12)),
                ])),
                Icon(Icons.arrow_outward_rounded, color: scheme.primary, size: 20),
              ]),
              const SizedBox(height: 13),
              if (lastAyah != null) ...[
                Directionality(textDirection: TextDirection.rtl, child: Text(lastAyah.arabic, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: quranTextStyle(context, fontSize: 25, height: 1.9, color: scheme.onSurface))),
                const SizedBox(height: 6),
              ],
              FilledButton.icon(
                onPressed: lastAyah == null ? onReadQuran : onContinueReading,
                icon: Icon(lastAyah == null ? Icons.menu_book_rounded : Icons.play_arrow_rounded),
                label: Text(lastAyah == null ? uiText(language, 'startReading') : uiText(language, 'continueReading')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        _homeSectionHeading(context, uiText(language, 'quickAccess')),
        const SizedBox(height: 11),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          childAspectRatio: MediaQuery.sizeOf(context).width < 360 ? 1.08 : MediaQuery.sizeOf(context).width > 620 ? 1.75 : 1.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _homeActionCard(context, icon: Icons.menu_book_rounded, title: uiText(language, 'quranTab'), subtitle: uiText(language, 'readSubtitle'), accent: const Color(0xFF287A58), onTap: onReadQuran),
            _homeActionCard(context, icon: Icons.headphones_rounded, title: uiText(language, 'recitation'), subtitle: uiText(language, 'chooseReciter'), accent: const Color(0xFFB88728), onTap: onRecitation),
            _homeActionCard(context, icon: Icons.search_rounded, title: uiText(language, 'searchQuran'), subtitle: uiText(language, 'searchHint'), accent: const Color(0xFF3476A5), onTap: onSearch),
            _homeActionCard(context, icon: Icons.bookmark_rounded, title: uiText(language, 'bookmarks'), subtitle: '$bookmarkCount ${uiText(language, 'savedAyat')}', accent: const Color(0xFF7C5BB6), onTap: onBookmarks),
            _homeActionCard(context, icon: Icons.translate_rounded, title: uiText(language, 'translationTools'), subtitle: 'English · اردو · سنڌي', accent: const Color(0xFF1D817B), onTap: onSettings),
            _homeActionCard(context, icon: Icons.auto_stories_rounded, title: uiText(language, 'wordAnalysis'), subtitle: uiText(language, 'wordTapHint'), accent: const Color(0xFF9A6B37), onTap: onWordAnalysis),
          ],
        ),
        const SizedBox(height: 22),
        _homeSectionHeading(context, uiText(language, 'dailyReflection')),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2922) : const Color(0xFFFFFBF1),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: isDark ? const Color(0xFF3A5547) : const Color(0xFFE7D8B4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFB88728), size: 19),
              const SizedBox(width: 8),
              Expanded(child: Text('${repository.surah(dailyAyah.surahNumber)?.nameEnglish ?? ''} · ${dailyAyah.key}', style: TextStyle(color: _mutedColor(context), fontSize: 12, fontWeight: FontWeight.w700))),
              const Icon(Icons.format_quote_rounded, color: Color(0xFFB88728)),
            ]),
            const SizedBox(height: 12),
            Directionality(textDirection: TextDirection.rtl, child: Text(dailyAyah.arabic, textAlign: TextAlign.center, style: quranTextStyle(context, fontSize: 29, height: 2.0, color: scheme.onSurface))),
            const SizedBox(height: 10),
            Text(dailyAyah.translationFor(translationLanguage), textDirection: isRtl(translationLanguage) ? TextDirection.rtl : TextDirection.ltr, textAlign: TextAlign.start, style: TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.65)),
            const SizedBox(height: 13),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: onReadQuran, icon: const Icon(Icons.menu_book_rounded, size: 18), label: Text(uiText(language, 'readSubtitle')))),
          ]),
        ),
        const SizedBox(height: 14),
        Center(child: Text('AlQari · ${uiText(language, 'tagline')}', textAlign: TextAlign.center, style: TextStyle(color: _mutedColor(context), fontSize: 11, letterSpacing: 0.2))),
      ],
    );
  }
}

Widget _homeHeroStat(String value, String label) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(color: Color(0xFFFFE7A5), fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
    const SizedBox(height: 3),
    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
  ]),
);

Widget _homeSectionHeading(BuildContext context, String title, {String? subtitle}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.25)),
    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(color: _mutedColor(context), height: 1.4, fontSize: 12)),
    ],
  ],
);

Widget _homeActionCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required Color accent, required VoidCallback onTap}) {
  final scheme = Theme.of(context).colorScheme;
  return Card(
    color: scheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _borderColor(context))),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.withAlpha(20), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: accent, size: 22)),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface, fontSize: 13)),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.25, color: _mutedColor(context))),
        ]),
      ),
    ),
  );
}

class MorePage extends StatelessWidget {
  final String language;
  final int bookmarkCount;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onRecitation;
  final VoidCallback onContinueReading;
  final VoidCallback onAbout;
  final VoidCallback onReadQuran;
  final VoidCallback onPrayerTimes;

  const MorePage({super.key, required this.language, required this.bookmarkCount, required this.onSearch, required this.onSettings, required this.onRecitation, required this.onContinueReading, required this.onAbout, required this.onReadQuran, required this.onPrayerTimes});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <({IconData icon, String title, String subtitle, VoidCallback action})>[
      (icon: Icons.search_rounded, title: uiText(language, 'searchQuran'), subtitle: uiText(language, 'searchHint'), action: onSearch),
      (icon: Icons.headphones_rounded, title: uiText(language, 'recitation'), subtitle: uiText(language, 'chooseReciter'), action: onRecitation),
      (icon: Icons.menu_book_rounded, title: uiText(language, 'continueReading'), subtitle: uiText(language, 'readSubtitle'), action: onContinueReading),
      (icon: Icons.translate_rounded, title: uiText(language, 'translationTools'), subtitle: 'اردو', action: onSettings),
      (icon: Icons.access_time_rounded, title: uiText(language, 'prayerTimes'), subtitle: uiText(language, 'prayerSubtitle'), action: onPrayerTimes),
      (icon: Icons.tune_rounded, title: uiText(language, 'settingsAppearance'), subtitle: uiText(language, 'appearance'), action: onSettings),
      (icon: Icons.info_outline_rounded, title: uiText(language, 'about'), subtitle: 'AlQari · Version 1.8.0', action: onAbout),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D3B30), Color(0xFF236B55)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(children: [
          alQariBrandMark(size: 55, radius: 16),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AlQari', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 23)),
            const SizedBox(height: 4),
            Text(uiText(language, 'browseFeatures'), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35)),
          ])),
        ]),
      ),
      const SizedBox(height: 18),
      _homeSectionHeading(context, uiText(language, 'more')),
      const SizedBox(height: 10),
      Card(
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: _borderColor(context))),
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primary.withAlpha(18), borderRadius: BorderRadius.circular(13)), child: Icon(items[i].icon, color: scheme.primary)),
              title: Text(items[i].title, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
              subtitle: Text(items[i].subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _mutedColor(context), fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: _mutedColor(context)),
              onTap: items[i].action,
            ),
            if (i != items.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ]),
      ),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _softSurfaceColor(context), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(Icons.bookmark_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('$bookmarkCount ${uiText(language, 'savedAyat')}', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700))),
          TextButton(onPressed: onReadQuran, child: Text(uiText(language, 'quranTab'))),
        ]),
      ),
    ]);
  }
}

class ReaderPage extends StatefulWidget {
  final QuranRepository repository;
  final String language;
  final String translationLanguage;
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  final Future<void> Function(Ayah) onReadAyah;
  final VoidCallback onOpenRecitation;
  final String initialMode;
  final int initialJuz;
  final int initialSurah;
  final String? lastReadKey;
  final double initialScrollOffset;
  final ValueChanged<double> onScrollOffsetChanged;
  final Future<void> Function(String, int, int) onLocationChanged;

  const ReaderPage({
    super.key,
    required this.repository,
    required this.language,
    required this.translationLanguage,
    required this.bookmarks,
    required this.arabicScale,
    required this.onBookmark,
    required this.onReadAyah,
    required this.onOpenRecitation,
    required this.initialMode,
    required this.initialJuz,
    required this.initialSurah,
    required this.lastReadKey,
    required this.initialScrollOffset,
    required this.onScrollOffsetChanged,
    required this.onLocationChanged,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

double maxOffsetForAyahs(ScrollController controller, int ayahCount) {
  if (!controller.hasClients || ayahCount <= 1) return 300;
  final maxOffset = controller.position.maxScrollExtent;
  if (!maxOffset.isFinite || maxOffset <= 0) return 300;
  return (maxOffset / (ayahCount - 1)).clamp(180.0, 720.0).toDouble();
}

class _ReaderPageState extends State<ReaderPage> {
  String? _activeAyahKey;
  final Map<String, GlobalKey> _ayahItemKeys = <String, GlobalKey>{};
  late String _mode;
  late int _selectedJuz;
  late int _selectedSurah;
  late final ScrollController _scrollController;
  bool _showSelectionControls = true;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _selectedJuz = widget.initialJuz;
    _selectedSurah = widget.initialSurah;
    _scrollController = ScrollController(initialScrollOffset: widget.initialScrollOffset);
    _activeAyahKey = activeRecitationAyahKey.value;
    activeRecitationAyahKey.addListener(_onActiveRecitationAyahChanged);
  }

  void _onActiveRecitationAyahChanged() {
    final key = activeRecitationAyahKey.value;
    if (!mounted) return;
    if (key == null) {
      if (_activeAyahKey != null) setState(() => _activeAyahKey = null);
      return;
    }

    final index = _visibleAyahs.indexWhere((ayah) => ayah.key == key);
    if (index < 0) {
      final parts = key.split(':');
      final surahNumber = parts.length == 2 ? int.tryParse(parts[0]) : null;
      if (surahNumber == null || surahNumber < 1 || surahNumber > 114) return;
      if (_activeAyahKey == key && _mode == 'surah' && _selectedSurah == surahNumber) return;
      _ayahItemKeys.clear();
      setState(() {
        _activeAyahKey = key;
        _mode = 'surah';
        _selectedSurah = surahNumber;
      });
      widget.onScrollOffsetChanged(0);
      widget.onLocationChanged('surah', surahNumber, _selectedJuz);
    } else {
      if (key == _activeAyahKey) return;
      setState(() => _activeAyahKey = key);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAyah(key);
    });
  }

  Future<void> _scrollToAyah(String key) async {
    if (!mounted || !_scrollController.hasClients) return;
    final ayahs = _visibleAyahs;
    final targetIndex = ayahs.indexWhere((ayah) => ayah.key == key);
    if (targetIndex < 0) return;

    // Sliver children are lazily mounted. First jump near the target based on
    // the list's estimated extent, then refine using the nearest mounted row.
    if (_ayahItemKeys[key]?.currentContext == null) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final denominator = (ayahs.length - 1).clamp(1, 1 << 30);
      final fraction = targetIndex / denominator;
      _scrollController.jumpTo((maxOffset * fraction).clamp(0.0, maxOffset).toDouble());
      await WidgetsBinding.instance.endOfFrame;
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      final targetContext = _ayahItemKeys[key]?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 420),
          alignment: 0.12,
          curve: Curves.easeInOutCubic,
        );
        return;
      }

      var firstMountedIndex = -1;
      var lastMountedIndex = -1;
      for (var i = 0; i < ayahs.length; i++) {
        if (_ayahItemKeys[ayahs[i].key]?.currentContext != null) {
          if (firstMountedIndex < 0) firstMountedIndex = i;
          lastMountedIndex = i;
        }
      }

      if (firstMountedIndex < 0) {
        _scrollController.jumpTo(0);
      } else {
        final visibleAnchor = targetIndex < firstMountedIndex
            ? firstMountedIndex
            : lastMountedIndex;
        final averageRowExtent = maxOffsetForAyahs(_scrollController, ayahs.length);
        final delta = (targetIndex - visibleAnchor) * averageRowExtent;
        final nextOffset = (_scrollController.offset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ).toDouble();
        _scrollController.jumpTo(nextOffset);
      }
      await WidgetsBinding.instance.endOfFrame;
    }

    // One last pass for the now-mounted item after the bounded refinement.
    final targetContext = _ayahItemKeys[key]?.currentContext;
    if (mounted && targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        alignment: 0.12,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    activeRecitationAyahKey.removeListener(_onActiveRecitationAyahChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final locationChanged = oldWidget.initialMode != widget.initialMode ||
        oldWidget.initialJuz != widget.initialJuz ||
        oldWidget.initialSurah != widget.initialSurah;
    final offsetChanged = oldWidget.initialScrollOffset != widget.initialScrollOffset;
    if (locationChanged) {
      _mode = widget.initialMode;
      _selectedJuz = widget.initialJuz;
      _selectedSurah = widget.initialSurah;
    }
    if (locationChanged || offsetChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxOffset = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(widget.initialScrollOffset.clamp(0, maxOffset).toDouble());
      });
    }
  }

  void _changeLocation({String? mode, int? surah, int? juz, bool collapseControls = true}) {
    _ayahItemKeys.clear();
    setState(() {
      if (collapseControls) _showSelectionControls = false;
      if (mode != null) _mode = mode;
      if (surah != null) _selectedSurah = surah;
      if (juz != null) _selectedJuz = juz;
    });
    widget.onScrollOffsetChanged(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
    widget.onLocationChanged(_mode, _selectedSurah, _selectedJuz);
  }

  List<Ayah> get _visibleAyahs {
    if (_mode == 'surah') return widget.repository.surah(_selectedSurah)?.ayahs ?? const [];
    return widget.repository.allAyahs.where((a) => a.juz == _selectedJuz).toList(growable: false);
  }

  Widget _buildVerseCard(Ayah ayah, String lang, {ActiveRecitationWord? activeWordRange}) => VerseCard(
        key: ValueKey(ayah.key),
        repository: widget.repository,
        ayah: ayah,
        language: lang,
        translationLanguage: widget.translationLanguage,
        arabicScale: widget.arabicScale,
        isBookmarked: widget.bookmarks.contains(ayah.key),
        onBookmark: () => widget.onBookmark(ayah),
        onReadAyah: () => widget.onReadAyah(ayah),
        isLastRead: widget.lastReadKey == ayah.key,
        activeWordRange: activeWordRange,
      );

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final scheme = Theme.of(context).colorScheme;
    final ayahs = _visibleAyahs;
    return Column(children: [
      if (_showSelectionControls) Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 5),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _borderColor(context)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: scheme.primary.withAlpha(22), borderRadius: BorderRadius.circular(15)),
              child: alQariBrandMark(size: 44, radius: 13),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(uiText(lang, 'reader'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.2)),
              const SizedBox(height: 3),
              Text(uiText(lang, 'readSubtitle'), style: TextStyle(fontSize: 12, color: _mutedColor(context), height: 1.35)),
            ])),
          ]),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _softSurfaceColor(context), borderRadius: BorderRadius.circular(15)),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'juz', label: Text(uiText(lang, 'juzMode')), icon: const Icon(Icons.bookmarks_outlined)),
                ButtonSegment(value: 'surah', label: Text(uiText(lang, 'surahMode')), icon: const Icon(Icons.menu_book_outlined)),
              ],
              selected: {_mode},
              onSelectionChanged: (selected) => _changeLocation(mode: selected.first, collapseControls: false),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 11),
          if (_mode == 'juz')
            DropdownButtonFormField<int>(
              initialValue: _selectedJuz,
              isExpanded: true,
              decoration: InputDecoration(labelText: uiText(lang, 'selectJuz'), border: const OutlineInputBorder(), isDense: true, prefixIcon: const Icon(Icons.bookmarks_outlined)),
              items: [for (var juz = 1; juz <= 30; juz++) DropdownMenuItem(value: juz, child: Text('${uiText(lang, 'juz')} $juz'))],
              onChanged: (value) { if (value != null) _changeLocation(juz: value); },
            )
          else
            DropdownButtonFormField<int>(
              initialValue: _selectedSurah,
              isExpanded: true,
              decoration: InputDecoration(labelText: uiText(lang, 'selectSurah'), border: const OutlineInputBorder(), isDense: true, prefixIcon: const Icon(Icons.menu_book_outlined)),
              items: widget.repository.surahs.map((s) => DropdownMenuItem(value: s.number, child: Text('${s.number}. ${s.nameEnglish} — ${s.nameArabic}'))).toList(),
              onChanged: (value) { if (value != null) _changeLocation(surah: value); },
            ),
          const SizedBox(height: 11),
          Row(children: [
            Icon(Icons.format_list_numbered_rounded, size: 16, color: _mutedColor(context)),
            const SizedBox(width: 6),
            Expanded(child: Text('${ayahs.length} ${uiText(lang, 'versesInSection')}', style: TextStyle(color: _mutedColor(context), fontSize: 12, fontWeight: FontWeight.w600))),
            if (widget.lastReadKey != null && ayahs.any((ayah) => ayah.key == widget.lastReadKey))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: scheme.primary.withAlpha(22), borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bookmark_added_outlined, color: scheme.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(uiText(lang, 'lastRead'), style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.onOpenRecitation,
            icon: const Icon(Icons.headphones_rounded),
            label: Text(uiText(lang, 'listenRecitation')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ]),
      )
      else Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor(context)),
        ),
        child: Row(children: [
          Expanded(child: Text(
            _mode == 'juz' ? '${uiText(lang, 'juz')} $_selectedJuz' : '${_selectedSurah}. ${widget.repository.surah(_selectedSurah)?.nameEnglish ?? ''}',
            style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
          )),
          TextButton.icon(
            onPressed: () => setState(() => _showSelectionControls = true),
            icon: const Icon(Icons.tune_rounded),
            label: Text(uiText(lang, 'change')),
          ),
        ]),
      ),
      Expanded(
        child: ayahs.isEmpty
            ? Center(child: Text(uiText(lang, 'noResults')))
            : NotificationListener<ScrollEndNotification>(
                onNotification: (notification) {
                  if (_scrollController.hasClients) {
                    widget.onScrollOffsetChanged(_scrollController.offset);
                  }
                  return false;
                },
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  children: [
                    for (final ayah in ayahs)
                      AnimatedContainer(
                        key: _ayahItemKeys.putIfAbsent(ayah.key, GlobalKey.new),
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: _activeAyahKey == ayah.key ? gold.withAlpha(34) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: _activeAyahKey == ayah.key ? Border.all(color: gold, width: 1.5) : null,
                        ),
                        padding: _activeAyahKey == ayah.key ? const EdgeInsets.all(3) : EdgeInsets.zero,
                        child: _activeAyahKey == ayah.key
                            ? ValueListenableBuilder<ActiveRecitationWord?>(
                                valueListenable: activeRecitationWord,
                                builder: (context, range, child) => _buildVerseCard(
                                  ayah,
                                  lang,
                                  activeWordRange: range,
                                ),
                              )
                            : _buildVerseCard(ayah, lang),
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }
}


class RecitationPage extends StatefulWidget {
  final QuranRepository repository;
  final String language;
  final String translationLanguage;
  final ValueChanged<String> onTranslationLanguage;
  final double arabicScale;
  final int initialSurah;
  final bool active;

  const RecitationPage({
    super.key,
    required this.repository,
    required this.language,
    required this.translationLanguage,
    required this.onTranslationLanguage,
    required this.arabicScale,
    required this.initialSurah,
    this.active = true,
  });

  @override
  State<RecitationPage> createState() => _RecitationPageState();
}

class _RecitationPageState extends State<RecitationPage> {
  late final AudioPlayer _player;
  late final FlutterTts _translationTts;
  late final StreamSubscription<PlayerException> _errorSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<int?> _indexSubscription;
  late final StreamSubscription<ProcessingState> _processingSubscription;
  late int _selectedSurah;
  String _selectedReciter = 'ar.alafasy';
  bool _loading = false;
  bool _initialized = false;
  bool _advancingSurah = false;
  bool _translationSpeaking = false;
  bool _manualNavigation = false;
  String? _error;
  int _loadGeneration = 0;
  int _currentPlaylistIndex = 0;
  Duration _currentPosition = Duration.zero;
  Map<String, List<RecitationTimingSegment>> _wordTimings = <String, List<RecitationTimingSegment>>{};

  QuranReciter get _reciter => supportedReciters.firstWhere((item) => item.id == _selectedReciter);
  Surah get _surah => widget.repository.surah(_selectedSurah)!;

  @override
  void initState() {
    super.initState();
    _selectedSurah = widget.initialSurah.clamp(1, 114).toInt();
    _player = AudioPlayer();
    _translationTts = FlutterTts();
    _translationTts.setCompletionHandler(() {
      if (!mounted || !_translationSpeaking) return;
      _translationSpeaking = false;
      unawaited(_playNextAyahAfterTranslation());
    });
    _translationTts.setErrorHandler((message) {
      if (!mounted) return;
      _translationSpeaking = false;
      setState(() => _error = 'Translation voice unavailable: $message');
      unawaited(_playNextAyahAfterTranslation());
    });
    _errorSubscription = _player.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? uiText(widget.language, 'audioError');
        _loading = false;
      });
    });
    _positionSubscription = _player.positionStream.listen((position) {
      _currentPosition = position;
      _syncCurrentRecitationPosition();
    });
    _indexSubscription = _player.currentIndexStream.listen((_) {
      // Each playlist intentionally contains only the current ayah. The
      // player's sequence index is therefore always 0 and must not replace
      // our Surah-relative ayah index, which advances after translation TTS.
      _currentPosition = Duration.zero;
      _syncCurrentRecitationPosition();
    });
    _processingSubscription = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) unawaited(_onAyahAudioCompleted());
    });
    unawaited(_loadWordTimings(_selectedReciter));
    if (widget.active) _loadSurahPlaylist();
  }

  @override
  void didUpdateWidget(covariant RecitationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSurah != widget.initialSurah && widget.active) {
      _selectedSurah = widget.initialSurah.clamp(1, 114).toInt();
      _initialized = false;
      _loadSurahPlaylist();
      return;
    }
    if (!oldWidget.active && widget.active && !_initialized) {
      _selectedSurah = widget.initialSurah.clamp(1, 114).toInt();
      _loadSurahPlaylist();
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription.cancel());
    unawaited(_positionSubscription.cancel());
    unawaited(_indexSubscription.cancel());
    unawaited(_processingSubscription.cancel());
    if (activeRecitationAyahKey.value != null) activeRecitationAyahKey.value = null;
    activeRecitationWord.value = null;
    unawaited(_translationTts.stop());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadWordTimings(String edition) async {
    try {
      final decoded = jsonDecode(await rootBundle.loadString('assets/data/word_timings.json'));
      if (decoded is! Map<String, dynamic>) return;
      final parsed = parseWordTimingData(decoded, edition);
      if (!mounted || edition != _selectedReciter) return;
      setState(() => _wordTimings = parsed);
      _syncCurrentRecitationPosition();
    } catch (_) {
      // The app remains usable with ayah-level highlight if timing data is absent.
      if (mounted && edition == _selectedReciter) setState(() => _wordTimings = <String, List<RecitationTimingSegment>>{});
      activeRecitationWord.value = null;
    }
  }

  void _syncCurrentRecitationPosition() {
    // The IndexedStack creates this page before the user starts recitation.
    // Do not publish a fake first-ayah state until a playlist is actually loaded.
    if (!mounted || !_initialized) return;
    final surah = widget.repository.surah(_selectedSurah);
    if (surah == null ||
        surah.ayahs.isEmpty ||
        _currentPlaylistIndex < 0 ||
        _currentPlaylistIndex >= surah.ayahs.length) {
      return;
    }
    final ayah = surah.ayahs[_currentPlaylistIndex];
    if (activeRecitationAyahKey.value != ayah.key) {
      activeRecitationAyahKey.value = ayah.key;
    }
    final milliseconds = _currentPosition.inMilliseconds;
    ActiveRecitationWord? nextWord;
    for (final segment in _wordTimings[ayah.key] ?? const <RecitationTimingSegment>[]) {
      if (milliseconds >= segment.startMs && milliseconds < segment.endMs) {
        nextWord = ActiveRecitationWord(
          ayahKey: ayah.key,
          wordStartIndex: segment.wordStartIndex,
          wordEndIndex: segment.wordEndIndex,
        );
        break;
      }
      if (segment.startMs > milliseconds) break;
    }
    if (!(activeRecitationWord.value?.sameAs(nextWord) ?? nextWord == null)) {
      activeRecitationWord.value = nextWord;
    }
  }

  Future<void> _onAyahAudioCompleted() async {
    if (!mounted || !_initialized || _loading || _translationSpeaking || _manualNavigation) return;
    final surah = widget.repository.surah(_selectedSurah);
    if (surah == null || _currentPlaylistIndex < 0 || _currentPlaylistIndex >= surah.ayahs.length) return;
    final ayah = surah.ayahs[_currentPlaylistIndex];
    final translation = ayah.translationFor(widget.translationLanguage).trim();
    if (translation.isEmpty) { await _playNextAyahAfterTranslation(); return; }
    _translationSpeaking = true;
    try {
      await _translationTts.stop();
      final ttsLanguage = switch (widget.translationLanguage) { 'ur' => 'ur-PK', 'sd' => 'sd-PK', _ => 'en-US' };
      await _translationTts.setLanguage(ttsLanguage);
      await _translationTts.setSpeechRate(0.46);
      await _translationTts.setPitch(1.0);
      await _translationTts.speak(translation);
    } catch (_) {
      _translationSpeaking = false;
      await _playNextAyahAfterTranslation();
    }
  }

  Future<void> _playNextAyahAfterTranslation() async {
    if (!mounted || !_initialized || _loading) return;
    final surah = widget.repository.surah(_selectedSurah);
    if (surah == null) return;
    if (_currentPlaylistIndex + 1 < surah.ayahs.length) {
      await _loadSurahPlaylist(startIndex: _currentPlaylistIndex + 1, autoplay: true);
    } else { await _advanceToNextSurah(); }
  }

  Future<void> _advanceToNextSurah() async {
    if (!mounted || !_initialized || _loading || _advancingSurah) return;
    if (_selectedSurah >= 114) { activeRecitationWord.value = null; return; }
    _advancingSurah = true;
    try {
      if (!mounted) return;
      setState(() => _selectedSurah += 1);
      _currentPlaylistIndex = 0;
      _currentPosition = Duration.zero;
      activeRecitationWord.value = null;
      await _loadSurahPlaylist(autoplay: true);
    } finally { _advancingSurah = false; }
  }

  Future<void> _loadSurahPlaylist({int startIndex = 0, bool autoplay = false}) async {
    final generation = ++_loadGeneration;
    final surah = widget.repository.surah(_selectedSurah);
    if (surah == null || surah.ayahs.isEmpty) {
      setState(() {
        _loading = false;
        _error = uiText(widget.language, 'audioError');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _player.stop();
      final safeIndex = startIndex.clamp(0, surah.ayahs.length - 1).toInt();
      final ayah = surah.ayahs[safeIndex];
      final globalNumber = globalAyahNumberFor(widget.repository, ayah);
      final sources = <AudioSource>[
        AudioSource.uri(
          Uri.parse(recitationAudioUrl(_reciter, surah.number, ayah.number, globalNumber)),
          tag: MediaItem(
            id: ayah.key,
            album: 'AlQari · Quran recitation',
            title: surah.nameEnglish + ' · Ayah ' + ayah.number.toString(),
            artist: _reciter.name,
          ),
        ),
      ];
      _currentPlaylistIndex = safeIndex;
      _currentPosition = Duration.zero;
      _translationSpeaking = false;
      activeRecitationWord.value = null;
      await _player.setAudioSources(
        sources,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      if (!mounted || generation != _loadGeneration) return;
      _initialized = true;
      setState(() => _loading = false);
      _syncCurrentRecitationPosition();
      if (autoplay) unawaited(_player.play());
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _initialized = false;
        _loading = false;
        _error = '${uiText(widget.language, 'audioError')}\n$error';
      });
    }
  }

  Future<void> _changeSurah(int value) async {
    final wasPlaying = _player.playing || _translationSpeaking;
    _manualNavigation = true;
    _translationSpeaking = false;
    await _translationTts.stop();
    setState(() => _selectedSurah = value);
    await _loadSurahPlaylist(autoplay: wasPlaying);
    _manualNavigation = false;
  }

  Future<void> _changeReciter(String value) async {
    if (value == _selectedReciter) return;
    final wasPlaying = _player.playing || _translationSpeaking;
    final currentIndex = _currentPlaylistIndex;
    _translationSpeaking = false;
    await _translationTts.stop();
    setState(() {
      _selectedReciter = value;
      _wordTimings = <String, List<RecitationTimingSegment>>{};
    });
    activeRecitationWord.value = null;
    unawaited(_loadWordTimings(value));
    await _loadSurahPlaylist(startIndex: currentIndex, autoplay: wasPlaying);
  }

  String _durationText(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _togglePlayback(PlayerState? state) async {
    if (_loading) return;
    try {
      if (_player.playing) {
        await _player.pause();
      } else if (_translationSpeaking) {
        _translationSpeaking = false;
        await _translationTts.stop();
      } else {
        if (state?.processingState == ProcessingState.completed) {
          if (_selectedSurah >= 114) {
            await _player.seek(Duration.zero, index: 0);
          } else {
            await _advanceToNextSurah();
            return;
          }
        }
        unawaited(_player.play());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '${uiText(widget.language, 'audioError')}\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final scheme = Theme.of(context).colorScheme;
    final outline = _borderColor(context);
    return Directionality(
      textDirection: isRtl(lang) ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, Color.lerp(scheme.primary, scheme.secondary, 0.34)!],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.graphic_eq_rounded, color: scheme.onPrimary, size: 30),
                const SizedBox(height: 12),
                Text(uiText(lang, 'recitation'), style: TextStyle(color: scheme.onPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(uiText(lang, 'streamAudioNote'), style: TextStyle(color: scheme.onPrimary.withAlpha(220), fontSize: 13, height: 1.45)),
              ]),
            ),
            const SizedBox(height: 16),
            _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(uiText(lang, 'chooseAudioSurah'), style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _selectedSurah,
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.menu_book_rounded), border: OutlineInputBorder()),
                items: [
                  for (final surah in widget.repository.surahs)
                    DropdownMenuItem<int>(value: surah.number, child: Text('${surah.number}. ${surah.nameEnglish} — ${surah.nameArabic}')),
                ],
                onChanged: _loading ? null : (value) { if (value != null) _changeSurah(value); },
              ),
              const SizedBox(height: 16),
              Text(uiText(lang, 'chooseReciter'), style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedReciter,
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.record_voice_over_rounded), border: OutlineInputBorder()),
                items: [
                  for (final reciter in supportedReciters)
                    DropdownMenuItem<String>(value: reciter.id, child: Text('${reciter.name} · ${reciter.arabicName}')),
                ],
                onChanged: _loading ? null : (value) { if (value != null) _changeReciter(value); },
              ),
              const SizedBox(height: 10),
              Text('${_reciter.bitrate} kbps · ${_reciter.id}', style: TextStyle(fontSize: 11, color: _mutedColor(context))),
              const SizedBox(height: 4),
              Text(
                _wordTimings.isNotEmpty
                    ? (lang == 'ur' ? 'لفظ بہ لفظ آڈیو ہائی لائٹ دستیاب ہے' : lang == 'sd' ? 'لفظ بہ لفظ آڊيو هاءِ لائيٽ موجود آهي' : 'Word-by-word audio highlighting available')
                    : (lang == 'ur' ? 'آیات کی سطح پر ہائی لائٹ' : lang == 'sd' ? 'آيت جي سطح تي هاءِ لائيٽ' : 'Ayah-level highlighting'),
                style: TextStyle(fontSize: 11, color: _wordTimings.isNotEmpty ? scheme.primary : _mutedColor(context), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              translationLanguageSelector(context, uiLanguage: lang, translationLanguage: widget.translationLanguage, onChanged: widget.onTranslationLanguage),
            ])),
            const SizedBox(height: 12),
            _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.queue_music_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('${_surah.nameEnglish} · ${_surah.numberOfAyahs} ayat', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface))),
              ]),
              const SizedBox(height: 16),
              StreamBuilder<int?>(
                stream: _player.currentIndexStream,
                initialData: 0,
                builder: (context, snapshot) {
                  final index = (snapshot.data ?? 0).clamp(0, _surah.ayahs.length - 1).toInt();
                  final ayah = _surah.ayahs[index];
                  if (activeRecitationAyahKey.value != ayah.key) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (activeRecitationAyahKey.value != ayah.key) {
                        activeRecitationAyahKey.value = ayah.key;
                      }
                    });
                  }
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: _softSurfaceColor(context), borderRadius: BorderRadius.circular(20), border: Border.all(color: outline)),
                    child: Column(children: [
                      Text(uiText(lang, 'currentAyah'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                      const SizedBox(height: 10),
                      Text('﴿ ${ayah.number} ﴾', style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(ayah.arabic, textDirection: TextDirection.rtl, textAlign: TextAlign.center, style: quranTextStyle(context, fontSize: widget.arabicScale, height: 2.15, color: scheme.onSurface)),
                      const SizedBox(height: 10),
                      Text(ayah.translationFor(widget.translationLanguage), textDirection: isRtl(widget.translationLanguage) ? TextDirection.rtl : TextDirection.ltr, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.65, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text('${_surah.nameEnglish} · ${_surah.number}:${ayah.number}', style: TextStyle(fontSize: 11, color: _mutedColor(context))),
                    ]),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12, height: 1.4))),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _loading ? null : () => _loadSurahPlaylist(), icon: const Icon(Icons.refresh_rounded), label: Text(uiText(lang, 'tryAgain'))),
              ],
              const SizedBox(height: 12),
              StreamBuilder<Duration?>(
                stream: _player.durationStream,
                builder: (context, durationSnapshot) => StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  initialData: Duration.zero,
                  builder: (context, positionSnapshot) {
                    final duration = durationSnapshot.data ?? Duration.zero;
                    final position = positionSnapshot.data ?? Duration.zero;
                    final max = duration.inMilliseconds.toDouble();
                    final value = max > 0 ? position.inMilliseconds.toDouble().clamp(0.0, max).toDouble() : 0.0;
                    return Column(children: [
                      Slider(value: value, min: 0, max: max > 0 ? max : 1, onChanged: max > 0 && !_loading ? (next) => _player.seek(Duration(milliseconds: next.round())) : null),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(_durationText(position), style: TextStyle(fontSize: 11, color: _mutedColor(context))),
                        Text(_durationText(duration), style: TextStyle(fontSize: 11, color: _mutedColor(context))),
                      ]),
                    ]);
                  },
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  final playing = state?.playing ?? false;
                  final completed = state?.processingState == ProcessingState.completed;
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton.filledTonal(
                      tooltip: uiText(lang, 'previousAyah'),
                      onPressed: _loading
                          ? null
                          : () {
                              _manualNavigation = true;
                              _translationSpeaking = false;
                              unawaited(_translationTts.stop());
                              if (_currentPlaylistIndex > 0) {
                                unawaited(_loadSurahPlaylist(startIndex: _currentPlaylistIndex - 1, autoplay: true));
                              } else {
                                unawaited(_loadSurahPlaylist(startIndex: 0, autoplay: true));
                              }
                              _manualNavigation = false;
                            },
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 28,
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 66,
                      height: 66,
                      child: FilledButton(
                        onPressed: _loading ? null : () => _togglePlayback(state),
                        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                        child: _loading
                            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                            : Icon(playing ? Icons.pause_rounded : completed ? Icons.replay_rounded : Icons.play_arrow_rounded, size: 36),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      tooltip: uiText(lang, 'nextAyah'),
                      onPressed: _loading ? null : () {
                        _manualNavigation = true;
                        _translationSpeaking = false;
                        unawaited(_translationTts.stop());
                        final surah = widget.repository.surah(_selectedSurah);
                        if (surah != null && _currentPlaylistIndex + 1 < surah.ayahs.length) {
                          unawaited(_loadSurahPlaylist(startIndex: _currentPlaylistIndex + 1, autoplay: true));
                        } else {
                          unawaited(_advanceToNextSurah());
                        }
                        _manualNavigation = false;
                      },
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 28,
                    ),
                  ]);
                },
              ),
            ])),
            const SizedBox(height: 12),
            _settingsCard(context, child: Text(uiText(lang, 'audioSourceNote'), style: TextStyle(fontSize: 12, height: 1.55, color: _mutedColor(context)))),
          ],
        ),
      ),
      ),
    );
  }
}

class VerseCard extends StatelessWidget {
  final QuranRepository repository;
  final Ayah ayah;
  final String language;
  final String? translationLanguage;
  final double arabicScale;
  final bool isBookmarked;
  final bool isLastRead;
  final ActiveRecitationWord? activeWordRange;
  final VoidCallback onBookmark;
  final VoidCallback onReadAyah;

  const VerseCard({
    super.key,
    required this.repository,
    required this.ayah,
    required this.language,
    this.translationLanguage,
    required this.arabicScale,
    required this.isBookmarked,
    required this.onBookmark,
    required this.onReadAyah,
    this.isLastRead = false,
    this.activeWordRange,
  });

  @override
  Widget build(BuildContext context) {
    final surah = repository.surah(ayah.surahNumber)!;
    final scheme = Theme.of(context).colorScheme;
    final selectedTranslation = translationLanguage ?? language;
    final words = ayah.arabic.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    // Keep ayat in a continuous Mushaf-like stream rather than separate cards.
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      shape: Border(
        bottom: BorderSide(
          color: isLastRead ? scheme.primary : _borderColor(context).withAlpha(100),
          width: isLastRead ? 1.7 : 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: scheme.primary.withAlpha(22), borderRadius: BorderRadius.circular(13), border: Border.all(color: scheme.primary.withAlpha(34))),
              alignment: Alignment.center,
              child: Text('${ayah.number}', style: TextStyle(color: scheme.primary, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onReadAyah,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(surah.nameEnglish, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('${uiText(language, 'verse')} ${ayah.key}', style: TextStyle(color: _mutedColor(context), fontWeight: FontWeight.w500, fontSize: 11)),
                  ]),
                ),
              ),
            ),
            if (isLastRead) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: Tooltip(message: uiText(language, 'lastRead'), child: Icon(Icons.history_rounded, size: 18, color: scheme.primary))),
            IconButton(
              tooltip: isBookmarked ? uiText(language, 'removeBookmark') : uiText(language, 'bookmark'),
              onPressed: () { onReadAyah(); onBookmark(); },
              icon: Icon(isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: isBookmarked ? scheme.primary : _mutedColor(context)),
              style: IconButton.styleFrom(backgroundColor: _softSurfaceColor(context), minimumSize: const Size(40, 40)),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: _arabicWordSurfaceColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderColor(context).withAlpha(95)),
              ),
              child: Wrap(
                alignment: WrapAlignment.start,
                runAlignment: WrapAlignment.start,
                spacing: 4,
                runSpacing: 7,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Builder(builder: (context) {
                      final timing = activeWordRange;
                      final isActiveWord = timing != null &&
                          timing.ayahKey == ayah.key &&
                          i >= timing.wordStartIndex &&
                          i < timing.wordEndIndex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          onReadAyah();
                          showWordAnalysis(context, repository, ayah, i + 1, words[i], language);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: isActiveWord ? gold.withAlpha(150) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isActiveWord ? Border.all(color: gold, width: 1) : null,
                          ),
                          child: Text(
                            words[i],
                            textDirection: TextDirection.rtl,
                            style: quranTextStyle(context, fontSize: arabicScale, height: 2.0, color: scheme.onSurface),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 9),
          Text('${uiText(language, 'translation')} · ${uiText(language, selectedTranslation == 'ur' ? 'urdu' : selectedTranslation == 'sd' ? 'sindhi' : 'english')}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            ayah.translationFor(selectedTranslation),
            textDirection: isRtl(selectedTranslation) ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(fontSize: 15, height: 1.65, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _smallTag(context, '${uiText(language, 'juz')} ${ayah.juz}'),
            if (ayah.page > 0) _smallTag(context, 'Page ${ayah.page}'),
            if (ayah.sajda != null && ayah.sajda != false) _smallTag(context, 'Sajdah'),
          ]),
        ]),
      ),
    );
  }
}

Widget _smallTag(BuildContext context, String value) => Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _softSurfaceColor(context), borderRadius: BorderRadius.circular(8)),
      child: Text(value, style: TextStyle(fontSize: 10, color: _mutedColor(context))),
    );

void showWordAnalysis(BuildContext context, QuranRepository repository, Ayah ayah, int wordPosition, String wordText, String language) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) => _WordAnalysisSheet(repository: repository, ayah: ayah, wordPosition: wordPosition, wordText: wordText, language: language),
  );
}

class _WordAnalysisSheet extends StatefulWidget {
  final QuranRepository repository;
  final Ayah ayah;
  final int wordPosition;
  final String wordText;
  final String language;
  const _WordAnalysisSheet({required this.repository, required this.ayah, required this.wordPosition, required this.wordText, required this.language});
  @override
  State<_WordAnalysisSheet> createState() => _WordAnalysisSheetState();
}

class _WordAnalysisSheetState extends State<_WordAnalysisSheet> {
  bool _loading = true;
  OnlineWordGloss? _online;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final result = await fetchWordGloss(widget.ayah.key, widget.wordPosition, widget.language);
    if (!mounted) return;
    setState(() { _online = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final local = widget.repository.wordMorphology(widget.ayah.surahNumber, widget.ayah.number, widget.wordPosition);
    final root = (local?.root.isNotEmpty == true) ? local!.root : (_online?.root ?? '');
    final lemma = (local?.lemma.isNotEmpty == true) ? local!.lemma : (_online?.lemma ?? '');
    final pos = local?.pos ?? '';
    final segments = local?.segments ?? const <MorphSegment>[];
    final posPretty = _partOfSpeech(pos, lang);
    final transliteration = _online?.transliteration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: _borderColor(context), borderRadius: BorderRadius.circular(9)))),
          const SizedBox(height: 18),
          Text(uiText(lang, 'wordAnalysis'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 12),
          Text(widget.wordText, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: quranTextStyle(context, fontSize: 42, height: 2.15, color: Theme.of(context).colorScheme.onSurface)),
          if (transliteration?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(transliteration!, textAlign: TextAlign.center, style: TextStyle(color: _mutedColor(context))),
          ],
          const SizedBox(height: 8),
          Text('${uiText(lang, 'surah')} ${widget.ayah.surahNumber} · ${uiText(lang, 'verse')} ${widget.ayah.number}', textAlign: TextAlign.center, style: TextStyle(color: _mutedColor(context), fontSize: 12)),
          const SizedBox(height: 15),
          _detailCard(context, uiText(lang, 'onlineGloss'), _loading ? uiText(lang, 'glossLoading') : (_online?.gloss?.trim().isNotEmpty == true ? _online!.gloss! : uiText(lang, 'glossUnavailable'))),
          _detailCard(context, uiText(lang, 'root'), root.isEmpty ? uiText(lang, 'noRoot') : root),
          _detailCard(context, uiText(lang, 'lemma'), lemma.isEmpty ? '—' : lemma),
          _detailCard(context, uiText(lang, 'pos'), posPretty.isEmpty ? (pos.isEmpty ? '—' : pos) : posPretty),
          _detailCard(context, uiText(lang, 'sarf'), local?.sarfDescription(lang) ?? uiText(lang, 'noMorph')),
          _detailCard(context, uiText(lang, 'nahw'), _nahwHelp(lang, local)),
          _detailCard(context, uiText(lang, 'irab'), local?.irabDescription(lang) ?? uiText(lang, 'noMorph')),
          if (segments.isNotEmpty) _detailCard(context, uiText(lang, 'morphology'), segments.map((s) => '${s.tag}: ${s.features}').join('\n')),
          _detailCard(context, uiText(lang, 'verseMeaning'), widget.ayah.translationFor(lang)),
          if (!_loading && _online?.gloss?.isNotEmpty != true) Text(uiText(lang, 'glossLanguageNote'), style: TextStyle(color: _mutedColor(context), height: 1.5, fontSize: 12)),
          const SizedBox(height: 5),
          Text('Word gloss: Quran Foundation API. Morphology: Quranic Arabic Corpus / mustafa0x. Morphological tags are reference data and are not a substitute for a teacher-verified sentence-level I‘rab lesson.', style: TextStyle(color: _mutedColor(context), fontSize: 11, height: 1.45)),
        ]),
      ),
    );
  }
}

Widget _detailCard(BuildContext context, String title, String value) => Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 5),
        SelectableText(value, style: const TextStyle(height: 1.45, fontSize: 14)),
      ]),
    );

String _partOfSpeech(String pos, String lang) {
  final code = pos.isEmpty ? '' : pos;
  const labels = <String, Map<String, String>>{
    'N': {'en': 'Noun', 'ur': 'اسم', 'sd': 'اسم'},
    'PN': {'en': 'Proper noun', 'ur': 'اسمِ علم', 'sd': 'اسم خاص'},
    'V': {'en': 'Verb', 'ur': 'فعل', 'sd': 'فعل'},
    'P': {'en': 'Preposition / particle', 'ur': 'حرفِ جر / حرف', 'sd': 'حرف جر / حرف'},
    'ADJ': {'en': 'Adjective', 'ur': 'صفت', 'sd': 'صفت'},
    'DET': {'en': 'Determiner', 'ur': 'حرفِ تعریف', 'sd': 'تعريف جو حرف'},
    'PRON': {'en': 'Pronoun', 'ur': 'ضمیر', 'sd': 'ضمير'},
    'CONJ': {'en': 'Conjunction', 'ur': 'حرفِ عطف', 'sd': 'حرف عطف'},
    'DEM': {'en': 'Demonstrative', 'ur': 'اسمِ اشارہ', 'sd': 'اسم اشارو'},
    'REL': {'en': 'Relative pronoun', 'ur': 'اسمِ موصول', 'sd': 'اسم موصول'},
    'NEG': {'en': 'Negation particle', 'ur': 'حرفِ نفی', 'sd': 'حرف نفي'},
  };
  final label = labels[code];
  return label?[lang] ?? label?['en'] ?? code;
}

String _nahwHelp(String language, WordMorphology? morphology) {
  final pos = morphology?.pos ?? '';
  final segments = morphology?.segments ?? const <MorphSegment>[];
  if (morphology == null || (pos.isEmpty && segments.isEmpty)) return uiText(language, 'noMorph');
  final posText = _partOfSpeech(pos, language);
  final segmentText = segments.map((s) => s.tag).where((v) => v.isNotEmpty).toSet().join(' + ');
  const explanatory = {
    'en': 'This is corpus part-of-speech and segmentation support. A complete sentence-level syntactic relation is not provided by the morphology file itself.',
    'ur': 'یہ ماخذ کی قسمِ کلمہ اور لفظی اجزاء کی معلومات ہیں۔ صرفی فائل میں مکمل جملے کی نحوی نسبت شامل نہیں۔',
    'sd': 'هي ماخذ جي ڪلمي جي قسم ۽ لفظي جزن جي ڄاڻ آهي. صرفي فائل ۾ مڪمل جملي جو نحوي تعلق شامل ناهي.',
  };
  return '${posText.isEmpty ? pos : posText}${segmentText.isEmpty ? '' : ' · $segmentText'}\n\n${explanatory[language] ?? explanatory['en']}';
}

class SearchPage extends StatefulWidget {
  final QuranRepository repository;
  final String language;
  final String translationLanguage;
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  final Future<void> Function(Ayah) onReadAyah;
  const SearchPage({super.key, required this.repository, required this.language, required this.translationLanguage, required this.bookmarks, required this.arabicScale, required this.onBookmark, required this.onReadAyah});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  List<Ayah> get _matches {
    final q = removeQuranMarks(_query.toLowerCase());
    if (q.length < 2) return const [];
    final results = <Ayah>[];
    for (final ayah in widget.repository.allAyahs) {
      final haystacks = [removeQuranMarks(ayah.arabic.toLowerCase()), ...ayah.translations.values.map((v) => v.toLowerCase())];
      if (haystacks.any((h) => h.contains(q))) {
        results.add(ayah);
        if (results.length >= 250) break;
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final results = _matches;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          onSubmitted: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: uiText(lang, 'searchHint'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() => _query = ''); }),
            filled: true, fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: _query.trim().length < 2
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(uiText(lang, 'searchPrompt'), textAlign: TextAlign.center, style: TextStyle(color: _mutedColor(context)))))
            : results.isEmpty
                ? Center(child: Text(uiText(lang, 'noResults')))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: results.length,
                    itemBuilder: (context, index) => VerseCard(
                      repository: widget.repository,
                      ayah: results[index],
                      language: lang,
                      translationLanguage: widget.translationLanguage,
                      arabicScale: widget.arabicScale,
                      isBookmarked: widget.bookmarks.contains(results[index].key),
                      onBookmark: () => widget.onBookmark(results[index]),
                      onReadAyah: () => widget.onReadAyah(results[index]),
                    ),
                  ),
      ),
      if (results.length >= 250) Padding(padding: const EdgeInsets.all(8), child: Text(lang == 'ur' ? 'پہلے 250 نتائج دکھائے گئے ہیں۔' : lang == 'sd' ? 'پهريان 250 نتيجا ڏيکاريا ويا آهن.' : 'Showing the first 250 matches.', style: TextStyle(color: _mutedColor(context), fontSize: 11))),
    ]);
  }
}

class BookmarksPage extends StatelessWidget {
  final QuranRepository repository;
  final String language;
  final String translationLanguage;
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  final Future<void> Function(Ayah) onReadAyah;
  const BookmarksPage({super.key, required this.repository, required this.language, required this.translationLanguage, required this.bookmarks, required this.arabicScale, required this.onBookmark, required this.onReadAyah});

  @override
  Widget build(BuildContext context) {
    final saved = repository.allAyahs.where((ayah) => bookmarks.contains(ayah.key)).toList(growable: false);
    if (saved.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bookmark_border, size: 45, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), Text(uiText(language, 'bookmarks'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 8), Text(uiText(language, 'bookmark'), style: TextStyle(color: _mutedColor(context)))])));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: saved.length,
      itemBuilder: (context, index) => VerseCard(
        repository: repository, ayah: saved[index], language: language, translationLanguage: translationLanguage, arabicScale: arabicScale,
        isBookmarked: true, onBookmark: () => onBookmark(saved[index]), onReadAyah: () => onReadAyah(saved[index]),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final String language;
  final double arabicScale;
  final Map<String, dynamic> manifest;
  final ValueChanged<String> onLanguage;
  final ValueChanged<double> onArabicScale;
  final String themeMode;
  final int accentIndex;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<int> onAccentIndex;

  const SettingsPage({
    super.key,
    required this.language,
    required this.arabicScale,
    required this.manifest,
    required this.onLanguage,
    required this.onArabicScale,
    required this.themeMode,
    required this.accentIndex,
    required this.onThemeMode,
    required this.onAccentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final translations = manifest['translations'] as Map<String, dynamic>? ?? const {};
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'appearance'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 6),
        Text('Choose Light, Dark, or follow your phone setting.', style: TextStyle(color: _mutedColor(context), height: 1.4)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'system', label: Text(uiText(language, 'systemTheme')), icon: const Icon(Icons.settings_suggest_outlined)),
            ButtonSegment(value: 'light', label: Text(uiText(language, 'lightTheme')), icon: const Icon(Icons.light_mode_outlined)),
            ButtonSegment(value: 'dark', label: Text(uiText(language, 'darkTheme')), icon: const Icon(Icons.dark_mode_outlined)),
          ],
          selected: {themeMode},
          onSelectionChanged: (selected) => onThemeMode(selected.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 18),
        Text(uiText(language, 'accentColor'), style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < appAccentColors.length; i++)
            ChoiceChip(
              label: Text(appAccentNames[i]),
              selected: accentIndex == i,
              avatar: CircleAvatar(radius: 8, backgroundColor: appAccentColors[i]),
              onSelected: (_) => onAccentIndex(i),
            ),
        ]),
      ])),
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'language'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 10),
        RadioGroup<String>(
          groupValue: language,
          onChanged: (String? value) { if (value != null) onLanguage(value); },
          child: Column(children: [
            for (final entry in [
              ('en', uiText(language, 'english')),
              ('ur', uiText(language, 'urdu')),
              ('sd', uiText(language, 'sindhi')),
            ])
              RadioListTile<String>(contentPadding: EdgeInsets.zero, value: entry.$1, title: Text(entry.$2)),
          ]),
        ),
      ])),
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'arabicSize'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 6),
        Text('Amiri Quran · Quranic Arabic typeface', style: TextStyle(fontSize: 12, color: _mutedColor(context), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ', textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: quranTextStyle(context, fontSize: arabicScale, height: 2.15, color: scheme.onSurface)),
        Slider(value: arabicScale.clamp(26, 50).toDouble(), min: 26, max: 50, divisions: 12, label: arabicScale.round().toString(), onChanged: onArabicScale),
        Text('The font loads and caches when the device is online. On a first launch without internet, a system fallback may appear until the font has loaded once.', style: TextStyle(fontSize: 11, height: 1.45, color: _mutedColor(context))),
      ])),
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'lastRead'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 6),
        Text('Your last selected Surah / Juz is saved on this device. Use Continue reading in the side menu to return to the reader.', style: TextStyle(height: 1.5, color: _mutedColor(context))),
      ])),
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'fullCoverage'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 6),
        Text(uiText(language, 'verseCount')),
        const SizedBox(height: 8),
        Text(uiText(language, 'offlineNote'), style: TextStyle(height: 1.5, color: _mutedColor(context))),
      ])),
      _settingsCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'sourceNotice'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
        const SizedBox(height: 10),
        _sourceEntry(context, 'Quran text', 'AlQuran Cloud API · quran-uthmani edition. Source text is preserved without modification.'),
        _sourceEntry(context, 'Verse translations', 'Translator and edition identifiers are recorded in assets/data/data_manifest.json. Each translation remains subject to its source terms.'),
        _sourceEntry(context, 'Arabic typeface', 'Amiri Quran by the Amiri Project authors, delivered through Google Fonts. SIL Open Font License 1.1. A system fallback is used until the font has downloaded and cached.'),
        _sourceEntry(context, 'Recitation audio', 'Al Quran Cloud CDN and EveryAyah.com. Audio is streamed and remains subject to the selected provider’s terms.'),
        _sourceEntry(context, 'Word timings', 'cpfair/quran-align, release-2016-11-24, CC BY 4.0. See the generated manifest and word_timings_LICENSE.txt.'),
        _sourceEntry(context, 'Word gloss', 'Quran Foundation API at api.quran.com; requested online as needed.'),
        _sourceEntry(context, 'Arabic morphology', 'Quranic Arabic Corpus / mustafa0x/quran-morphology. Source morphology data is included verbatim with attribution.'),
        _sourceEntry(context, 'Prayer times', 'AlAdhan Prayer Times API, method 1 (University of Islamic Sciences, Karachi), using device location. Check your local mosque timetable if local practice differs.'),
        _sourceEntry(context, 'Adhan recording', 'Beautiful adhan.ogg by Adam-synagda, Wikimedia Commons, CC0 1.0: https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg.'),
        _sourceEntry(context, 'App feature libraries', 'Background media: just_audio_background / audio_service (MIT). Notifications: flutter_local_notifications (BSD-3-Clause). Location: geolocator (MIT). Time-zone handling: flutter_timezone (Apache-2.0) and timezone (BSD-2-Clause). AI tutoring uses Google Gemini API; the user supplies the key.'),
        const SizedBox(height: 12),
        for (final lang in ['en', 'ur', 'sd']) if (translations[lang] is Map<String, dynamic>) ...[
          Text('${lang.toUpperCase()}: ${(translations[lang] as Map<String, dynamic>)['identifier'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text('${(translations[lang] as Map<String, dynamic>)['translator'] ?? ''} · ${(translations[lang] as Map<String, dynamic>)['version'] ?? ''}', style: TextStyle(fontSize: 12, color: _mutedColor(context))),
          const SizedBox(height: 4),
        ],
      ])),
    ]);
  }
}



class PrayerTimesPage extends StatefulWidget {
  final String language;
  const PrayerTimesPage({super.key,required this.language});
  @override
  State<PrayerTimesPage> createState()=>_PrayerTimesPageState();
}
class _PrayerTimesPageState extends State<PrayerTimesPage>{
  static const names=['Fajr','Dhuhr','Asr','Maghrib','Isha'];
  static const keys=['fajr','dhuhr','asr','maghrib','isha'];
  static const baseId=5000;
  final FlutterLocalNotificationsPlugin notifications=FlutterLocalNotificationsPlugin();
  bool busy=false,ready=false,exactAllowed=false;
  double? latitude,longitude;
  Map<String,String> todayTimes=const {};
  String? errorText,statusText;
  int scheduledCount=0;
  String dateKey(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
  @override
  void initState(){super.initState();restoreLocation();}
  Future<void> restoreLocation()async{
    try{final p=await SharedPreferences.getInstance();final lat=p.getDouble('prayerLatitude'),lon=p.getDouble('prayerLongitude');
      if (lat == null || lon == null) return;
      if (mounted) setState(() { latitude = lat; longitude = lon; });
      final data=await fetchDays(lat,lon,DateTime.now(),1);if(mounted)setState(()=>todayTimes=data[dateKey(DateTime.now())]??const {});
    }catch(_){}
  }
  Future<void> initNotifications()async{
    tzdata.initializeTimeZones();
    try{final zone=await FlutterTimezone.getLocalTimezone();tz.setLocalLocation(tz.getLocation(zone.identifier));}catch(_){tz.setLocalLocation(tz.getLocation('Asia/Karachi'));}
    if(ready)return;
    await notifications.initialize(settings:const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));
    final android=notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted=await android?.requestNotificationsPermission();if(granted==false)throw Exception('Notification permission was not granted.');
    exactAllowed=await android?.requestExactAlarmsPermission()??false;ready=true;
  }
  Future<Position> obtainLocation()async{
    if(!await Geolocator.isLocationServiceEnabled()){await Geolocator.openLocationSettings();throw Exception('Turn on phone Location/GPS and retry.');}
    var permission=await Geolocator.checkPermission();if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw Exception('Location permission was denied. Allow it in settings and retry.');
    var position=await Geolocator.getLastKnownPosition();
    if(position==null||DateTime.now().difference(position.timestamp).abs()>const Duration(hours:12)){
      position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.medium,timeLimit:Duration(seconds:20)));
    }
    return position;
  }
  Future<Map<String,Map<String,String>>> fetchMonth(double lat,double lon,int year,int month)async{
    final uri=Uri.https('api.aladhan.com','/v1/calendar/'+year.toString()+'/'+month.toString(),{'latitude':lat.toStringAsFixed(6),'longitude':lon.toStringAsFixed(6),'method':'1','school':'1'});
    final response=await http.get(uri,headers:const {'Accept':'application/json'}).timeout(const Duration(seconds:18));
    if(response.statusCode!=200)throw Exception('Prayer-time service returned HTTP '+response.statusCode.toString()+'.');
    final data=jsonDecode(response.body) as Map<String,dynamic>;final list=data['data'] as List<dynamic>? ?? const [];
    final result=<String,Map<String,String>>{};
    for(final item in list){if(item is! Map<String,dynamic>)continue;final date=item['date'] as Map<String,dynamic>? ?? const {};final greg=date['gregorian'] as Map<String,dynamic>? ?? const {};final day=int.tryParse(greg['day']?.toString()??'');if(day==null)continue;
      final timings=item['timings'] as Map<String,dynamic>? ?? const {};final parsed=<String,String>{};
      for(final name in names){final m=RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(timings[name]?.toString()??'');if(m!=null)parsed[name]=m.group(1)!.padLeft(2,'0')+':'+m.group(2)!;}
      result[dateKey(DateTime(year,month,day))]=parsed;
    }
    if(result.isEmpty)throw Exception('Prayer-time service returned no times.');return result;
  }
  Future<Map<String,Map<String,String>>> fetchDays(double lat,double lon,DateTime start,int count)async{
    final days=List<DateTime>.generate(count,(i)=>DateTime(start.year,start.month,start.day+i));
    final months=<String>{for(final d in days)d.year.toString()+'-'+d.month.toString()};
    final all=<String,Map<String,String>>{};
    for(final m in months){final bits=m.split('-');all.addAll(await fetchMonth(lat,lon,int.parse(bits[0]),int.parse(bits[1])));}
    return {for(final d in days)if(all.containsKey(dateKey(d)))dateKey(d):all[dateKey(d)]!};
  }
  Future<void> enableAndSchedule()async{
    if (busy) return;
    setState(() { busy = true; errorText = null; statusText = null; });
    try{
      await initNotifications();final pos=await obtainLocation();final lat=pos.latitude,lon=pos.longitude;
      final prefs=await SharedPreferences.getInstance();await prefs.setDouble('prayerLatitude',lat);await prefs.setDouble('prayerLongitude',lon);
      final today=DateTime.now();final calendar=await fetchDays(lat,lon,today,7);final todays=calendar[dateKey(today)]??const <String,String>{};
      for(var id=baseId;id<baseId+40;id++){await notifications.cancel(id: id);}scheduledCount=0;
      final now=tz.TZDateTime.now(tz.local);final mode=exactAllowed?AndroidScheduleMode.exactAllowWhileIdle:AndroidScheduleMode.inexactAllowWhileIdle;
      for(var offset=0;offset<7;offset++){
        final date=DateTime(today.year,today.month,today.day+offset);final timings=calendar[dateKey(date)];if(timings==null)continue;
        for(var i=0;i<names.length;i++){
          final parts=(timings[names[i]]??'').split(':');if(parts.length!=2)continue;final hour=int.tryParse(parts[0]),minute=int.tryParse(parts[1]);if(hour==null||minute==null)continue;
          final when=tz.TZDateTime(tz.local,date.year,date.month,date.day,hour,minute);if(!when.isAfter(now))continue;final label=uiText(widget.language,keys[i]);final id=baseId+offset*5+i;
          const details=NotificationDetails(android:AndroidNotificationDetails('alqari_prayer_azan_v1','Prayer time Adhan',channelDescription:'Prayer reminders with Adhan notification audio.',importance:Importance.max,priority:Priority.high,playSound:true,sound:RawResourceAndroidNotificationSound('adhan'),enableVibration:true,visibility:NotificationVisibility.public));
          try{await notifications.zonedSchedule(id: id, title: 'AlQari · ' + label, body: 'It is time for ' + label + ' prayer.', scheduledDate: when, notificationDetails: details, androidScheduleMode: mode);}
          catch(_){await notifications.zonedSchedule(id: id, title: 'AlQari · ' + label, body: 'It is time for ' + label + ' prayer.', scheduledDate: when, notificationDetails: details, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);}
          scheduledCount++;
        }
      }
      if (mounted) setState(() {
        busy = false;
        latitude = lat;
        longitude = lon;
        todayTimes = todays;
        statusText = 'Scheduled ' + scheduledCount.toString() + ' reminders for seven days. ' +
          (exactAllowed ? 'Exact-alarm access is enabled.' : 'Exact-alarm access is off; Android may delay some alerts.');
      });
    } catch (e) {
      if (mounted) setState(() { busy = false; errorText = e.toString().replaceFirst('Exception: ', ''); });
    }
  }
  @override
  Widget build(BuildContext context){
    final lang=widget.language,scheme=Theme.of(context).colorScheme;final hasLocation=latitude!=null&&longitude!=null;
    return ListView(padding:const EdgeInsets.all(14),children:[
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(Icons.access_time_filled_rounded,color:scheme.primary,size:30),const SizedBox(height:8),
        Text(uiText(lang,'prayerTimes'),style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:scheme.primary)),
        const SizedBox(height:5),Text(uiText(lang,'prayerSubtitle'),style:TextStyle(color:scheme.onSurfaceVariant,fontSize:12)),
      ]))),
      const SizedBox(height:10),
      Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(hasLocation?latitude!.toStringAsFixed(4)+', '+longitude!.toStringAsFixed(4):'Location not selected yet',style:TextStyle(fontWeight:FontWeight.w700,color:scheme.onSurface)),
        const SizedBox(height:7),Text(uiText(lang,'prayerLocationNote'),style:TextStyle(fontSize:11,height:1.45,color:scheme.onSurfaceVariant)),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:busy?null:enableAndSchedule,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.notifications_active_outlined),label:Text(busy?uiText(lang,'prayerLoading'):uiText(lang,hasLocation?'updatePrayerAlerts':'enablePrayerAlerts'))),
        if(errorText!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(errorText!,style:TextStyle(color:scheme.error,fontSize:12))),
        if(statusText!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(statusText!,style:TextStyle(color:scheme.primary,fontSize:12))),
      ]))),
      const SizedBox(height:10),
      Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(lang=='ur'?'آج کے نماز کے اوقات':lang=='sd'?'اڄ جي نماز جا وقت':'Today’s prayer times',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:scheme.primary)),const SizedBox(height:8),
        if(todayTimes.isEmpty)Text('Enable location to load local prayer times.',style:TextStyle(color:scheme.onSurfaceVariant,fontSize:12))
        else for(var i=0;i<names.length;i++)...[if(i>0)const Divider(height:1),Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Row(children:[Icon(Icons.mosque_outlined,size:20,color:scheme.primary),const SizedBox(width:10),Expanded(child:Text(uiText(lang,keys[i]),style:TextStyle(fontWeight:FontWeight.w700,color:scheme.onSurface))),Text(todayTimes[names[i]]??'—',style:TextStyle(fontWeight:FontWeight.w800,color:scheme.primary))]))],
      ]))),
      const SizedBox(height:9),Text(uiText(lang,'prayerReminderNote'),style:TextStyle(color:scheme.onSurfaceVariant,fontSize:11,height:1.5)),
    ]);
  }
}

Widget _sourceEntry(BuildContext context, String title, String details) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
    const SizedBox(height: 3),
    Text(details, style: TextStyle(height: 1.45, color: _mutedColor(context), fontSize: 12)),
  ]),
);

Widget translationLanguageSelector(BuildContext context, {required String uiLanguage, required String translationLanguage, required ValueChanged<String> onChanged}) => DropdownButtonFormField<String>(
  key: ValueKey('translation-language-$translationLanguage'),
  initialValue: translationLanguage,
  isExpanded: true,
  decoration: InputDecoration(labelText: uiText(uiLanguage, 'translationLanguage'), prefixIcon: const Icon(Icons.translate_rounded), border: const OutlineInputBorder(), isDense: true),
  items: [
    DropdownMenuItem<String>(value: 'ur', child: Text(uiText(uiLanguage, 'urdu'))),
    DropdownMenuItem<String>(value: 'sd', child: Text(uiText(uiLanguage, 'sindhi'))),
    DropdownMenuItem<String>(value: 'en', child: Text(uiText(uiLanguage, 'english'))),
  ],
  onChanged: (value) { if (value != null) onChanged(value); },
);

Widget _settingsCard(BuildContext context, {required Widget child}) => Card(
      margin: const EdgeInsets.only(bottom: 13),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _borderColor(context))),
      child: Padding(padding: const EdgeInsets.all(17), child: child),
    );
