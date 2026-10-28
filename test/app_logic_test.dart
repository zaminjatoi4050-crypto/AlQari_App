import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:al_qari/main.dart';

void main() {

  test('brand logo asset is bundled with the app', () async {
    final logo = await rootBundle.load('assets/branding/al_qari_icon.png');
    expect(logo.lengthInBytes, greaterThan(1024));
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
    expect(supportedReciters.map((reciter) => reciter.id), contains('ar.alafasy'));
    expect(supportedReciters.map((reciter) => reciter.id), contains('ar.abdulbasit'));
    expect(supportedReciters.map((reciter) => reciter.id).toSet().length, supportedReciters.length);
  });

  test('ayah audio URL uses the global ayah number and edition ID', () {
    expect(
      ayahAudioUrl('ar.alafasy', 262, bitrate: 128),
      'https://cdn.islamic.network/quran/audio/128/ar.alafasy/262.mp3',
    );
  });

  test('ayah audio URL rejects out-of-range global ayah numbers', () {
    expect(() => ayahAudioUrl('ar.alafasy', 0), throwsA(isA<RangeError>()));
    expect(() => ayahAudioUrl('ar.alafasy', 6237), throwsA(isA<RangeError>()));
  });

  test('ayah audio URL rejects unknown reciter editions', () {
    expect(() => ayahAudioUrl('unknown.edition', 1), throwsA(isA<ArgumentError>()));
  });
}
