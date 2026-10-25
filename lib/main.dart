import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const Color forest = Color(0xFF153D33);
const Color green = Color(0xFF236B55);
const Color gold = Color(0xFFD8B56A);
const Color paper = Color(0xFFF7F5EF);

void main() => runApp(const AlQariApp());

/// Removes Arabic harakat for tolerant local search; it never modifies the
/// source text shown in the Quran reader.
String removeQuranMarks(String value) => value
    .replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
    .replaceAll('ـ', '')
    .trim();

String uiText(String language, String key) {
  const values = <String, Map<String, String>>{
    'app': {'en': 'AlQariApp', 'ur': 'القرآن سیکھیں', 'sd': 'القرآن سکو'},
    'tagline': {'en': 'Read • Understand • Reflect', 'ur': 'پڑھیں • سمجھیں • غور کریں', 'sd': 'پڙهو • سمجھو • غور ڪريو'},
    'reader': {'en': 'Quran Reader', 'ur': 'قرآن ریڈر', 'sd': 'قرآن پڙهڻ'},
    'search': {'en': 'Search', 'ur': 'تلاش', 'sd': 'ڳولا'},
    'bookmarks': {'en': 'Bookmarks', 'ur': 'محفوظ آیات', 'sd': 'محفوظ آيتون'},
    'settings': {'en': 'Settings', 'ur': 'ترتیبات', 'sd': 'سيٽنگون'},
    'selectJuz': {'en': 'Select Juz / Para', 'ur': 'پارہ منتخب کریں', 'sd': 'پارو چونڊيو'},
    'selectSurah': {'en': 'Select Surah', 'ur': 'سورۃ منتخب کریں', 'sd': 'سورت چونڊيو'},
    'juzMode': {'en': 'Juz / Para', 'ur': 'پارہ', 'sd': 'پارو'},
    'surahMode': {'en': 'Surah', 'ur': 'سورۃ', 'sd': 'سورت'},
    'translation': {'en': 'Translation of meaning', 'ur': 'ترجمۂ مفہوم', 'sd': 'مفهوم جو ترجمو'},
    'wordAnalysis': {'en': 'Word analysis', 'ur': 'لفظ کا تجزیہ', 'sd': 'لفظ جو تجزيو'},
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

  String translationFor(String language) => translations[language] ?? translations['en'] ?? '';
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
    final locationPattern = RegExp(r'^\((\d+):(\d+):(\d+):(\d+)\)$');
    for (final line in const LineSplitter().convert(source)) {
      if (line.trim().isEmpty || line.startsWith('LOCATION')) continue;
      List<String> parts = line.split('\t');
      if (parts.length < 4) {
        final m = RegExp(r'^\((\d+:\d+:\d+:\d+)\)\s+(\S+)\s+(\S+)\s+(.+)$').firstMatch(line);
        if (m == null) continue;
        parts = ['(${m.group(1)})', m.group(2)!, m.group(3)!, m.group(4)!];
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
        if (feature.startsWith('ROOT:')) rootByKey.putIfAbsent(key, () => _buckwalterToArabic(feature.substring(5)));
        else if (feature.startsWith('LEM:')) lemmaByKey.putIfAbsent(key, () => _buckwalterToArabic(feature.substring(4)));
        else if (feature.startsWith('POS:')) posByKey[key] = feature.substring(4);
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
      "'": 'ء', '>': 'أ', '&': 'ؤ', '<': 'إ', '}': 'ئ', 'A': 'ا', 'b': 'ب', 'p': 'ة',
      't': 'ت', 'v': 'ث', 'j': 'ج', 'H': 'ح', 'x': 'خ', 'd': 'د', '*': 'ذ', 'r': 'ر',
      'z': 'ز', 's': 'س', '$': 'ش', 'S': 'ص', 'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع',
      'g': 'غ', 'f': 'ف', 'q': 'ق', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'h': 'ه',
      'w': 'و', 'Y': 'ى', 'y': 'ي', '`': 'ٰ', '{': 'ٱ', '|': 'آ', '^': 'ٓ', '~': 'ّ',
      'o': 'ْ', 'a': 'َ', 'u': 'ُ', 'i': 'ِ', 'F': 'ً', 'N': 'ٌ', 'K': 'ٍ',
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

class AlQariApp extends StatefulWidget {
  const AlQariApp({super.key});

  @override
  State<AlQariApp> createState() => _AlQariAppState();
}

class _AlQariAppState extends State<AlQariApp> {
  late Future<QuranRepository> _repository = QuranRepository.load();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AlQariApp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, secondary: gold),
          scaffoldBackgroundColor: paper,
          appBarTheme: const AppBarTheme(backgroundColor: forest, foregroundColor: Colors.white, elevation: 0),
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFFF2E8CF),
            selectedColor: const Color(0xFFE0C889),
            side: const BorderSide(color: Color(0xFFE5D3A4)),
            labelStyle: const TextStyle(color: forest),
          ),
        ),
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
            return HomeShell(repository: snapshot.data!);
          },
        ),
      );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: forest,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.menu_book_rounded, color: gold, size: 64),
            const SizedBox(height: 18),
            const Text('AlQariApp', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 10),
            Text(uiText('en', 'loading'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: gold),
          ]),
        ),
      );
}

class _DataErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _DataErrorScreen({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AlQariApp')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off_rounded, size: 54, color: green),
            const SizedBox(height: 18),
            Text(uiText('en', 'loadError'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('Release APKs must be built with the GitHub Actions workflow so that the full Quran and morphology assets are generated and validated first.', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            SelectableText(error, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: Text(uiText('en', 'tryAgain'))),
          ]),
        ),
      );
}

class HomeShell extends StatefulWidget {
  final QuranRepository repository;
  const HomeShell({super.key, required this.repository});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String _language = 'en';
  double _arabicScale = 32;
  final Set<String> _bookmarks = <String>{};

  @override
  void initState() {
    super.initState();
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final lang = prefs.getString('language') ?? 'en';
      _language = const ['en', 'ur', 'sd'].contains(lang) ? lang : 'en';
      _arabicScale = (prefs.getDouble('arabicScale') ?? 32).clamp(26, 50).toDouble();
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

  Future<void> _toggleBookmark(Ayah ayah) async {
    setState(() {
      if (!_bookmarks.add(ayah.key)) _bookmarks.remove(ayah.key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bookmarks', _bookmarks.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final lang = _language;
    final titles = [uiText(lang, 'reader'), uiText(lang, 'search'), uiText(lang, 'bookmarks'), uiText(lang, 'settings')];
    return Directionality(
      textDirection: isRtl(lang) ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(uiText(lang, 'app'), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(uiText(lang, 'tagline'), style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _language,
                  dropdownColor: Colors.white,
                  iconEnabledColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
        body: IndexedStack(
          index: _tab,
          children: [
            ReaderPage(repository: widget.repository, language: lang, bookmarks: _bookmarks, arabicScale: _arabicScale, onBookmark: _toggleBookmark),
            SearchPage(repository: widget.repository, language: lang, bookmarks: _bookmarks, arabicScale: _arabicScale, onBookmark: _toggleBookmark),
            BookmarksPage(repository: widget.repository, language: lang, bookmarks: _bookmarks, arabicScale: _arabicScale, onBookmark: _toggleBookmark),
            SettingsPage(language: lang, arabicScale: _arabicScale, manifest: widget.repository.dataManifest, onLanguage: _setLanguage, onArabicScale: _setArabicScale),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: titles[0]),
            NavigationDestination(icon: const Icon(Icons.search), label: titles[1]),
            NavigationDestination(icon: const Icon(Icons.bookmark_border), selectedIcon: const Icon(Icons.bookmark), label: titles[2]),
            NavigationDestination(icon: const Icon(Icons.tune), label: titles[3]),
          ],
        ),
      ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  final QuranRepository repository;
  final String language;
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  const ReaderPage({super.key, required this.repository, required this.language, required this.bookmarks, required this.arabicScale, required this.onBookmark});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String _mode = 'juz';
  int _selectedJuz = 20;
  int _selectedSurah = 27;

  List<Ayah> get _visibleAyahs {
    if (_mode == 'surah') return widget.repository.surah(_selectedSurah)?.ayahs ?? const [];
    return widget.repository.allAyahs.where((a) => a.juz == _selectedJuz).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final ayahs = _visibleAyahs;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0xFFEAE7DD), borderRadius: BorderRadius.circular(14)),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'juz', label: Text(uiText(lang, 'juzMode')), icon: const Icon(Icons.bookmarks_outlined)),
                ButtonSegment(value: 'surah', label: Text(uiText(lang, 'surahMode')), icon: const Icon(Icons.menu_book_outlined)),
              ],
              selected: {_mode},
              onSelectionChanged: (selected) => setState(() => _mode = selected.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 10),
          if (_mode == 'juz')
            DropdownButtonFormField<int>(
              value: _selectedJuz,
              isExpanded: true,
              decoration: InputDecoration(labelText: uiText(lang, 'selectJuz'), border: const OutlineInputBorder(), isDense: true),
              items: [for (var juz = 1; juz <= 30; juz++) DropdownMenuItem(value: juz, child: Text('${uiText(lang, 'juz')} $juz'))],
              onChanged: (value) { if (value != null) setState(() => _selectedJuz = value); },
            )
          else
            DropdownButtonFormField<int>(
              value: _selectedSurah,
              isExpanded: true,
              decoration: InputDecoration(labelText: uiText(lang, 'selectSurah'), border: const OutlineInputBorder(), isDense: true),
              items: widget.repository.surahs.map((s) => DropdownMenuItem(value: s.number, child: Text('${s.number}. ${s.nameEnglish} — ${s.nameArabic}'))).toList(),
              onChanged: (value) { if (value != null) setState(() => _selectedSurah = value); },
            ),
          const SizedBox(height: 6),
          Text('${ayahs.length} ${uiText(lang, 'verse')}${ayahs.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
      ),
      Expanded(
        child: ayahs.isEmpty
            ? Center(child: Text(uiText(lang, 'noResults')))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                itemCount: ayahs.length,
                itemBuilder: (context, index) => VerseCard(
                  repository: widget.repository,
                  ayah: ayahs[index],
                  language: lang,
                  arabicScale: widget.arabicScale,
                  isBookmarked: widget.bookmarks.contains(ayahs[index].key),
                  onBookmark: () => widget.onBookmark(ayahs[index]),
                ),
              ),
      ),
    ]);
  }
}

class VerseCard extends StatelessWidget {
  final QuranRepository repository;
  final Ayah ayah;
  final String language;
  final double arabicScale;
  final bool isBookmarked;
  final VoidCallback onBookmark;
  const VerseCard({super.key, required this.repository, required this.ayah, required this.language, required this.arabicScale, required this.isBookmarked, required this.onBookmark});

  @override
  Widget build(BuildContext context) {
    final surah = repository.surah(ayah.surahNumber)!;
    final words = ayah.arabic.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE8E5DC))),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${surah.nameEnglish} · ${ayah.key}', style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 12))),
            IconButton(
              tooltip: isBookmarked ? uiText(language, 'removeBookmark') : uiText(language, 'bookmark'),
              onPressed: onBookmark,
              icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border, color: isBookmarked ? green : Colors.black45),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.start,
              spacing: 7,
              runSpacing: 10,
              children: [
                for (var i = 0; i < words.length; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showWordAnalysis(context, repository, ayah, i + 1, words[i], language),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFFFFCF4), borderRadius: BorderRadius.circular(8)),
                      child: Text(words[i], style: TextStyle(fontSize: arabicScale, height: 1.8, color: forest, fontFamily: 'serif')),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 9),
          Text(uiText(language, 'translation'), style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            ayah.translationFor(language),
            textDirection: isRtl(language) ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(fontSize: 15, height: 1.65, color: Color(0xFF343A37)),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _smallTag('${uiText(language, 'juz')} ${ayah.juz}'),
            if (ayah.page > 0) _smallTag('Page ${ayah.page}'),
            if (ayah.sajda != null && ayah.sajda != false) _smallTag('Sajdah'),
          ]),
        ]),
      ),
    );
  }
}

Widget _smallTag(String value) => Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF0EEE7), borderRadius: BorderRadius.circular(8)),
      child: Text(value, style: const TextStyle(fontSize: 10, color: Colors.black54)),
    );

void showWordAnalysis(BuildContext context, QuranRepository repository, Ayah ayah, int wordPosition, String wordText, String language) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paper,
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
          Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(9)))),
          const SizedBox(height: 18),
          Text(uiText(lang, 'wordAnalysis'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: forest)),
          const SizedBox(height: 12),
          Text(widget.wordText, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 38, color: forest, fontFamily: 'serif')),
          if (transliteration?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(transliteration!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          Text('${uiText(lang, 'surah')} ${widget.ayah.surahNumber} · ${uiText(lang, 'verse')} ${widget.ayah.number}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black45, fontSize: 12)),
          const SizedBox(height: 15),
          _detailCard(uiText(lang, 'onlineGloss'), _loading ? uiText(lang, 'glossLoading') : (_online?.gloss?.trim().isNotEmpty == true ? _online!.gloss! : uiText(lang, 'glossUnavailable'))),
          _detailCard(uiText(lang, 'root'), root.isEmpty ? uiText(lang, 'noRoot') : root),
          _detailCard(uiText(lang, 'lemma'), lemma.isEmpty ? '—' : lemma),
          _detailCard(uiText(lang, 'pos'), posPretty.isEmpty ? (pos.isEmpty ? '—' : pos) : posPretty),
          _detailCard(uiText(lang, 'sarf'), local?.sarfDescription(lang) ?? uiText(lang, 'noMorph')),
          _detailCard(uiText(lang, 'nahw'), _nahwHelp(lang, local)),
          _detailCard(uiText(lang, 'irab'), local?.irabDescription(lang) ?? uiText(lang, 'noMorph')),
          if (segments.isNotEmpty) _detailCard(uiText(lang, 'morphology'), segments.map((s) => '${s.tag}: ${s.features}').join('\n')),
          _detailCard(uiText(lang, 'verseMeaning'), widget.ayah.translationFor(lang)),
          if (!_loading && _online?.gloss?.isNotEmpty != true) Text(uiText(lang, 'glossLanguageNote'), style: const TextStyle(color: Colors.black54, height: 1.5, fontSize: 12)),
          const SizedBox(height: 5),
          const Text('Word gloss: Quran Foundation API. Morphology: Quranic Arabic Corpus / mustafa0x. Morphological tags are reference data and are not a substitute for a teacher-verified sentence-level I‘rab lesson.', style: TextStyle(color: Colors.black45, fontSize: 11, height: 1.45)),
        ]),
      ),
    );
  }
}

Widget _detailCard(String title, String value) => Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE8E5DC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: 13)),
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
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  const SearchPage({super.key, required this.repository, required this.language, required this.bookmarks, required this.arabicScale, required this.onBookmark});
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
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: _query.trim().length < 2
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(uiText(lang, 'searchPrompt'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))))
            : results.isEmpty
                ? Center(child: Text(uiText(lang, 'noResults')))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: results.length,
                    itemBuilder: (context, index) => VerseCard(
                      repository: widget.repository,
                      ayah: results[index],
                      language: lang,
                      arabicScale: widget.arabicScale,
                      isBookmarked: widget.bookmarks.contains(results[index].key),
                      onBookmark: () => widget.onBookmark(results[index]),
                    ),
                  ),
      ),
      if (results.length >= 250) Padding(padding: const EdgeInsets.all(8), child: Text(lang == 'ur' ? 'پہلے 250 نتائج دکھائے گئے ہیں۔' : lang == 'sd' ? 'پهريان 250 نتيجا ڏيکاريا ويا آهن.' : 'Showing the first 250 matches.', style: const TextStyle(color: Colors.black45, fontSize: 11))),
    ]);
  }
}

class BookmarksPage extends StatelessWidget {
  final QuranRepository repository;
  final String language;
  final Set<String> bookmarks;
  final double arabicScale;
  final Future<void> Function(Ayah) onBookmark;
  const BookmarksPage({super.key, required this.repository, required this.language, required this.bookmarks, required this.arabicScale, required this.onBookmark});

  @override
  Widget build(BuildContext context) {
    final saved = repository.allAyahs.where((ayah) => bookmarks.contains(ayah.key)).toList(growable: false);
    if (saved.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.bookmark_border, size: 45, color: green), const SizedBox(height: 12), Text(uiText(language, 'bookmarks'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 8), Text(uiText(language, 'bookmark'), style: const TextStyle(color: Colors.black54))])));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: saved.length,
      itemBuilder: (context, index) => VerseCard(
        repository: repository, ayah: saved[index], language: language, arabicScale: arabicScale,
        isBookmarked: true, onBookmark: () => onBookmark(saved[index]),
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
  const SettingsPage({super.key, required this.language, required this.arabicScale, required this.manifest, required this.onLanguage, required this.onArabicScale});

  @override
  Widget build(BuildContext context) {
    final translations = manifest['translations'] as Map<String, dynamic>? ?? const {};
    return ListView(padding: const EdgeInsets.all(16), children: [
      _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'language'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 10),
        for (final entry in [
          ('en', uiText(language, 'english')),
          ('ur', uiText(language, 'urdu')),
          ('sd', uiText(language, 'sindhi')),
        ]) RadioListTile<String>(contentPadding: EdgeInsets.zero, value: entry.$1, groupValue: language, title: Text(entry.$2), onChanged: (value) { if (value != null) onLanguage(value); }),
      ])),
      _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'arabicSize'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 6),
        Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'serif', fontSize: arabicScale, color: forest, height: 1.8)),
        Slider(value: arabicScale.clamp(26, 50).toDouble(), min: 26, max: 50, divisions: 12, label: arabicScale.round().toString(), onChanged: onArabicScale),
      ])),
      _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'fullCoverage'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 6),
        Text(uiText(language, 'verseCount')),
        const SizedBox(height: 8),
        Text(uiText(language, 'offlineNote'), style: const TextStyle(height: 1.5, color: Colors.black54)),
      ])),
      _settingsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(language, 'sourceNotice'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: forest)),
        const SizedBox(height: 10),
        const Text('Arabic text: AlQuran Cloud API, quran-uthmani edition; preserve Tanzil Project attribution and do not alter source text.\n\nVerse translations: translator / edition identifiers chosen and recorded at build time in assets/data/data_manifest.json. Follow the source terms.\n\nWord-by-word gloss: Quran Foundation API at api.quran.com (online request).\n\nWord morphology: Quranic Arabic Corpus / mustafa0x/quran-morphology; raw source text is included verbatim with source attribution.', style: TextStyle(height: 1.5)),
        const SizedBox(height: 12),
        for (final lang in ['en', 'ur', 'sd']) if (translations[lang] is Map<String, dynamic>) ...[
          Text('${lang.toUpperCase()}: ${(translations[lang] as Map<String, dynamic>)['identifier'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text('${(translations[lang] as Map<String, dynamic>)['translator'] ?? ''} · ${(translations[lang] as Map<String, dynamic>)['version'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
        ],
      ])),
    ]);
  }
}

Widget _settingsCard({required Widget child}) => Card(
      margin: const EdgeInsets.only(bottom: 13),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE8E5DC))),
      child: Padding(padding: const EdgeInsets.all(17), child: child),
    );
