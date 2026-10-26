// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/translation/local_ocr.dart';
import 'package:jhentai/src/translation/translation_client.dart';
import 'package:jhentai/src/translation/translation_models.dart';
import 'package:jhentai/src/translation/translation_settings.dart';

class OcrTransport implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  OcrTransport(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancel) =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody reply(List<Map<String, dynamic>> translations) =>
    ResponseBody.fromString(
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'content': jsonEncode({'translations': translations})
              }
            }
          ]
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old settings retain vision; experimental mode persists', () {
    expect(TranslationSettings.fromJson({}).imageBackend, 'vision');
    expect(TranslationSettings.fromJson({'imageBackend': 'other'}).imageBackend,
        'vision');
    expect(
        TranslationSettings.fromJson(
                const TranslationSettings(imageBackend: 'localOcr').toJson())
            .imageBackend,
        'localOcr');
  });
  test('tiles preserve original resolution, cover edges and overlap', () {
    final tiles = localOcrTiles(1800, 5000);
    expect(tiles.length, 8);
    expect(tiles.first.topLeft, ui.Offset.zero);
    expect(tiles.last.bottomRight, const ui.Offset(1, 1));
    for (final t in tiles) {
      expect(t.width * 1800, lessThanOrEqualTo(1536.000001));
      expect(t.height * 5000, lessThanOrEqualTo(1536.000001));
    }
    expect(tiles[0].intersect(tiles[1]).width, greaterThan(0));
    expect(
        () => localOcrTiles(1000, 100000), throwsA(isA<TranslationFailure>()));
  });
  test('local OCR requires only a text model; vision still needs its model',
      () {
    expect(
        () =>
            const TranslationSettings(imageBackend: 'localOcr', visionModel: '')
                .validate(),
        returnsNormally);
    expect(() => const TranslationSettings(visionModel: '').validate(),
        throwsFormatException);
  });
  test('crop tiles and native normalized coordinates map to original image',
      () {
    final tiles =
        localOcrTiles(1000, 2000, crop: const ui.Rect.fromLTWH(.2, .4, .5, .3));
    final lines = parseOcrLines([
      {
        'text': 'Hello',
        'confidence': .9,
        'bbox': [.1, .1, .8, .8]
      }
    ], tiles.single);
    expect(lines.single.bounds.left, closeTo(.25, .000001));
    expect(lines.single.bounds.top, closeTo(.43, .000001));
    expect(lines.single.bounds.right, closeTo(.6, .000001));
    expect(lines.single.bounds.bottom, closeTo(.64, .000001));
  });
  test('reject malformed OCR geometry and nonfinite scores', () {
    for (final bad in [
      {
        'text': 'x',
        'confidence': .9,
        'bbox': [0, 0, 1, 2]
      },
      {
        'text': 'x',
        'confidence': double.nan,
        'bbox': [0, 0, 1, 1]
      },
      {
        'text': 'x',
        'confidence': .9,
        'bbox': [.5, 0, .2, 1]
      },
    ]) {
      expect(() => parseOcrLines([bad], const ui.Rect.fromLTWH(0, 0, 1, 1)),
          throwsA(isA<TranslationFailure>()));
    }
  });
  test('overlap duplicates removed, separated repeated dialogue retained', () {
    final lines = combineOcrLines([
      const OcrLine('HELLO', .9, ui.Rect.fromLTWH(.1, .1, .2, .05)),
      const OcrLine('HELLO', .8, ui.Rect.fromLTWH(.1, .1, .2, .05)),
      const OcrLine('HELLO', .9, ui.Rect.fromLTWH(.7, .8, .2, .05)),
    ], 1000, 1000);
    expect(lines.length, 2);
  });
  test('adjacent vertical columns read right to left', () {
    final lines = combineOcrLines([
      const OcrLine('左列', .9, ui.Rect.fromLTWH(.1, .1, .03, .3)),
      const OcrLine('右列', .9, ui.Rect.fromLTWH(.14, .1, .03, .3)),
    ], 1000, 1000);
    expect(lines.single.text, '右列\n左列');
  });
  test('OCR sends bounded text-only batches and restores IDs/geometry',
      () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = OcrTransport((options) async {
        requests++;
        final body = options.data as Map;
        expect(body['model'], 'text-model');
        expect(body['max_tokens'], 1500);
        expect(jsonEncode(body), isNot(contains('image_url')));
        final messages = body['messages'] as List;
        expect(messages[1]['content'], isA<String>());
        expect(messages[0]['content'], contains('固定名'));
        final items = jsonDecode(messages[1]['content']) as List;
        expect(items.length, lessThanOrEqualTo(4));
        return reply(items.reversed
            .map((item) => {'id': item['id'], 'translated': '测试译文'})
            .toList());
      });
    final client = TranslationClient(dio: dio);
    final lines = List.generate(5,
        (i) => OcrLine('HELLO $i', .9, ui.Rect.fromLTWH(.1, .1 * i, .2, .05)));
    final result = await client.ocrText(
        lines,
        const TranslationSettings(
            apiKey: 'placeholder',
            textModel: 'text-model',
            glossary: 'name = 固定名'));
    expect(requests, 2);
    expect(result.map((b) => b.bounds), lines.map((b) => b.bounds));
    client.dispose();
  });
  test('cancelled OCR translation never sends request', () async {
    var sent = false;
    final client = TranslationClient(
        dio: Dio()
          ..httpClientAdapter = OcrTransport((_) async {
            sent = true;
            return reply([]);
          }));
    final token = CancelToken()..cancel();
    await expectLater(
        client.ocrText(
            [const OcrLine('HELLO', .9, ui.Rect.fromLTWH(0, 0, .2, .2))],
            const TranslationSettings(apiKey: 'placeholder'),
            cancelToken: token),
        throwsA(isA<DioException>()));
    expect(sent, false);
    client.dispose();
  });
  test('missing/duplicate model IDs fail without image fallback', () async {
    final client = TranslationClient(
        dio: Dio()
          ..httpClientAdapter = OcrTransport((_) async => reply([
                {'id': 0, 'translated': '你好'},
                {'id': 0, 'translated': '你好'}
              ])));
    await expectLater(
        client.ocrText([
          const OcrLine('HELLO', .9, ui.Rect.fromLTWH(0, 0, .2, .2)),
          const OcrLine('WORLD', .9, ui.Rect.fromLTWH(0, .4, .2, .2))
        ], const TranslationSettings(apiKey: 'placeholder')),
        throwsA(isA<TranslationFailure>()));
    client.dispose();
  });
  test('model download rejects truncated data and cleans only its partial file',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final directory = await Directory.systemTemp.createTemp('local-ocr-test-');
    final keep = File('${directory.path}/unrelated.txt')
      ..writeAsStringSync('keep');
    const channel = MethodChannel('ocr-test-channel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel,
            (call) async => {'directory': directory.path, 'ready': false});
    final dio = Dio()
      ..httpClientAdapter = OcrTransport((request) async {
        expect(request.headers['authorization'], isNull);
        expect(request.uri.scheme, 'https');
        return ResponseBody.fromString('bad model', 200);
      });
    try {
      await expectLater(
          LocalOcrService(channel: channel)
              .install(CancelToken(), (_) {}, transport: dio),
          throwsA(isA<TranslationFailure>()));
      expect(await directory.list().length, 1);
      expect(await keep.readAsString(), 'keep');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      dio.close();
      await directory.delete(recursive: true);
    }
  });
}
