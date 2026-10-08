// SPDX-License-Identifier: GPL-3.0-only
// Offline native test: synthetic fixture and a loopback OpenAI-compatible API.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:jhentai/src/model/read_page_info.dart';
import 'package:jhentai/src/pages/read/read_page_logic.dart';
import 'package:jhentai/src/service/gallery_download/gallery_download_service.dart';
import 'package:jhentai/src/main.dart' as app;
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/widget/eh_image.dart';
import 'package:jhentai/src/translation/translation_image_layer.dart';
import 'package:jhentai/src/translation/reader_translation_controller.dart';
import 'package:jhentai/src/translation/reader_translation_toolbar.dart';
import 'package:jhentai/src/translation/reader_image_loader.dart';
import 'package:extended_image/extended_image.dart';
import 'package:jhentai/src/translation/translation_store.dart';
import 'package:jhentai/src/translation/translation_settings_page.dart';
import 'package:jhentai/src/translation/translation_widgets.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native BYOK, cached reader image, whole/crop overlay, editing and text',
      (tester) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xffdceee8), BlendMode.src);
    canvas.drawRect(
        const Rect.fromLTWH(150, 200, 600, 350), Paint()..color = Colors.white);
    canvas.drawRect(const Rect.fromLTWH(900, 1600, 550, 350),
        Paint()..color = Colors.white);
    final painter = TextPainter(
        text: const TextSpan(
            text: 'HELLO!\nA synthetic translation test.',
            style: TextStyle(color: Colors.black, fontSize: 45)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 580);
    painter.paint(canvas, const Offset(160, 240));
    final picture = recorder.endRecording();
    final fixture = await picture.toImage(1600, 2400);
    final png = (await fixture.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    fixture.dispose();
    picture.dispose();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    var imageDownloads = 0;
    server.listen((request) async {
      try {
        if (request.uri.path == '/fixture.png') {
          imageDownloads++;
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(png);
        } else {
          request.response.headers.contentType = ContentType.json;
          expectSync(request.headers.value('authorization'),
              'Bearer integration-placeholder');
          expectSync(request.headers.value('cookie'), isNull);
          if (request.uri.path == '/v1/models') {
            request.response.write(jsonEncode({
              'data': [
                {'id': 'mock-vision'}
              ]
            }));
          } else {
            final body = jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
            requests.add(body);
            expectSync(body['max_tokens'], 1500);
            expectSync(body['temperature'], .1);
            final content = body['messages'][1]['content'];
            dynamic result;
            if (content is String) {
              final items = jsonDecode(content) as List;
              result = {
                'translations': [
                  for (final item in items)
                    {'id': item['id'], 'translated': '离线文本翻译测试。'}
                ]
              };
            } else if ((body['messages'][0]['content'] as String)
                .contains('cropped image')) {
              result = {'original': 'Hello', 'translated': '框选测试成功'};
            } else {
              result = {
                'bubbles': [
                  {
                    'original': 'HELLO!',
                    'translated': '整图测试成功',
                    'bbox': [100, 100, 260, 460]
                  }
                ]
              };
            }
            request.response.write(jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': jsonEncode(result)}
                }
              ]
            }));
          }
        }
      } finally {
        await request.response.close();
      }
    });
    await translationStore.load();
    final oldSettings = translationStore.settings;
    try {
      await tester
          .pumpWidget(const MaterialApp(home: TranslationSettingsPage()));
      await waitFor(tester, find.byKey(const Key('translation-baseUrl')));
      await tester.enterText(find.byKey(const Key('translation-baseUrl')),
          'http://127.0.0.1:${server.port}/v1');
      await tester.enterText(find.byKey(const Key('translation-apiKey')),
          'integration-placeholder');
      await tester.enterText(
          find.byKey(const Key('translation-textModel')), 'mock-text');
      await tester
          .ensureVisible(find.byKey(const Key('translation-visionModel')));
      await tester.enterText(
          find.byKey(const Key('translation-visionModel')), 'mock-vision');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('保存设置'), 500,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text('保存设置'));
      await waitFor(tester, find.text('已保存。只在点击翻译后发送内容。'));
      const secure = FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true));
      expect(await secure.read(key: 'bilingual-lite-api-key'),
          'integration-placeholder');
      final prefs = File(
          '${(await getApplicationSupportDirectory()).path}/bilingual-lite-settings.json');
      expect(await prefs.readAsString(),
          isNot(contains('integration-placeholder')));
      await tester.tap(find.text('查询模型验证连接'));
      await waitFor(tester, find.textContaining('连接成功'));

      final screenshotKey = GlobalKey();
      final zoom = PhotoViewController();
      final session = ReaderTranslationController(
          pageCount: 3,
          loadImage: (index, token) => loadTranslationFrame(
              ExtendedNetworkImageProvider(
                  'http://127.0.0.1:${server.port}/fixture.png?page=$index',
                  cache: true),
              token));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SafeArea(
                  child: RepaintBoundary(
                      key: screenshotKey,
                      child: ReaderTranslationScope(
                          controller: session,
                          child: Stack(children: [
                            Column(children: [
                              const TranslatableText(
                                  source: 'A synthetic title.',
                                  child: Text('A synthetic title.')),
                              Expanded(
                                  child: PhotoView.customChild(
                                      controller: zoom,
                                      initialScale: 1.0,
                                      minScale: 1.0,
                                      maxScale: 3.0,
                                      child: Center(
                                          child: EHImage(
                                              galleryImage: GalleryImage(
                                                  url:
                                                      'http://127.0.0.1:${server.port}/fixture.png'),
                                              translationId:
                                                  'integration-synthetic',
                                              containerWidth: 300,
                                              containerHeight: 450)))),
                            ]),
                            ReaderTranslationToolbar(controller: session),
                          ])))))));
      await waitFor(tester, find.byType(TranslationImageLayer));
      await tester.tap(find.byKey(const Key('translate-text')));
      await waitFor(tester, find.byKey(const Key('translated-text')));
      await tester.tap(find.byKey(const Key('image-translation-tools')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('translate-image')));
      await waitFor(tester, find.text('整图测试成功'));
      expect(imageDownloads,
          1); // Uses the reader's decoded frame, not a second download.
      final before =
          tester.getRect(find.byKey(const Key('translation-bubble-0')));
      final toolRect =
          tester.getRect(find.byKey(const Key('image-translation-tools')));
      zoom.scale = 1.2;
      await tester.pump(const Duration(milliseconds: 400));
      final zoomed =
          tester.getRect(find.byKey(const Key('translation-bubble-0')));
      expect(zoomed.width, closeTo(before.width * 1.2, 1));
      expect(tester.getRect(find.byKey(const Key('image-translation-tools'))),
          toolRect);
      zoom.scale = 1.0;
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('调整'));
      await tester.pump();
      final bubbleFinder = find.byKey(const Key('translation-bubble-0'));
      // Move the toolbar away from the first bubble before dragging it.
      await tester.drag(find.byKey(const Key('image-translation-tools')),
          const Offset(0, 200));
      await tester.pump();
      await tester.drag(bubbleFinder, const Offset(15, 20));
      await tester.pump();
      expect(tester.getRect(bubbleFinder).left, greaterThan(before.left));
      await tester
          .ensureVisible(find.byKey(const Key('translation-resize-handle')));
      await tester.drag(find.byKey(const Key('translation-resize-handle')),
          const Offset(20, 20));
      await tester.pump();
      expect(tester.getRect(bubbleFinder).width, greaterThan(before.width));
      await tester.ensureVisible(find.text('完成调整'));
      await tester.tap(find.text('完成调整'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('snip-image')));
      await tester.pump();
      final surface =
          tester.getRect(find.byKey(const Key('translation-crop-surface')));
      final gesture =
          await tester.startGesture(surface.topLeft + const Offset(140, 80));
      await gesture.moveBy(const Offset(110, 100));
      await gesture.up();
      await waitFor(tester, find.text('框选测试成功'));
      expect(find.byKey(const Key('translation-bubble-1')), findsOneWidget);
      expect(requests.length, 3);
      await tester.ensureVisible(find.byKey(const Key('translate-all-images')));
      await tester.tap(find.byKey(const Key('translate-all-images')));
      await waitFor(tester, find.textContaining('整页翻译完成'));
      expect(session.completed, 3);
      expect(session.failed, 0);
      expect(session.page(1).translated, isTrue);
      expect(session.page(2).translated, isTrue);
      expect(requests.length, 5);
      expect(imageDownloads, 3);
      expect(find.byKey(const Key('image-translation-tools')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      final boundary = screenshotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final capture = await boundary.toImage(pixelRatio: 1);
      final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
      final output =
          '${(await getApplicationSupportDirectory()).path}/translation-smoke.png';
      await File(output).writeAsBytes(bytes!.buffer.asUint8List());
      capture.dispose();
      // Printed path contains no user content; the fixture is generated above.
      debugPrint('TRANSLATION_SMOKE_SCREENSHOT=$output');
      await tester.pumpWidget(const SizedBox());
      zoom.dispose();
      session.dispose();
    } finally {
      await translationStore.save(oldSettings);
      await server.close(force: true);
    }
  });

  testWidgets('complete app starts offline and opens translation settings',
      (tester) async {
    // Block network both in this test zone and in callbacks from the app zone.
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('Offline startup test');
      await request.response.close();
    });
    final previousOverrides = HttpOverrides.current;
    final previousFlutterError = FlutterError.onError;
    final previousPlatformError = ui.PlatformDispatcher.instance.onError;
    final freshLogs =
        await Directory.systemTemp.createTemp('bilingual-startup-');
    await log.clear();
    log.logDirPath = '${freshLogs.path}/logs';
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await app.main([]);
        // The app installs production error/proxy handlers during init. Keep
        // the test binding's error collection and deny network in onReady too.
        FlutterError.onError = previousFlutterError;
        ui.PlatformDispatcher.instance.onError = previousPlatformError;
        HttpOverrides.global = _OfflineHttpOverrides(proxy.port);
        await waitFor(tester, find.byType(app.MyApp));
        await tester.pump(const Duration(seconds: 1));
        Get.offAllNamed(Routes.setting);
        await waitFor(tester, find.text('双语轻译 · BYOK'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('双语轻译 · BYOK'));
        await waitFor(tester, find.byKey(const Key('translation-apiKey')));
        expect(find.byType(TranslationSettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugPrint('FULL_APP_OFFLINE_STARTUP=passed');
        final drawing = ui.PictureRecorder();
        Canvas(drawing).drawColor(Colors.white, BlendMode.src);
        final picture = drawing.endRecording();
        final frame = await picture.toImage(300, 450);
        picture.dispose();
        final data = (await frame.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        frame.dispose();
        final fixture = File('${freshLogs.path}/reader.png');
        await fixture.writeAsBytes(data);
        Get.offAllNamed(Routes.read,
            arguments: ReadPageInfo(
                mode: ReadMode.local,
                galleryTitle: 'Synthetic reader',
                initialIndex: 0,
                pageCount: 3,
                readProgressRecordStorageKey: 'bilingual-offline-reader',
                useSuperResolution: false,
                images: List.generate(
                    3,
                    (_) => GalleryImage(
                        url: '',
                        path: fixture.path,
                        downloadStatus: DownloadStatus.downloaded))));
        await waitFor(tester, find.byKey(const Key('image-translation-tools')));
        await waitFor(tester, find.byType(TranslationImageLayer));
        expect(
            find.byKey(const Key('image-translation-tools')), findsOneWidget);
        final reader = Get.find<ReadPageLogic>();
        reader.translation.activate(1);
        reader.recordReadProgress(0);
        expect(reader.translation.activeIndex, 1);
        reader.recordReadProgress(2);
        expect(reader.translation.activeIndex, 2);
        final unmounted = await reader.translation.loadImage(2, CancelToken());
        expect(unmounted.width, 300);
        unmounted.dispose();
        expect(tester.takeException(), isNull);
        debugPrint('FULL_APP_READER_SINGLE_TOOLBAR_AND_LOCAL_LOADING=passed');
        Get.offAllNamed(Routes.setting);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox());
      }, _OfflineHttpOverrides(proxy.port));
    } finally {
      FlutterError.onError = previousFlutterError;
      ui.PlatformDispatcher.instance.onError = previousPlatformError;
      HttpOverrides.global = previousOverrides;
      await proxy.close(force: true);
    }
  });
}

class _OfflineHttpOverrides extends HttpOverrides {
  final int port;
  _OfflineHttpOverrides(this.port);
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
}
