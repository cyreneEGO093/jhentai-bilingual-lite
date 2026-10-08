// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/translation/translation_client.dart';
import 'package:jhentai/src/translation/translation_models.dart';
import 'package:jhentai/src/translation/translation_settings.dart';

class FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  FakeAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(dynamic data,
        {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers
      },
    );

ResponseBody completion(dynamic content,
        {String finish = 'stop', int reasoning = 0}) =>
    response({
      'choices': [
        {
          'finish_reason': finish,
          'message': {'content': jsonEncode(content)}
        }
      ],
      'usage': {
        'completion_tokens_details': {'reasoning_tokens': reasoning}
      },
    });

TranslationClient client(
        Future<ResponseBody> Function(RequestOptions) handler) =>
    TranslationClient(dio: Dio()..httpClientAdapter = FakeAdapter(handler));
const configured = TranslationSettings(apiKey: 'test-placeholder');

void main() {
  test(
      'OpenRouter text uses bounded output, disables reasoning and preserves IDs',
      () async {
    final api = client((options) async {
      expect(options.uri.toString(),
          'https://openrouter.ai/api/v1/chat/completions');
      expect(options.method, 'POST');
      expect(options.followRedirects, isFalse);
      final body = options.data as Map;
      expect(body['temperature'], .1);
      expect(body['max_tokens'], 1500);
      expect(body['reasoning'], {'enabled': false});
      expect(options.headers['Cookie'], isNull);
      expect(jsonEncode(body['messages']), contains('Test custom 简体中文'));
      final batch = jsonDecode(body['messages'][1]['content']) as List;
      return completion({
        'translations': batch.reversed
            .map((item) =>
                {'id': '${item['id']}', 'translated': '译${item['id']}'})
            .toList()
      });
    });
    final result = await api.text(
        'a' * 1000,
        const TranslationSettings(
            apiKey: 'test-placeholder',
            textPrompt: 'Test custom {{targetLang}}'));
    expect(result, '译0\n译1');
    api.dispose();
  });

  test('custom endpoints do not receive OpenRouter-only reasoning parameters',
      () async {
    final api = client((o) async {
      expect((o.data as Map).containsKey('reasoning'), isFalse);
      return completion({
        'translations': [
          {'id': 0, 'translated': '你好'}
        ]
      });
    });
    expect(
        await api.text(
            'Hello',
            const TranslationSettings(
                baseUrl: 'http://localhost:1234/v1', apiKey: 'local')),
        '你好');
    api.dispose();
  });

  test('output truncation, reasoning usage and duplicate IDs are rejected',
      () async {
    for (final output in [
      completion({'translations': []}, finish: 'length'),
      completion({'translations': []}, reasoning: 10),
      completion({
        'translations': [
          {'id': 0, 'translated': 'a'},
          {'id': 0, 'translated': 'b'}
        ]
      }),
    ]) {
      final api = client((_) async => output);
      await expectLater(
          api.text('a' * 1000, configured), throwsA(isA<TranslationFailure>()));
      api.dispose();
    }
  });

  test(
      '401 reports a useful error without echoing provider data or credentials',
      () async {
    final api = client(
        (_) async => response({'error': 'private-test-content'}, status: 401));
    await expectLater(
        api.text('Hello', configured),
        throwsA(isA<TranslationFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('API Key'), isNot(contains('private-test-content')),
                isNot(contains('test-placeholder'))))));
    api.dispose();
  });

  test('429 is retried once; other requests are not automatically duplicated',
      () async {
    var attempts = 0;
    final api = client((_) async {
      attempts++;
      return attempts == 1
          ? response({},
              status: 429,
              headers: {
                'retry-after': ['1']
              })
          : completion({
              'translations': [
                {'id': 0, 'translated': '你好'}
              ]
            });
    });
    expect(await api.text('Hello', configured), '你好');
    expect(attempts, 2);
    api.dispose();
  });

  test(
      'queue limits concurrent requests and cancelled queued jobs send nothing',
      () async {
    var active = 0;
    var maximum = 0;
    var requests = 0;
    final gate = Completer<void>();
    final api = client((_) async {
      requests++;
      active++;
      if (active > maximum) {
        maximum = active;
      }
      await gate.future;
      active--;
      return response({
        'data': [
          {'id': 'test-model'}
        ]
      });
    });
    final first = api.models(configured);
    final second = api.models(configured);
    final token = CancelToken();
    final cancelled = api.models(configured, cancelToken: token);
    final cancelledExpectation =
        expectLater(cancelled, throwsA(isA<TranslationFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    token.cancel();
    gate.complete();
    await Future.wait([first, second]);
    await cancelledExpectation;
    expect(maximum, 2);
    expect(requests, 2);
    api.dispose();
  });

  test(
      'normalized vision coordinates and snip coordinates are mapped correctly',
      () async {
    final api = client((o) async => completion({
          'bubbles': [
            {
              'original': 'Hello',
              'translated': '你好',
              'bbox': [100, 200, 400, 700]
            }
          ]
        }));
    final bubbles = await api.image('data:image/jpeg;base64,AA==', configured);
    expect(bubbles.single.bounds, const Rect.fromLTRB(.2, .1, .7, .4));
    api.dispose();
    final snip = client(
        (_) async => completion({'original': 'Hello', 'translated': '你好'}));
    const region = Rect.fromLTRB(.1, .2, .3, .5);
    expect(
        (await snip.image('data:image/jpeg;base64,AA==', configured,
                crop: region))
            .single
            .bounds,
        region);
    snip.dispose();
  });

  test('invalid bbox and insecure endpoints fail closed', () {
    for (final bbox in [
      [0, 0, 1001, 100],
      [200, 0, 100, 100],
      [0, '0', 100, 100]
    ]) {
      expect(
          () => TranslationBubble.parse(jsonEncode([
                {'original': '', 'translated': 'test', 'bbox': bbox}
              ])),
          throwsA(isA<TranslationFailure>()));
    }
    for (final url in [
      'http://remote.example/v1',
      'https://user:secret@example.com/v1',
      'https://example.com/v1?secret=value'
    ]) {
      expect(() => TranslationSettings(baseUrl: url).validate(),
          throwsFormatException);
    }
    expect(configured.toJson().containsKey('apiKey'), isFalse);
    expect(clampTranslationRect(const Rect.fromLTWH(-.2, 1, .5, .5)),
        const Rect.fromLTWH(0, .5, .5, .5));
  });
}
