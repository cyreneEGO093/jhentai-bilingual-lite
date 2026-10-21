// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Bilingual Lite v0.6.2. Deliberately conservative, not a language detector.
bool copiedForeignProse(String source, String translated, String target) {
  if (!RegExp(
          r'^(?:简体中文|繁體中文|繁体中文|中文|Chinese(?:\s*\([^)]*\))?|zh(?:[-_](?:CN|TW|HK|Hans|Hant))?)$',
          caseSensitive: false)
      .hasMatch(target.trim())) {
    return false;
  }
  String normalize(String value) =>
      value.replaceAll(RegExp(r'\s+', unicode: true), '');
  if (normalize(source) != normalize(translated)) {
    return false;
  }
  final prose = source.replaceAll(
      RegExp(r'https?://\S+|[@#][\p{L}\p{N}_]+', unicode: true), '');
  final kana =
      RegExp(r'[\p{Script=Hiragana}\p{Script=Katakana}]', unicode: true)
          .allMatches(prose)
          .length;
  final hangul =
      RegExp(r'\p{Script=Hangul}', unicode: true).allMatches(prose).length;
  return (kana >= 6 || hangul >= 8) &&
      (RegExp(r'[。！？.!?]').hasMatch(prose) ||
          RegExp(r'\s+').allMatches(prose).length >= 3);
}
