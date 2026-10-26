// SPDX-License-Identifier: GPL-3.0-only
// Offline Android native-model test. Seed the two documented models into the
// debug app's no_backup/bilingual-ocr-v1 directory before running this test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jhentai/src/translation/local_ocr.dart';
import 'package:jhentai/src/translation/translation_client.dart';
import 'package:jhentai/src/translation/translation_models.dart';
import 'package:jhentai/src/translation/translation_settings.dart';
import 'package:jhentai/src/translation/translation_settings_page.dart';
import 'package:jhentai/src/translation/translation_store.dart';
import 'package:jhentai/src/translation/reader_translation_controller.dart';
import 'package:jhentai/src/translation/translation_image_layer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android settings show the experimental mode and model state',
      (tester) async {
    await translationStore.load();
    final before = translationStore.settings;
    try {
      await translationStore.save(
          const TranslationSettings(imageBackend: 'localOcr', visionModel: ''));
      await tester
          .pumpWidget(const MaterialApp(home: TranslationSettingsPage()));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('translation-imageBackend')));
      expect(field.initialValue, 'localOcr');
      expect(find.text('OCR 模型已下载（运行前再次校验）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await translationStore.save(before);
    }
  });
  testWidgets(
      'real Android OCR, crop, cancellation, integrity and text-only reader overlay',
      (tester) async {
    expect((await localOcr.status())['ready'], true,
        reason: 'Seed the pinned model files before this test.');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    void write(String text, Offset position) {
      final painter = TextPainter(
          text: TextSpan(
              text: text,
              style: const TextStyle(
                  fontFamily: 'sans-serif', fontSize: 42, color: Colors.black)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: 700);
      painter.paint(canvas, position);
      painter.dispose();
    }

    write('HELLO WORLD', const Offset(60, 80));
    write('こんにちは', const Offset(60, 330));
    final picture = recorder.endRecording();
    final fixture = await picture.toImage(800, 600);
    picture.dispose();
    final timer = Stopwatch()..start();
    final lines = await localOcr.recognize(fixture, CancelToken());
    debugPrint(
        'Native OCR fixture: ${timer.elapsedMilliseconds} ms, ${lines.map((l) => l.text).toList()}');
    expect(lines.any((l) => l.text.contains('HELLO')), true);
    expect(lines.any((l) => l.text.contains('こんにちは')), true);
    debugPrint((await File('/proc/self/status').readAsLines())
        .where((line) => line.startsWith('VmHWM:') || line.startsWith('VmRSS:'))
        .join('; '));
    for (final line in lines) {
      expect(line.bounds.left, inInclusiveRange(0, 1));
      expect(line.bounds.bottom, inInclusiveRange(0, 1));
      expect(line.confidence, greaterThanOrEqualTo(.55));
    }
    final cropped = await localOcr.recognize(fixture, CancelToken(),
        crop: const Rect.fromLTWH(0, .45, 1, .4));
    expect(cropped.any((l) => l.text.contains('こんにちは')), true);
    expect(cropped.any((l) => l.text.contains('HELLO')), false);
    expect(cropped.first.bounds.top, greaterThan(.45));

    final token = CancelToken();
    final pending = localOcr.recognize(fixture, token);
    final cancellation = Timer(const Duration(milliseconds: 100), token.cancel);
    await expectLater(pending, throwsA(anything));
    expect(token.isCancelled, true);
    cancellation.cancel();
    expect(localOcr.busy, false);
    expect(await localOcr.recognize(fixture, CancelToken()), isNotEmpty);

    // Same-length corruption must fail SHA-256 before inference; always restore.
    final directory = (await localOcr.status())['directory'] as String;
    final model = File('$directory/${localOcrAssets.first.name}');
    final original = await model.readAsBytes();
    try {
      final corrupt = List<int>.of(original)..[0] ^= 1;
      await model.writeAsBytes(corrupt, flush: true);
      await expectLater(
          localOcr.recognize(fixture, CancelToken()),
          throwsA(isA<TranslationFailure>()
              .having((e) => e.message, 'message', contains('模型校验失败'))));
    } finally {
      await model.writeAsBytes(original, flush: true);
    }

    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serve = server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(request.uri.path, '/v1/chat/completions');
      expect(jsonEncode(body), isNot(contains('image_url')));
      expect(body['model'], 'offline-text-fixture');
      requests++;
      final items = jsonDecode(body['messages'][1]['content']) as List;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({
                'translations': [
                  for (final item in items)
                    {'id': item['id'], 'translated': '离线测试译文'}
                ]
              })
            }
          }
        ]
      }));
      await request.response.close();
    });
    final client = TranslationClient();
    final controller = ReaderTranslationController(
        pageCount: 1,
        loadImage: (_, __) async => fixture.clone(),
        settings: () => TranslationSettings(
            apiKey: 'offline-placeholder',
            imageBackend: 'localOcr',
            textModel: 'offline-text-fixture',
            baseUrl: 'http://127.0.0.1:${server.port}/v1'),
        ensureSettings: () async {},
        client: client);
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReaderTranslationScope(
                  controller: controller,
                  child: SizedBox(
                      width: 400,
                      height: 300,
                      child: TranslationImageLayer(
                          imageId: 'ocr-fixture',
                          image: fixture,
                          child: RawImage(image: fixture)))))));
      await controller.translate();
      await tester.pumpAndSettle();
      expect(controller.failed, 0, reason: controller.status);
      expect(controller.current.translated, true, reason: controller.status);
      expect(controller.current.bubbles, isNotEmpty);
      expect(find.text('离线测试译文'), findsWidgets);
      expect(requests, greaterThan(0));
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      client.dispose();
      await serve.cancel();
      await server.close(force: true);
      fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
