// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'translation_models.dart';

class OcrLine {
  final String text;
  final double confidence;
  final ui.Rect bounds;
  const OcrLine(this.text, this.confidence, this.bounds);
}

class OcrModelAsset {
  final String name, task, hash;
  final int bytes;
  const OcrModelAsset(this.name, this.task, this.bytes, this.hash);
  Uri get url => Uri.parse(
      'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/PP-OCRv6/$task/$name');
}

const localOcrAssets = [
  OcrModelAsset('PP-OCRv6_det_small.onnx', 'det', 9929594,
      '090f04abcd9d9a7498bc4ebf677e4cb9bdce1fe4197ddb7e529f1ef44e1ff94f'),
  OcrModelAsset('PP-OCRv6_rec_small.onnx', 'rec', 21234383,
      '6f327246b50388f3c176ae304bd95767ea6dc0c9ae92153ef8cbe210b3c14884'),
];
void checkOcrCancellation(CancelToken token) {
  if (token.isCancelled) {
    throw token.cancelError!;
  }
}

List<ui.Rect> localOcrTiles(int width, int height, {ui.Rect? crop}) {
  final area = crop ?? const ui.Rect.fromLTWH(0, 0, 1, 1);
  if (width < 1 ||
      height < 1 ||
      [area.left, area.top, area.right, area.bottom].any((v) => !v.isFinite) ||
      area.left < 0 ||
      area.top < 0 ||
      area.right > 1 ||
      area.bottom > 1 ||
      area.width <= 0 ||
      area.height <= 0) {
    throw const TranslationFailure('OCR 框选范围无效。');
  }
  final left = (area.left * width).floor(), top = (area.top * height).floor();
  final right = (area.right * width).ceil(),
      bottom = (area.bottom * height).ceil();
  final result = <ui.Rect>[];
  for (var y = top; y < bottom; y += 1344) {
    for (var x = left; x < right; x += 1344) {
      result.add(ui.Rect.fromLTRB(
          x / width,
          y / height,
          math.min(right, x + 1536) / width,
          math.min(bottom, y + 1536) / height));
      if (result.length > 24) {
        throw const TranslationFailure('图片过大，请分次框选（每次最多 24 个 OCR 分块）。');
      }
      if (x + 1536 >= right) {
        break;
      }
    }
    if (y + 1536 >= bottom) {
      break;
    }
  }
  return result;
}

List<OcrLine> parseOcrLines(dynamic data, ui.Rect tile) {
  if (data is! List || data.length > 100) {
    throw const TranslationFailure('本地 OCR 返回格式无效。');
  }
  return data.map<OcrLine>((item) {
    if (item is! Map ||
        item['text'] is! String ||
        (item['text'] as String).trim().isEmpty ||
        (item['text'] as String).length > 800 ||
        item['confidence'] is! num ||
        !(item['confidence'] as num).isFinite ||
        item['confidence'] < 0 ||
        item['confidence'] > 1 ||
        item['bbox'] is! List ||
        (item['bbox'] as List).length != 4) {
      throw const TranslationFailure('本地 OCR 返回内容无效。');
    }
    final b = item['bbox'] as List;
    if (b.any((n) => n is! num || !n.isFinite || n < 0 || n > 1) ||
        b[2] <= b[0] ||
        b[3] <= b[1]) {
      throw const TranslationFailure('本地 OCR 返回坐标无效。');
    }
    return OcrLine(
        (item['text'] as String).trim(),
        (item['confidence'] as num).toDouble(),
        ui.Rect.fromLTRB(
            tile.left + b[1] * tile.width,
            tile.top + b[0] * tile.height,
            tile.left + b[3] * tile.width,
            tile.top + b[2] * tile.height));
  }).toList();
}

/// Conservative adjacent-line grouping; not semantic panel/bubble detection.
List<OcrLine> combineOcrLines(List<OcrLine> input, int width, int height) {
  final unique = <OcrLine>[];
  String key(String value) => value.replaceAll(RegExp(r'\s'), '');
  for (final line in [...input]
    ..sort((a, b) => b.text.length.compareTo(a.text.length))) {
    final duplicate = unique.any((other) {
      final intersection = line.bounds.intersect(other.bounds);
      final overlap = intersection.width > 0 && intersection.height > 0
          ? intersection.width * intersection.height
          : 0.0;
      final minimum = math.min(line.bounds.width * line.bounds.height,
          other.bounds.width * other.bounds.height);
      final a = key(line.text), b = key(other.text);
      return overlap / minimum > .65 && (a.contains(b) || b.contains(a));
    });
    if (!duplicate) {
      unique.add(line);
    }
  }
  ui.Rect px(OcrLine l) => ui.Rect.fromLTRB(l.bounds.left * width,
      l.bounds.top * height, l.bounds.right * width, l.bounds.bottom * height);
  bool vertical(OcrLine l) => px(l).height > px(l).width * 1.5;
  final groups = <List<OcrLine>>[];
  for (final line in unique
    ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top))) {
    List<OcrLine>? target;
    for (final group in groups) {
      if (group.fold<int>(0, (n, l) => n + l.text.length) + line.text.length >
          800) {
        continue;
      }
      if (group.any((other) {
        if (vertical(other) != vertical(line)) {
          return false;
        }
        final a = px(other), b = px(line);
        if (vertical(line)) {
          final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
          final gap = math.max(a.left, b.left) - math.min(a.right, b.right);
          return overlap / math.min(a.height, b.height) > .75 &&
              gap >= -2 &&
              gap < math.min(a.width, b.width) * .65;
        }
        final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
        final gap = math.max(a.top, b.top) - math.min(a.bottom, b.bottom);
        return overlap / math.min(a.width, b.width) > .75 &&
            gap >= -2 &&
            gap < math.min(a.height, b.height) * .65;
      })) {
        target = group;
        break;
      }
    }
    if (target == null) {
      groups.add([line]);
    } else {
      target.add(line);
    }
  }
  final merged = groups.map((g) {
    final isVertical = vertical(g.first);
    g.sort((a, b) => isVertical
        ? b.bounds.left.compareTo(a.bounds.left)
        : a.bounds.top.compareTo(b.bounds.top));
    return OcrLine(
        g.map((l) => l.text).join('\n'),
        g.map((l) => l.confidence).reduce(math.min),
        g.map((l) => l.bounds).reduce((a, b) => a.expandToInclude(b)));
  }).toList()
    ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
  if (merged.length > 60) {
    throw const TranslationFailure('识别文字区域超过 60 个，请分次框选。');
  }
  return merged;
}

class LocalOcrService {
  final MethodChannel channel;
  bool _busy = false;
  int _sequence = 0;
  LocalOcrService(
      {this.channel = const MethodChannel('bilingual_lite/local_ocr')});
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get busy => _busy;
  Future<Map<Object?, Object?>> status() async {
    if (!supported) {
      return {'ready': false};
    }
    return await channel.invokeMapMethod<Object?, Object?>('status') ??
        {'ready': false};
  }

  Future<void> install(CancelToken token, void Function(double) progress,
      {Dio? transport}) async {
    if (!supported || _busy) {
      throw const TranslationFailure('当前平台不支持或 OCR 正在使用中。');
    }
    _busy = true;
    final dio = transport ??
        Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 60)));
    if (transport == null) {
      dio.httpClientAdapter =
          IOHttpClientAdapter(createHttpClient: HttpClient.new);
    }
    try {
      final directory = Directory((await status())['directory'] as String);
      await directory.create(recursive: true);
      var completed = 0;
      final total = localOcrAssets.fold<int>(0, (n, a) => n + a.bytes);
      for (final asset in localOcrAssets) {
        checkOcrCancellation(token);
        final file = File('${directory.path}/${asset.name}');
        if (await file.exists() &&
            await file.length() == asset.bytes &&
            (await sha256.bind(file.openRead()).first).toString() ==
                asset.hash) {
          completed += asset.bytes;
          progress(completed / total);
          continue;
        }
        final part = File('${file.path}.part');
        try {
          final response = await dio.get<ResponseBody>(asset.url.toString(),
              options: Options(
                  responseType: ResponseType.stream,
                  followRedirects: true,
                  maxRedirects: 5),
              cancelToken: token);
          final body = response.data;
          if (body == null) {
            throw const TranslationFailure('模型下载没有返回内容。');
          }
          var received = 0;
          final sink = part.openWrite();
          try {
            await for (final bytes in body.stream) {
              checkOcrCancellation(token);
              received += bytes.length;
              if (received > asset.bytes) {
                throw const TranslationFailure('模型文件大小异常，已停止下载。');
              }
              sink.add(bytes);
              progress((completed + received) / total);
            }
          } finally {
            await sink.close();
          }
          checkOcrCancellation(token);
          if (received != asset.bytes ||
              (await sha256.bind(part.openRead()).first).toString() !=
                  asset.hash) {
            throw const TranslationFailure('模型校验失败，请重试下载。');
          }
          checkOcrCancellation(token);
          if (await file.exists()) {
            await file.delete();
          }
          await part.rename(file.path);
          completed += asset.bytes;
        } finally {
          if (await part.exists()) {
            await part.delete();
          }
        }
      }
    } finally {
      if (transport == null) {
        dio.close(force: true);
      }
      _busy = false;
    }
  }

  Future<void> remove() async {
    if (!supported || _busy) {
      throw const TranslationFailure('请先停止 OCR 或模型下载。');
    }
    _busy = true;
    try {
      final path = (await status())['directory'] as String;
      // Only fixed owned files, never recursively delete app/user directories.
      for (final asset in localOcrAssets) {
        for (final suffix in ['', '.part']) {
          final file = File('$path/${asset.name}$suffix');
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<List<OcrLine>> recognize(ui.Image image, CancelToken token,
      {ui.Rect? crop, void Function(String)? progress}) async {
    if (!supported) {
      throw const TranslationFailure('本地 OCR 实验模式目前仅支持 Android。');
    }
    if (_busy) {
      throw const TranslationFailure('请等待模型下载或上一项 OCR 完成。');
    }
    _busy = true;
    String? active;
    var finished = false;
    unawaited(token.whenCancel.then((_) async {
      if (!finished && active != null) {
        try {
          await channel.invokeMethod<void>('cancel', {'id': active});
        } catch (_) {}
      }
    }));
    try {
      checkOcrCancellation(token);
      if ((await status())['ready'] != true) {
        throw const TranslationFailure('请先在翻译设置中下载本地 OCR 模型（约 30 MB）。');
      }
      final tiles = localOcrTiles(image.width, image.height, crop: crop);
      final lines = <OcrLine>[];
      for (var i = 0; i < tiles.length; i++) {
        checkOcrCancellation(token);
        progress?.call('手机本地识别 ${i + 1}/${tiles.length}（图片不上传）');
        final t = tiles[i];
        final source = ui.Rect.fromLTRB(
            (t.left * image.width).roundToDouble(),
            (t.top * image.height).roundToDouble(),
            (t.right * image.width).roundToDouble(),
            (t.bottom * image.height).roundToDouble());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
        canvas.drawImageRect(image, source,
            ui.Rect.fromLTWH(0, 0, source.width, source.height), ui.Paint());
        final picture = recorder.endRecording();
        ui.Image? part;
        try {
          part = await picture.toImage(
              source.width.round(), source.height.round());
          final data = await part.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) {
            throw const TranslationFailure('无法读取 OCR 图片。');
          }
          checkOcrCancellation(token);
          active = 'ocr-${++_sequence}';
          final result = await channel.invokeMethod<Object?>('recognize', {
            'id': active,
            'bytes':
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
          });
          active = null;
          checkOcrCancellation(token);
          lines.addAll(parseOcrLines(result, t));
        } on PlatformException catch (error) {
          throw TranslationFailure(error.message ?? '本地 OCR 失败。');
        } finally {
          part?.dispose();
          picture.dispose();
        }
      }
      return combineOcrLines(lines, image.width, image.height);
    } finally {
      finished = true;
      _busy = false;
    }
  }
}

final localOcr = LocalOcrService();
