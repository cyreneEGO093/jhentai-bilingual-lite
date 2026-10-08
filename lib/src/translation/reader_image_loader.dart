// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'translation_models.dart';

/// Use the reader's image providers (and their disk cache), then release pixels
/// after encoding. No screenshots or new persistent translation image cache.
Future<ui.Image> loadTranslationFrame(
    ImageProvider provider, CancelToken token) async {
  if (token.isCancelled) {
    throw token.cancelError!;
  }
  final result = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((info, _) {
    if (!result.isCompleted) {
      result.complete(info.image.clone());
    }
    info.dispose();
  }, onError: (Object error, StackTrace? stack) {
    if (!result.isCompleted) {
      result.completeError(const TranslationFailure('图片加载失败，请稍后重试。'));
    }
  });
  final timer = Timer(const Duration(seconds: 90), () {
    if (!result.isCompleted) {
      result.completeError(const TranslationFailure('图片加载超时，请稍后重试。'));
    }
  });
  token.whenCancel.then((error) {
    if (!result.isCompleted) {
      result.completeError(error);
    }
  });
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    timer.cancel();
    stream.removeListener(listener);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.evict(key, includeLive: false);
  }
}
