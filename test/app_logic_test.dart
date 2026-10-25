import 'package:flutter_test/flutter_test.dart';
import 'package:al_qari_app/main.dart';

void main() {
  test('Arabic search normalization strips harakat but preserves letters', () {
    expect(removeQuranMarks('الرَّحْمَٰنِ'), 'الرحمن');
  });

  test('Arabic search normalization leaves English text usable', () {
    expect(removeQuranMarks('Al-Quran 123'), 'Al-Quran 123');
  });
}
