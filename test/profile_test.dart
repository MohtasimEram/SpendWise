import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/filter_font.dart';
import 'package:spendwise/ui.dart';
import 'package:spendwise/widgets.dart';

void main() {
  test('FilterFont.parse falls back to the default', () {
    expect(FilterFont.parse(null), FilterFont.jakarta);
    expect(FilterFont.parse('nonsense'), FilterFont.jakarta);
    expect(FilterFont.parse('classic'), FilterFont.classic);
    expect(FilterFont.parse('dmSans'), FilterFont.dmSans);
  });

  test('Classic keeps the original plain style (no custom family)', () {
    final st = FilterFont.classic.style(size: 14, weight: FontWeight.w700);
    expect(st.fontFamily, isNull);
    expect(st.fontSize, 14);
    expect(st.fontWeight, FontWeight.w700);
  });

  test('avatar ids are unique', () {
    final ids = kAvatars.map((a) => a.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.contains(kInitialAvatar), isFalse);
  });

  test('nickname rules: no spaces, 3-20 chars', () {
    expect(validateNickname('eram_01'), isNull);
    expect(validateNickname('a.b-c'), isNull);
    expect(validateNickname('has space'), isNotNull);
    expect(validateNickname('ab'), isNotNull);
    expect(validateNickname('x' * 21), isNotNull);
    expect(validateNickname('bad!char'), isNotNull);
    expect(validateNickname('  '), isNotNull);
    expect(sanitizeNick('Mohtasim Eram!'), 'MohtasimEram');
  });
}
