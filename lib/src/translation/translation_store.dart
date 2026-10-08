// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'translation_settings.dart';

final translationStore = TranslationStore();

class TranslationStore extends ChangeNotifier {
  static const _keyName = 'bilingual-lite-api-key';
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  TranslationSettings settings = const TranslationSettings();
  String? loadError;
  Future<void>? _initialization;
  File? _file;

  Future<void> load() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      _file = File('${directory.path}/bilingual-lite-settings.json');
      Map<String, dynamic> values = {};
      if (await _file!.exists()) {
        values =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      }
      settings = TranslationSettings.fromJson(values,
          apiKey: await _secure.read(key: _keyName) ?? '');
    } catch (_) {
      loadError = '翻译设置或系统密钥存储读取失败，请重新保存配置。';
    }
    notifyListeners();
  }

  Future<void> save(TranslationSettings value) async {
    await load();
    value.validate();
    if (_file == null) {
      throw const FileSystemException('翻译配置目录不可用');
    }
    // Fail closed: no plaintext fallback when the OS credential store fails.
    if (value.apiKey.isEmpty) {
      await _secure.delete(key: _keyName);
    } else {
      await _secure.write(key: _keyName, value: value.apiKey);
    }
    final temp = File('${_file!.path}.tmp');
    await temp.writeAsString(jsonEncode(value.toJson()), flush: true);
    await temp.rename(_file!.path);
    settings = value;
    loadError = null;
    notifyListeners();
  }
}
