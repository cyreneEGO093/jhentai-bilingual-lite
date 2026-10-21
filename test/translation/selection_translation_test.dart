// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/translation/selection_translation.dart';
import 'package:jhentai/src/translation/translation_client.dart';
import 'package:jhentai/src/translation/translation_models.dart';
import 'package:jhentai/src/translation/translation_settings.dart';

class FakeText extends TranslationClient {
  final List<String> sent = [];
  int? failAt;
  Completer<String>? gate;
  CancelToken? lastToken;
  @override
  Future<String> text(String source, TranslationSettings settings,
      {CancelToken? cancelToken}) async {
    lastToken = cancelToken;
    sent.add(source);
    if (sent.length == failAt) {
      throw const TranslationFailure('Synthetic error');
    }
    if (gate != null) {
      return await gate!.future;
    }
    return '译文${sent.length}';
  }
}

const config = TranslationSettings(apiKey: 'offline-placeholder');
void main() {
  test(
      'selection retry retains completed chunks and handles surrogate boundaries',
      () async {
    final api = FakeText()..failAt = 2;
    final c = SelectionTranslationController('${'a' * 1199}😀${'b' * 1300}',
        client: api, loadSettings: () async => config);
    await c.run();
    expect(c.results, ['译文1']);
    expect(c.error, 'Synthetic error');
    expect(api.sent.first.length, 1199);
    expect(api.sent[1].startsWith('😀'), isTrue);
    await c.run();
    expect(api.sent[2], api.sent[1]);
    expect(c.complete, isTrue);
    expect(c.results, ['译文1', '译文3', '译文4']);
    c.dispose();
    api.dispose();
  });
  test(
      'selection limits and cancellation during settings load prevent API calls',
      () async {
    final api = FakeText();
    for (final source in ['', 'a' * 6001]) {
      final c = SelectionTranslationController(source,
          client: api, loadSettings: () async => config);
      await c.run();
      expect(c.error, isNotNull);
      expect(api.sent, isEmpty);
      c.dispose();
    }
    final gate = Completer<TranslationSettings>();
    final c = SelectionTranslationController('Hello',
        client: api, loadSettings: () => gate.future);
    final run = c.run();
    c.stop();
    gate.complete(config);
    await run;
    expect(api.sent, isEmpty);
    c.dispose();
    api.dispose();
  });
  testWidgets(
      'dialog close or Escape cancels immediately, ignores late response and sends no next chunk',
      (tester) async {
    for (final escape in [false, true]) {
      final api = FakeText()..gate = Completer<String>();
      final c = SelectionTranslationController('a' * 2400,
          client: api, loadSettings: () async => config);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => SelectionTranslationDialog(
                              source: c.source, controller: c)),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.sent.length, 1);
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.byKey(const Key('close-selection-translation')));
      }
      expect(api.lastToken!.isCancelled, isTrue);
      api.gate!.complete('Late result');
      await tester.pumpAndSettle();
      expect(api.sent.length, 1);
      expect(find.text('Late result'), findsNothing);
      api.dispose();
    }
  });
  testWidgets('selected text menu preserves existing actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TranslationSelectionArea(extraItems: [
      ContextMenuButtonItem(label: 'Existing action', onPressed: () {})
    ], child: const Text('Hello selected text')))));
    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    final state =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    state.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    final toolbar = area.contextMenuBuilder!(
            tester.element(find.byType(SelectionArea)), state)
        as AdaptiveTextSelectionToolbar;
    expect(toolbar.buttonItems!.map((item) => item.label),
        containsAll(['翻译选中文本', 'Existing action']));
  });
}
