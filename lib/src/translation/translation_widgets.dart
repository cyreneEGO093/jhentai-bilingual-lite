// SPDX-License-Identifier: GPL-3.0-only
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'translation_client.dart';
import 'translation_models.dart';
import 'translation_store.dart';
import 'translation_settings_page.dart';

final translationClient = TranslationClient();

String translationError(Object error) => error is TranslationFailure
    ? error.message
    : error is FormatException
        ? error.message
        : '翻译失败，请检查设置后重试。';

/// Appends a translation without changing the original widget or its semantics.
class TranslatableText extends StatefulWidget {
  final Widget child;
  final String source;
  final bool boundedPreview;
  const TranslatableText(
      {super.key,
      required this.child,
      required this.source,
      this.boundedPreview = false});
  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  CancelToken? _token;
  String? _translation;
  String? _error;
  bool _busy = false;
  bool _visible = true;

  @override
  void didUpdateWidget(TranslatableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _token?.cancel();
      _translation = null;
      _error = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _translate() async {
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await translationStore.load();
      final result = await translationClient
          .text(widget.source, translationStore.settings, cancelToken: token);
      if (mounted && !token.isCancelled) {
        setState(() {
          _translation = result;
          _visible = true;
        });
      }
    } catch (error) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = translationError(error));
      }
    } finally {
      if (mounted && identical(_token, token)) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.boundedPreview)
              Expanded(
                  child: ClipRect(
                      child: SingleChildScrollView(child: _content(context))))
            else
              widget.child,
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                key: const Key('translate-text'),
                icon: Icon(_busy ? Icons.stop : Icons.translate, size: 16),
                label: Text(_busy
                    ? '停止翻译'
                    : _translation == null
                        ? '翻译文本'
                        : _visible
                            ? '隐藏译文'
                            : '显示译文'),
                onPressed: _busy
                    ? () {
                        _token?.cancel();
                        setState(() => _busy = false);
                      }
                    : _translation == null
                        ? _translate
                        : () => setState(() => _visible = !_visible),
              ),
              if (_translation != null)
                IconButton(
                    tooltip: '重新翻译',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _busy ? null : _translate),
              if (_error != null)
                IconButton(
                    tooltip: '翻译设置',
                    icon: const Icon(Icons.settings, size: 18),
                    onPressed: () => openTranslationSettings(context)),
            ]),
            if (!widget.boundedPreview && _translation != null && _visible)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2))),
                child: SelectableText(_translation!,
                    key: const Key('translated-text')),
              ),
            if (!widget.boundedPreview && _error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]);

  Widget _content(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.child,
            if (_translation != null && _visible)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(_translation!,
                      key: const Key('translated-text'))),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]);
}
