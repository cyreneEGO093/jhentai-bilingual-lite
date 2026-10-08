// SPDX-License-Identifier: GPL-3.0-only
// The normalized bbox contract is shared with bilingual-lite v0.6.0.
import 'dart:convert';
import 'dart:ui';

class TranslationFailure implements Exception {
  final String message;
  final int? status;
  const TranslationFailure(this.message, {this.status});
  @override
  String toString() => message;
}

class TranslationBubble {
  final String original;
  final String translated;
  final Rect bounds; // 0..1, relative to the image's painted rectangle.
  const TranslationBubble(this.original, this.translated, this.bounds);

  TranslationBubble withBounds(Rect value) =>
      TranslationBubble(original, translated, value);

  static List<TranslationBubble> parse(String content) {
    final dynamic decoded = parseJsonContent(content);
    final dynamic list = decoded is Map ? decoded['bubbles'] : decoded;
    if (list is! List || list.length > 60) {
      throw const TranslationFailure('译文格式无效，请重试或框选更小区域。');
    }
    return list.map((dynamic item) {
      if (item is! Map ||
          item['bbox'] is! List ||
          (item['bbox'] as List).length != 4) {
        throw const TranslationFailure('译文缺少有效坐标，请尝试框选翻译。');
      }
      final box = item['bbox'] as List;
      if (box.any((v) => v is! num || !v.isFinite || v < 0 || v > 1000) ||
          box[2] <= box[0] ||
          box[3] <= box[1]) {
        throw const TranslationFailure('译文坐标超出图片范围，请尝试框选翻译。');
      }
      return TranslationBubble(
        validText(item['original'], allowEmpty: true),
        validText(item['translated']),
        Rect.fromLTRB(
            box[1] / 1000, box[0] / 1000, box[3] / 1000, box[2] / 1000),
      );
    }).toList(growable: false);
  }
}

dynamic parseJsonContent(String content) {
  var text = content.trim();
  if (text.startsWith('```')) {
    text = text
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
  }
  try {
    return jsonDecode(text);
  } catch (_) {
    throw const TranslationFailure('译文格式无效，请重试或减少本次内容。');
  }
}

String validText(dynamic value, {bool allowEmpty = false}) {
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > 6000) {
    throw const TranslationFailure('模型未返回有效译文，请重试。');
  }
  return value.trim();
}

Rect clampTranslationRect(Rect rect) {
  final w = rect.width.clamp(0.035, 1.0);
  final h = rect.height.clamp(0.025, 1.0);
  return Rect.fromLTWH(
      rect.left.clamp(0, 1 - w), rect.top.clamp(0, 1 - h), w, h);
}
