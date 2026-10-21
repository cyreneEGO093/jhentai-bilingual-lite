// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Bilingual Lite v0.6.1 selected-text translation.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'translation_client.dart';
import 'translation_models.dart';
import 'translation_settings.dart';
import 'translation_store.dart';
import 'translation_widgets.dart';

class SelectionTranslationController extends ChangeNotifier {
  final String source;
  final TranslationClient client;
  final Future<TranslationSettings> Function() loadSettings;
  final List<String> results = [];
  final List<String> _chunks = [];
  TranslationSettings? _settings;
  CancelToken? _token;
  bool _disposed = false;
  bool busy = false;
  String? error;
  int get total => _chunks.length;
  bool get complete => total > 0 && results.length == total;

  SelectionTranslationController(this.source,
      {TranslationClient? client,
      Future<TranslationSettings> Function()? loadSettings})
      : client = client ?? translationClient,
        loadSettings = loadSettings ??
            (() async {
              await translationStore.load();
              return translationStore.settings;
            }) {
    if (source.trim().isEmpty || source.length > 6000) {
      error = '请选择 1～6000 字符的文本。';
      return;
    }
    var part = StringBuffer();
    for (final rune in source.runes) {
      final size = rune > 0xffff ? 2 : 1;
      if (part.length + size > 1200) {
        _chunks.add(part.toString());
        part = StringBuffer();
      }
      part.writeCharCode(rune);
    }
    if (part.isNotEmpty) {
      _chunks.add(part.toString());
    }
  }

  Future<void> run() async {
    if (_disposed || busy || complete || _chunks.isEmpty) {
      return;
    }
    final token = CancelToken();
    _token = token;
    busy = true;
    error = null;
    notifyListeners();
    try {
      _settings ??= await loadSettings();
      while (!_disposed && !token.isCancelled && results.length < total) {
        final result = await client.text(_chunks[results.length], _settings!,
            cancelToken: token);
        if (_disposed || token.isCancelled) {
          return;
        }
        results.add(result);
        notifyListeners();
      }
    } catch (e) {
      if (!_disposed && !token.isCancelled) {
        error = e is TranslationFailure ? e.message : translationError(e);
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _token = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  void stop() => _token?.cancel();
}

ContextMenuButtonItem selectionTranslationItem(
        BuildContext context, String source) =>
    ContextMenuButtonItem(
        label: '翻译选中文本',
        onPressed: () {
          ContextMenuController.removeAny();
          showDialog<void>(
              context: context,
              builder: (_) => SelectionTranslationDialog(source: source));
        });

class TranslationSelectionArea extends StatefulWidget {
  final Widget child;
  final List<ContextMenuButtonItem> extraItems;
  const TranslationSelectionArea(
      {super.key, required this.child, this.extraItems = const []});
  @override
  State<TranslationSelectionArea> createState() =>
      _TranslationSelectionAreaState();
}

class _TranslationSelectionAreaState extends State<TranslationSelectionArea> {
  String _selected = '';
  @override
  Widget build(BuildContext context) => SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText ?? '',
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.buttonItems(
              anchors: state.contextMenuAnchors,
              buttonItems: [
                ...state.contextMenuButtonItems,
                if (_selected.trim().isNotEmpty)
                  selectionTranslationItem(context, _selected),
                ...widget.extraItems
              ]),
      child: widget.child);
}

class SelectionTranslationDialog extends StatefulWidget {
  final String source;
  final SelectionTranslationController? controller;
  const SelectionTranslationDialog(
      {super.key, required this.source, this.controller});
  @override
  State<SelectionTranslationDialog> createState() =>
      _SelectionTranslationDialogState();
}

class _SelectionTranslationDialogState
    extends State<SelectionTranslationDialog> {
  late final c =
      widget.controller ?? SelectionTranslationController(widget.source);
  @override
  void initState() {
    super.initState();
    c.run();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              c.stop();
            }
          },
          child: AlertDialog(
              title: const Text('选中文本翻译'),
              content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        if (c.busy) const LinearProgressIndicator(),
                        Text('已完成 ${c.results.length} / ${c.total} 段'),
                        if (c.results.isNotEmpty)
                          SelectableText(c.results.join('\n\n'),
                              key: const Key('selection-translated-text')),
                        if (c.error != null)
                          Text(c.error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ExpansionTile(
                            title: const Text('查看原文'),
                            children: [SelectableText(c.source)]),
                        const Text('关闭将停止后续分段；已发送请求仍可能计费。'),
                      ]))),
              actions: [
                if (!c.busy && !c.complete && c.total > 0)
                  TextButton(onPressed: c.run, child: const Text('重试未完成部分')),
                TextButton(
                    key: const Key('close-selection-translation'),
                    onPressed: () {
                      c.stop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('关闭')),
              ])));
}
