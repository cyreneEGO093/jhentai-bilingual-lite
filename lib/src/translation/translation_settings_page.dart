// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'translation_settings.dart';
import 'translation_store.dart';
import 'translation_widgets.dart';
import 'translation_client.dart';
import 'local_ocr.dart';
import 'package:dio/dio.dart';

Future<void> openTranslationSettings(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TranslationSettingsPage()),
    );

class TranslationSettingsPage extends StatefulWidget {
  const TranslationSettingsPage({super.key});
  @override
  State<TranslationSettingsPage> createState() =>
      _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  final _fields = <String, TextEditingController>{};
  bool _loaded = false;
  bool _busy = false;
  bool _showKey = false;
  String? _message;
  double _opacity = .94;
  double _fontSize = 16;
  double _scale = 1;
  TranslationClient? _testingClient;
  CancelToken? _download;
  double _downloadProgress = 0;
  bool _modelsReady = false;

  @override
  void initState() {
    super.initState();
    translationStore.load().then((_) {
      if (!mounted) {
        return;
      }
      final settings = translationStore.settings;
      for (final item in settings.toJson().entries) {
        if (item.value is String) {
          _fields[item.key] = TextEditingController(text: item.value as String);
        }
      }
      _fields['apiKey'] = TextEditingController(text: settings.apiKey);
      setState(() {
        _opacity = settings.opacity;
        _fontSize = settings.fontSize;
        _scale = settings.toolScale;
        _message = translationStore.loadError;
        _loaded = true;
      });
      _refreshModels();
    });
  }

  @override
  void dispose() {
    _download?.cancel();
    _testingClient?.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshModels() async {
    if (!localOcr.supported) {
      return;
    }
    try {
      final state = await localOcr.status();
      if (mounted) {
        setState(() => _modelsReady = state['ready'] == true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _modelsReady = false);
      }
    }
  }

  Future<void> _manageModels({bool remove = false}) async {
    final token = CancelToken();
    setState(() {
      _download = token;
      _downloadProgress = 0;
      _message = null;
    });
    try {
      if (remove) {
        await localOcr.remove();
      } else {
        await localOcr.install(token, (value) {
          if (mounted) {
            setState(() => _downloadProgress = value);
          }
        });
      }
      if (mounted) {
        setState(
            () => _message = remove ? '已删除本地模型。' : '模型校验完成，可保存并使用本地 OCR 模式。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            token.isCancelled ? '模型下载已取消。' : translationError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _download = null);
        await _refreshModels();
      }
    }
  }

  TranslationSettings _value() => TranslationSettings.fromJson({
        for (final entry in _fields.entries)
          if (entry.key != 'apiKey') entry.key: entry.value.text.trim(),
        'opacity': _opacity,
        'fontSize': _fontSize,
        'toolScale': _scale,
      }, apiKey: _fields['apiKey']!.text.trim());

  Future<void> _save({bool test = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final value = _value();
      value.validate(requireKey: test);
      if (test) {
        final client = TranslationClient();
        _testingClient = client;
        try {
          final models = await client.models(value);
          if (mounted) {
            setState(() => _message =
                '连接成功，服务提供 ${models.length} 个模型。${value.imageBackend == 'localOcr' ? (models.contains(value.textModel) ? '' : '当前文本模型未出现在列表中，请核对名称。') : (models.contains(value.visionModel) ? '' : '当前图片模型未出现在列表中，请核对名称及视觉能力。')}');
          }
        } finally {
          client.dispose();
          _testingClient = null;
        }
      } else {
        await translationStore.save(value);
        if (mounted) {
          setState(() => _message = '已保存。只在点击翻译后发送内容。');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = translationError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _field(String key, String label,
          {int lines = 1, int? max, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          key: Key('translation-$key'),
          controller: _fields[key],
          maxLines: lines,
          maxLength: max,
          obscureText: key == 'apiKey' && !_showKey,
          enableSuggestions: key != 'apiKey',
          autocorrect: key != 'apiKey',
          decoration: InputDecoration(
            labelText: label,
            helperText: hint,
            helperMaxLines: 4,
            border: const OutlineInputBorder(),
            suffixIcon: key == 'apiKey'
                ? IconButton(
                    tooltip: '显示／隐藏密钥',
                    icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey))
                : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('双语轻译 · BYOK')),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                            '点击翻译时，文字及翻译配置会发送到下面的 API 服务；视觉模式还会发送压缩图片，本地 OCR 模式只发送识别文字。API Key 由用户提供，调用可能收费。视觉模式的图片模型必须支持图片输入。'),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          key: const Key('translation-imageBackend'),
                          initialValue: _fields['imageBackend']!.text,
                          decoration:
                              const InputDecoration(labelText: '图片翻译方式'),
                          items: [
                            const DropdownMenuItem(
                                value: 'vision', child: Text('视觉模型（默认）')),
                            DropdownMenuItem(
                                value: 'localOcr',
                                enabled: localOcr.supported,
                                child: const Text('手机本地 OCR + 文本翻译（实验）')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(
                                  () => _fields['imageBackend']!.text = value);
                            }
                          },
                        ),
                        if (localOcr.supported) ...[
                          const SizedBox(height: 12),
                          const Text(
                              '本地模式：图片留在手机，只发送识别出的文字、作品背景和术语表。下载约 30 MB 模型需联网（ModelScope），完成后识别可离线，文本翻译仍需 API。适合中日英印刷对白，复杂排版可能漏字；不会自动上传图片兜底。'),
                          Text(_modelsReady
                              ? 'OCR 模型已下载（运行前再次校验）'
                              : '尚未下载完整 OCR 模型'),
                          Wrap(spacing: 8, children: [
                            OutlinedButton(
                                key: const Key('ocr-download'),
                                onPressed:
                                    _download != null ? null : _manageModels,
                                child: const Text('下载／校验模型')),
                            TextButton(
                                onPressed: _download != null
                                    ? null
                                    : () => _manageModels(remove: true),
                                child: const Text('删除模型')),
                            if (_download != null)
                              TextButton(
                                  onPressed: () => _download?.cancel(),
                                  child: const Text('取消下载')),
                          ]),
                          if (_download != null)
                            LinearProgressIndicator(value: _downloadProgress),
                        ],
                        const SizedBox(height: 20),
                        _field('baseUrl', 'API 地址', max: 400),
                        _field('apiKey', 'API Key（系统安全存储）', max: 1000),
                        _field('textModel', '文本模型', max: 200),
                        _field('visionModel', '图片模型',
                            max: 200, hint: '仅视觉模式使用；本地 OCR 使用上方的文本模型。'),
                        _field('targetLang', '目标语言', max: 80),
                        _field('context', '作品背景', lines: 3, max: 500),
                        _field('glossary', '术语表',
                            lines: 4,
                            max: 3000,
                            hint: '每行填写：原文 = 固定译名。用于角色、技能和职业名称。'),
                        Text('遮罩不透明度：${(_opacity * 100).round()}%'),
                        Slider(
                            value: _opacity,
                            min: .1,
                            max: 1,
                            divisions: 18,
                            onChanged: (v) => setState(() => _opacity = v)),
                        Text('译文字号：${_fontSize.round()}'),
                        Slider(
                            value: _fontSize,
                            min: 10,
                            max: 32,
                            divisions: 22,
                            onChanged: (v) => setState(() => _fontSize = v)),
                        Text('图片工具大小：${(_scale * 100).round()}%'),
                        Slider(
                            value: _scale,
                            min: .75,
                            max: 1.5,
                            divisions: 15,
                            onChanged: (v) => setState(() => _scale = v)),
                        const Text(
                            '自定义提示词（留空使用默认值；支持 {{targetLang}}）。输出格式和 Token 上限仍由应用控制。'),
                        const SizedBox(height: 16),
                        _field('textPrompt', '文本提示词', lines: 4, max: 3000),
                        _field('imagePrompt', '整图提示词', lines: 4, max: 3000),
                        _field('snippetPrompt', '框选提示词', lines: 4, max: 3000),
                        Wrap(spacing: 12, runSpacing: 8, children: [
                          FilledButton(
                              onPressed: _busy ? null : _save,
                              child: const Text('保存设置')),
                          OutlinedButton(
                              onPressed: _busy ? null : () => _save(test: true),
                              child: const Text('查询模型验证连接')),
                        ]),
                        if (_busy) const LinearProgressIndicator(),
                        if (_message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_message!)),
                      ],
                    )),
              ),
      );
}
