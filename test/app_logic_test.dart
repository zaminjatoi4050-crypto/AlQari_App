
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:al_qari/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('brand logo asset is bundled with the app', () async {
    final ByteData logo;

    try {
      logo = await rootBundle.load(
        'assets/branding/al_qari_icon.png',
      );
    } catch (error) {
      fail(
        'Logo asset could not be loaded. Check pubspec.yaml '
        'and assets/branding/al_qari_icon.png. Error: $error',
      );
    }

    expect(
      logo.lengthInBytes,
      greaterThan(1024),
      reason: 'The logo file must be larger than 1024 bytes.',
    );
  });

  test('Quran text uses an explicit Quran-focused typeface', () {
    expect(quranFontFamily, 'Amiri Quran');
  });

  test('Arabic search normalization strips harakat but preserves letters', () {
    expect(removeQuranMarks('الرَّحْمَٰنِ'), 'الرحمن');
  });

  test('Arabic search normalization leaves English text usable', () {
    expect(removeQuranMarks('Al-Quran 123'), 'Al-Quran 123');
  });

  test('multiple supported reciters include well-known editions', () {
    expect(supportedReciters.length, greaterThanOrEqualTo(8));
    expect(
      supportedReciters.map((reciter) => reciter.id),
      contains('ar.alafasy'),
    );
    expect(
      supportedReciters.map((reciter) => reciter.id),
      contains('ar.abdulbasit'),
    );
    expect(
      supportedReciters.map((reciter) => reciter.id).toSet().length,
      supportedReciters.length,
    );
  });

  test('ayah audio URL uses the global ayah number and edition ID', () {
    expect(
      ayahAudioUrl('ar.alafasy', 262, bitrate: 128),
      'https://cdn.islamic.network/quran/audio/128/ar.alafasy/262.mp3',
    );
  });

  test('timed reciters use audio files paired with their word timings', () {
    expect(
      recitationAudioUrl(supportedReciters.first, 1, 1, 1),
      'https://everyayah.com/data/Alafasy_128kbps/001001.mp3',
    );
    final ajamy = supportedReciters.firstWhere((reciter) => reciter.id == 'ar.ajamy');
    expect(
      recitationAudioUrl(ajamy, 1, 1, 1),
      'https://everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/001001.mp3',
    );
  });

  test('word timing JSON parser reads zero-based word ranges in milliseconds', () {
    final parsed = parseWordTimingData(
      const {
        'reciters': {
          'ar.alafasy': {
            'verses': {
              '1:1': [
                [0, 1, 10, 250],
                [1, 3, 251, 700],
              ],
            },
          },
        },
      },
      'ar.alafasy',
    );

    expect(parsed['1:1'], hasLength(2));
    expect(parsed['1:1']!.first.wordStartIndex, 0);
    expect(parsed['1:1']!.first.wordEndIndex, 1);
    expect(parsed['1:1']!.first.startMs, 10);
    expect(parsed['1:1']!.last.wordEndIndex, 3);
    expect(parseWordTimingData(const {'reciters': {}}, 'ar.alafasy'), isEmpty);
  });

  test('generated timing asset contains full default-reciter verse timing data', () async {
    final decoded = jsonDecode(
      await rootBundle.loadString('assets/data/word_timings.json'),
    );
    expect(decoded, isA<Map>());
    final parsed = parseWordTimingData(
      Map<String, dynamic>.from(decoded as Map),
      'ar.alafasy',
    );
    expect(parsed.length, greaterThanOrEqualTo(6000));
    expect(parsed['1:1'], isNotEmpty);
  });

  test('ayah audio URL rejects out-of-range global ayah numbers', () {
    expect(
      () => ayahAudioUrl('ar.alafasy', 0),
      throwsA(isA<RangeError>()),
    );
    expect(
      () => ayahAudioUrl('ar.alafasy', 6237),
      throwsA(isA<RangeError>()),
    );
  });

  test('ayah audio URL rejects unknown reciter editions', () {
    expect(
      () => ayahAudioUrl('unknown.edition', 1),
      throwsA(isA<ArgumentError>()),
    );
  });
  test('ayah translation follows the selected language independently', () {
    final ayah = Ayah(
      surahNumber: 1,
      number: 1,
      key: '1:1',
      arabic: 'بِسْمِ اللَّهِ',
      translations: const {
        'en': 'English translation',
        'ur': 'اردو ترجمہ',
        'sd': 'سنڌي ترجمو',
      },
      juz: 1,
      page: 1,
      hizbQuarter: 1,
      ruku: 1,
      manzil: 1,
      sajda: null,
    );

    expect(ayah.translationFor('en'), 'English translation');
    expect(ayah.translationFor('ur'), 'اردو ترجمہ');
    expect(ayah.translationFor('sd'), 'سنڌي ترجمو');
  });

  test('ayah translation safely falls back to English for an unavailable locale', () {
    final ayah = Ayah(
      surahNumber: 1,
      number: 1,
      key: '1:1',
      arabic: 'بِسْمِ اللَّهِ',
      translations: const {'en': 'English translation', 'ur': 'اردو ترجمہ'},
      juz: 1,
      page: 1,
      hizbQuarter: 1,
      ruku: 1,
      manzil: 1,
      sajda: null,
    );

    expect(ayah.translationFor('sd'), 'English translation');
  });

}
