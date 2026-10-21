// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/translation/reader_translation_controller.dart';
import 'package:jhentai/src/translation/translation_client.dart';
import 'package:jhentai/src/translation/translation_settings.dart';
import 'package:jhentai/src/translation/translation_models.dart';

class FakeVision extends TranslationClient {
  int calls = 0;
  int? failAt;
  int? status;
  VoidCallback? onCall;
  @override
  Future<List<TranslationBubble>> image(
      String dataUrl, TranslationSettings settings,
      {Rect? crop, CancelToken? cancelToken}) async {
    expect(dataUrl, startsWith('data:image/jpeg;base64,'));
    calls++;
    onCall?.call();
    if (calls == failAt) {
      throw TranslationFailure('Synthetic failure', status: status);
    }
    return [
      TranslationBubble(
          'Hello', '你好', crop ?? const Rect.fromLTWH(.1, .1, .3, .2))
    ];
  }
}

void main() {
  testWidgets(
      'discard removes crops and edited bounds, ignores active result, skips queued page and preserves other pages',
      (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final image = await picture.toImage(30, 40);
      picture.dispose();
      final api = FakeVision();
      final c = ReaderTranslationController(
          pageCount: 4,
          loadImage: (_, __) async => image.clone(),
          client: api,
          settings: () =>
              const TranslationSettings(apiKey: 'offline-placeholder'),
          ensureSettings: () async {});
      await c.translate();
      await c.translate(crop: const Rect.fromLTWH(.2, .2, .1, .1));
      c.changeBounds(0, 0, const Rect.fromLTWH(.5, .5, .2, .2));
      c.selectedBubble = 0;
      c.editing = true;
      c.discardCurrent();
      c.resetBounds();
      expect(c.current.bubbles, isEmpty);
      expect(c.current.original, isEmpty);
      expect(c.current.translated, isFalse);
      expect(c.selectedBubble, isNull);
      expect(c.editing, isFalse);
      final before = api.calls;
      api.onCall = () {
        if (api.calls == before + 2) {
          c.activate(1);
          c.discardCurrent();
          c.activate(2);
          c.discardCurrent();
        }
      };
      await c.translate(all: true);
      expect(api.calls, before + 3);
      expect(c.page(0).translated, isTrue);
      expect(c.page(1).bubbles, isEmpty);
      expect(c.page(2).bubbles, isEmpty);
      expect(c.page(3).translated, isTrue);
      expect(c.completed, 2);
      expect(c.failed, 0);
      expect(c.skipped, 2);
      api.onCall = null;
      await c.translate(all: true);
      expect(api.calls, before + 5);
      expect(c.completed, 4);
      c.dispose();
      api.dispose();
      image.dispose();
    });
  });

  test('discard during initialization skips only invalidated page', () async {
    final gate = Completer<void>();
    final c = ReaderTranslationController(
        pageCount: 1,
        loadImage: (_, __) async => throw StateError('Must not load'),
        settings: () =>
            const TranslationSettings(apiKey: 'offline-placeholder'),
        ensureSettings: () => gate.future);
    final run = c.translate(all: true);
    c.discardCurrent();
    gate.complete();
    await run;
    expect(c.skipped, 1);
    expect(c.current.translated, isFalse);
    c.dispose();
  });
  testWidgets(
      'whole work loads unmounted pages, isolates failure, retries only missing',
      (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(30, 40);
      picture.dispose();
      final loaded = <int>[];
      final client = FakeVision()..failAt = 2;
      final c = ReaderTranslationController(
          pageCount: 3,
          loadImage: (i, token) async {
            loaded.add(i);
            return image.clone();
          },
          client: client,
          settings: () =>
              const TranslationSettings(apiKey: 'offline-placeholder'),
          ensureSettings: () async {});
      await c.translate(all: true);
      expect(loaded, [0, 1, 2]);
      expect(c.completed, 2);
      expect(c.failed, 1);
      expect(c.page(2).translated, isTrue);
      await c.translate(all: true);
      expect(loaded, [0, 1, 2, 1]);
      expect(c.completed, 3);
      expect(c.failed, 0);
      expect(client.calls, 4);
      c.dispose();
      image.dispose();
    });
  });

  testWidgets(
      'cancel preserves completed pages; authentication failure stops batch',
      (tester) async {
    await tester.runAsync(() async {
      final picture = ui.PictureRecorder();
      Canvas(picture);
      final drawing = picture.endRecording();
      final image = await drawing.toImage(30, 40);
      drawing.dispose();
      final client = FakeVision();
      final c = ReaderTranslationController(
          pageCount: 4,
          loadImage: (_, __) async => image.clone(),
          client: client,
          settings: () =>
              const TranslationSettings(apiKey: 'offline-placeholder'),
          ensureSettings: () async {});
      client.onCall = () {
        if (client.calls == 2) {
          c.cancel();
        }
      };
      await c.translate(all: true);
      expect(client.calls, 2);
      expect(c.page(0).translated, isTrue);
      expect(c.page(1).translated, isFalse);
      expect(c.busy, isFalse);
      client.onCall = null;
      client.failAt = 3;
      client.status = 401;
      await c.translate(all: true);
      expect(client.calls, 3);
      expect(c.status, 'Synthetic failure');
      c.dispose();
      image.dispose();
    });
  });

  test('cancel during settings initialization cannot send requests', () async {
    final gate = Completer<void>();
    final client = FakeVision();
    final c = ReaderTranslationController(
        pageCount: 1,
        loadImage: (_, __) async => throw StateError('Must not load'),
        client: client,
        settings: () =>
            const TranslationSettings(apiKey: 'offline-placeholder'),
        ensureSettings: () => gate.future);
    final run = c.translate(all: true);
    c.cancel();
    gate.complete();
    await run;
    expect(client.calls, 0);
    expect(c.busy, isFalse);
    c.dispose();
  });

  test('editing clamps at image edges without shifting the resize origin', () {
    const edge = Rect.fromLTRB(.999, .999, 1, 1);
    expect(
        editTranslationBounds(edge, const Offset(.1, .1), resize: true), edge);
    const r = Rect.fromLTWH(.7, .6, .2, .3);
    expect(editTranslationBounds(r, const Offset(1, 1), resize: true),
        const Rect.fromLTRB(.7, .6, 1, 1));
    expect(editTranslationBounds(r, const Offset(-1, -1), resize: false),
        rectMoreOrLessEquals(const Rect.fromLTWH(0, 0, .2, .3)));
  });
}
