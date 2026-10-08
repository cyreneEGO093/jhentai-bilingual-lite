// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/setting/advanced_setting.dart';

void main() {
  test('importing legacy settings drops the upstream update preference', () {
    final settings = AdvancedSetting();
    settings.applyBeanConfig(jsonEncode({
      'enableLogging': false,
      'enableCheckUpdate': true,
      'enableCheckClipboard': false,
      'inNoImageMode': true,
    }));
    final saved = jsonDecode(settings.toConfigString()) as Map;
    expect(saved.containsKey('enableCheckUpdate'), isFalse);
    expect(saved['enableLogging'], isFalse);
    expect(saved['enableCheckClipboard'], isFalse);
    expect(saved['inNoImageMode'], isTrue);
    settings.applyBeanConfig(settings.toConfigString());
    expect(jsonDecode(settings.toConfigString()), saved);
  });
}
