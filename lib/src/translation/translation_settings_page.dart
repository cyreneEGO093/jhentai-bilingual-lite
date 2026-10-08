// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'translation_settings.dart';
import 'translation_store.dart';
import 'translation_widgets.dart';
import 'translation_client.dart';

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
    });
  }

  @override
  void dispose() {
    _testingClient?.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
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
                '连接成功，服务提供 ${models.length} 个模型。${models.contains(value.visionModel) ? '' : '当前图片模型未出现在列表中，请核对名称及视觉能力。'}');
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
                            '点击翻译时，所选文字或压缩图片、作品背景和术语表将发送到下面配置的 API 服务。API Key 由用户提供，调用可能收费。模型需自行支持所选内容；图片模型必须支持视觉输入。'),
                        const SizedBox(height: 20),
                        _field('baseUrl', 'API 地址', max: 400),
                        _field('apiKey', 'API Key（系统安全存储）', max: 1000),
                        _field('textModel', '文本模型', max: 200),
                        _field('visionModel', '图片模型', max: 200),
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
