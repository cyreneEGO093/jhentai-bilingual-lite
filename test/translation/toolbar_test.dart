// SPDX-License-Identifier: GPL-3.0-only
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:jhentai/src/translation/translation_image_layer.dart';
import 'package:jhentai/src/translation/reader_translation_controller.dart';
import 'package:jhentai/src/translation/reader_translation_toolbar.dart';
import 'package:jhentai/src/translation/translation_settings.dart';
import 'package:jhentai/src/translation/translation_models.dart';
import 'package:jhentai/src/translation/translation_widgets.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('shared reader tools and continuous editing on $platform',
        (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 450);
      picture.dispose();
      final controller = ReaderTranslationController(
          pageCount: 2,
          loadImage: (_, __) async => image.clone(),
          settings: () => const TranslationSettings(),
          ensureSettings: () async {});
      controller.page(0).bubbles = [
        const TranslationBubble('Hello', '你好', Rect.fromLTWH(.3, .4, .25, .2))
      ];
      controller.page(0).original = List.of(controller.page(0).bubbles);
      final zoom = PhotoViewController();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
              body: ReaderTranslationScope(
                  controller: controller,
                  child: Stack(children: [
                    Positioned.fill(
                        child: PhotoView.customChild(
                            controller: zoom,
                            initialScale: 1.0,
                            minScale: 1.0,
                            maxScale: 3.0,
                            child: Center(
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  for (var i = 0; i < 2; i++)
                                    TranslationImageLayer(
                                        imageId: 'test-$i',
                                        pageIndex: i,
                                        image: image,
                                        child: const SizedBox(
                                            width: 300, height: 450)),
                                ])))),
                    ReaderTranslationToolbar(controller: controller),
                  ])))));
      final handle = find.byKey(const Key('image-translation-tools'));
      expect(handle, findsOneWidget);
      final toolbarBeforeZoom = tester.getRect(handle);
      zoom.scale = 1.3;
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(handle), toolbarBeforeZoom);
      await tester.tap(handle);
      await tester.pump();
      final dragBar = find.byKey(const Key('translation-toolbar-drag-bar'));
      expect(dragBar, findsOneWidget);
      final headerBefore = tester.getRect(dragBar);
      // The title area, not the close button, moves the expanded window.
      await tester.drag(dragBar, const Offset(450, 260));
      await tester.pump();
      expect(
          tester.getRect(handle).top, greaterThan(toolbarBeforeZoom.top + 200));
      expect(tester.getRect(dragBar).top, greaterThan(headerBefore.top + 200));
      final moveCorner = find.byKey(const Key('translation-move-corner-0-0'));
      final resizeCorner =
          find.byKey(const Key('translation-resize-corner-0-0'));
      expect(moveCorner, findsNothing);
      expect(resizeCorner, findsNothing);
      await tester.ensureVisible(find.text('调整'));
      await tester.tap(find.text('调整'));
      await tester.pump();
      expect(moveCorner, findsOneWidget);
      expect(resizeCorner, findsOneWidget);
      final bubble = find.byKey(const Key('translation-bubble-0'));
      final before = tester.getRect(bubble);
      await tester.drag(bubble, const Offset(26, 39));
      await tester.pump();
      var moved = tester.getRect(bubble);
      expect(moved.left, closeTo(before.left + 26, 1));
      expect(moved.top, closeTo(before.top + 39, 1));
      await tester.drag(moveCorner, const Offset(13, -13));
      await tester.pump();
      expect(tester.getRect(bubble).left, closeTo(moved.left + 13, 1));
      expect(tester.getRect(bubble).top, closeTo(moved.top - 13, 1));
      moved = tester.getRect(bubble);
      await tester.drag(resizeCorner, const Offset(13, 13));
      await tester.pump();
      expect(tester.getRect(bubble).width, closeTo(moved.width + 13, 1));
      expect(tester.getRect(bubble).height, closeTo(moved.height + 13, 1));
      moved = tester.getRect(bubble);
      final resize = find.byKey(const Key('translation-resize-handle'));
      await tester.ensureVisible(resize);
      await tester.drag(resize, const Offset(26, 26));
      await tester.pump();
      expect(tester.getRect(bubble).width, closeTo(moved.width + 26, 1));
      expect(tester.getRect(bubble).height, closeTo(moved.height + 26, 1));
      await tester.ensureVisible(find.text('完成调整'));
      await tester.tap(find.text('完成调整'));
      await tester.pump();
      expect(moveCorner, findsNothing);
      expect(resizeCorner, findsNothing);
      // Tapping the separate close button only collapses the panel.
      await tester.tap(handle);
      await tester.pump();
      expect(dragBar, findsNothing);
      expect(handle, findsOneWidget);
      await tester.tap(handle);
      await tester.pump();
      expect(dragBar, findsOneWidget);
      await tester.ensureVisible(find.text('调整'));
      await tester.tap(find.text('调整'));
      await tester.pump();
      await tester.ensureVisible(find.text('重置框位'));
      await tester.tap(find.text('重置框位'));
      await tester.pump();
      expect(controller.current.bubbles.first.bounds,
          controller.current.original.first.bounds);
      await tester.tap(bubble);
      await tester.pump();
      await tester.ensureVisible(find.text('删除选中框'));
      await tester.tap(find.text('删除选中框'));
      await tester.pump();
      expect(controller.current.bubbles, isEmpty);
      await tester.ensureVisible(find.text('重置框位'));
      await tester.tap(find.text('重置框位'));
      await tester.pump();
      expect(controller.current.bubbles.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      zoom.dispose();
      image.dispose();
    });
  }

  testWidgets(
      'mobile edit icons remain separate and reachable on tiny edge bubbles',
      (tester) async {
    final picture = ui.PictureRecorder();
    Canvas(picture).drawColor(Colors.white, BlendMode.src);
    final recorded = picture.endRecording();
    final image = await recorded.toImage(300, 400);
    recorded.dispose();
    final controller = ReaderTranslationController(
        pageCount: 1,
        loadImage: (_, __) async => image.clone(),
        settings: () => const TranslationSettings(),
        ensureSettings: () async {});
    controller.page(0).bubbles = [
      const TranslationBubble('A', '译', Rect.fromLTWH(.98, .98, .02, .02))
    ];
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
            body: Center(
                child: ReaderTranslationScope(
                    controller: controller,
                    child: TranslationImageLayer(
                        imageId: 'edge',
                        image: image,
                        child: const SizedBox(width: 300, height: 400)))))));
    final move = find.byKey(const Key('translation-move-corner-0-0'));
    final resize = find.byKey(const Key('translation-resize-corner-0-0'));
    expect(move, findsNothing);
    controller.toggleEditing();
    await tester.pump();
    final imageRect = tester.getRect(find.byType(TranslationImageLayer));
    final moveRect = tester.getRect(move), resizeRect = tester.getRect(resize);
    expect(moveRect.overlaps(resizeRect), isFalse);
    for (final r in [moveRect, resizeRect]) {
      expect(r.left, greaterThanOrEqualTo(imageRect.left));
      expect(r.top, greaterThanOrEqualTo(imageRect.top));
      expect(r.right, lessThanOrEqualTo(imageRect.right));
      expect(r.bottom, lessThanOrEqualTo(imageRect.bottom));
    }
    await tester.drag(move, const Offset(-30, -30));
    await tester.pump();
    expect(controller.current.bubbles.first.bounds.left, lessThan(.95));
    controller.toggleVisible();
    await tester.pump();
    expect(move, findsNothing);
    expect(resize, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    image.dispose();
  });

  testWidgets('expanded mobile toolbar has a wide independent drag header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ReaderTranslationController(
        pageCount: 1,
        loadImage: (_, __) async => throw StateError('No network in this test'),
        settings: () => const TranslationSettings(toolScale: 1.5),
        ensureSettings: () async {});
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
            body: Stack(children: [
          ReaderTranslationToolbar(controller: controller),
        ]))));
    final close = find.byKey(const Key('image-translation-tools'));
    await tester.tap(close);
    await tester.pump();
    final header = find.byKey(const Key('translation-toolbar-drag-bar'));
    expect(tester.getSize(header).width, greaterThan(200));
    expect(tester.getSize(header).height, tester.getSize(close).height);
    await tester.tap(header);
    await tester.pump();
    expect(header, findsOneWidget);
    final before = tester.getRect(header);
    // Even the blank title-bar padding is draggable, not just its icon/text.
    await tester.dragFrom(
        before.topLeft + const Offset(2, 10), const Offset(0, 120));
    await tester.pump();
    expect(tester.getRect(header).top, closeTo(before.top + 120, 1));
    await tester.ensureVisible(find.text('原图'));
    await tester.tap(find.text('原图'));
    await tester.pump();
    expect(controller.current.visible, isFalse);
    await tester.tap(close);
    await tester.pump();
    expect(header, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('bounded comment reserves a visible translation action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 280,
                    height: 190,
                    child: Card(
                        child: Column(children: [
                      const Text('Comment author'),
                      Expanded(
                          child: TranslatableText(
                              boundedPreview: true,
                              source: 'Synthetic comment.',
                              child: Text(
                                  List.filled(30, 'A long synthetic comment.')
                                      .join(' '),
                                  style: const TextStyle(fontSize: 24)))),
                      const Text('Votes'),
                    ])))))));
    final card = tester.getRect(find.byType(Card));
    final button = tester.getRect(find.byKey(const Key('translate-text')));
    expect(card.contains(button.topLeft), isTrue);
    expect(card.contains(button.bottomRight), isTrue);
    expect(button.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Votes')).top));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('translate-text'))), button);
    expect(tester.takeException(), isNull);
  });
}
