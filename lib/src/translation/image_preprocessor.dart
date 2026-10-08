// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as raster;
import 'translation_models.dart';

class PreparedTranslationImage {
  final String dataUrl;
  final int width;
  final int height;
  const PreparedTranslationImage(this.dataUrl, this.width, this.height);
}

Future<PreparedTranslationImage> prepareTranslationImage(ui.Image image,
    {ui.Rect? crop}) async {
  final source = crop == null
      ? ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
      : ui.Rect.fromLTWH(crop.left * image.width, crop.top * image.height,
          crop.width * image.width, crop.height * image.height);
  if (source.width < 1 ||
      source.height < 1 ||
      source.left < 0 ||
      source.top < 0 ||
      source.right > image.width + 0.01 ||
      source.bottom > image.height + 0.01) {
    throw const TranslationFailure('框选区域无效，请重新框选。');
  }
  final scale = math.min(1.0, 1280 / math.max(source.width, source.height));
  final w = math.max(1, (source.width * scale).round());
  final h = math.max(1, (source.height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium);
  final picture = recorder.endRecording();
  ui.Image? resized;
  try {
    resized = await picture.toImage(w, h);
    final bytes = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) {
      throw const TranslationFailure('无法读取图片像素。');
    }
    final encoded = await compute(_jpeg, (bytes.buffer.asUint8List(), w, h));
    if (encoded.length > 3 * 1024 * 1024) {
      throw const TranslationFailure('压缩后的图片仍超过 3 MB，请框选局部。');
    }
    return PreparedTranslationImage(
        'data:image/jpeg;base64,${base64Encode(encoded)}', w, h);
  } finally {
    resized?.dispose();
    picture.dispose();
  }
}

Uint8List _jpeg((Uint8List, int, int) input) => raster.encodeJpg(
      raster.Image.fromBytes(
          width: input.$2,
          height: input.$3,
          bytes: input.$1.buffer,
          numChannels: 4),
      quality: 85,
    );
