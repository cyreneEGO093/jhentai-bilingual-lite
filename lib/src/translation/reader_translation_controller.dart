// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'image_preprocessor.dart';
import 'translation_client.dart';
import 'translation_models.dart';
import 'translation_settings.dart';
import 'translation_store.dart';
import 'translation_widgets.dart';

typedef ReaderImageLoader = Future<ui.Image> Function(
    int index, CancelToken token);

class ReaderTranslationPage {
  List<TranslationBubble> bubbles = [];
  List<TranslationBubble> original = [];
  bool translated = false;
  bool visible = true;
}

/// Owns text results for one reading session, never a cache of decoded images.
class ReaderTranslationController extends ChangeNotifier {
  final int pageCount;
  final ReaderImageLoader loadImage;
  final TranslationClient client;
  final TranslationSettings Function() settings;
  final Future<void> Function() ensureSettings;
  final Map<int, ReaderTranslationPage> _pages = {};
  final Map<int, ReaderImageSurface> _surfaces = {};
  final bool _listenSettings;
  int activeIndex;
  int? selectedBubble;
  bool editing = false;
  bool selecting = false;
  bool busy = false;
  bool batching = false;
  int completed = 0;
  int failed = 0;
  String? status;
  CancelToken? _token;
  bool _disposed = false;
  bool _cancelRequested = false;
  String _fingerprint = '';

  ReaderTranslationController(
      {required this.pageCount,
      required this.loadImage,
      this.activeIndex = 0,
      TranslationClient? client,
      TranslationSettings Function()? settings,
      Future<void> Function()? ensureSettings})
      : client = client ?? translationClient,
        settings = settings ?? (() => translationStore.settings),
        ensureSettings = ensureSettings ?? translationStore.load,
        _listenSettings = settings == null {
    if (_listenSettings) {
      _fingerprint = _settingsFingerprint();
      translationStore.addListener(_settingsChanged);
    }
  }

  ReaderTranslationPage page(int index) =>
      _pages.putIfAbsent(index, ReaderTranslationPage.new);
  ReaderTranslationPage get current => page(activeIndex);
  ReaderImageSurface? get activeSurface => _surfaces[activeIndex];
  void changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _settingsFingerprint() => jsonEncode(settings().toJson()
    ..remove('opacity')
    ..remove('fontSize')
    ..remove('toolScale'));
  void _settingsChanged() {
    final next = _settingsFingerprint();
    if (next != _fingerprint) {
      if (_token != null) {
        cancel();
      }
      _pages.clear();
      selectedBubble = null;
      _fingerprint = next;
    }
    changed();
  }

  void attach(int index, ReaderImageSurface surface) =>
      _surfaces[index] = surface;
  void detach(int index, ReaderImageSurface surface) {
    if (identical(_surfaces[index], surface)) {
      _surfaces.remove(index);
    }
  }

  void activate(int index) {
    if (index == activeIndex || index < 0 || index >= pageCount) {
      return;
    }
    activeIndex = index;
    selectedBubble = null;
    selecting = false;
    changed();
  }

  void select(int index, int bubble) {
    activate(index);
    selectedBubble = bubble;
    changed();
  }

  void toggleEditing() {
    editing = !editing;
    selecting = false;
    current.visible = true;
    changed();
  }

  void toggleSelection() {
    if (!selecting && activeSurface?.box()?.hasSize != true) {
      status = '请等待当前图片显示后再框选。';
      changed();
      return;
    }
    selecting = !selecting;
    editing = false;
    changed();
  }

  void toggleVisible() {
    current.visible = !current.visible;
    editing = false;
    changed();
  }

  void resetBounds() {
    current.bubbles = List.of(current.original);
    selectedBubble = null;
    changed();
  }

  void deleteSelected() {
    final index = selectedBubble;
    if (index == null || index >= current.bubbles.length) {
      return;
    }
    current.bubbles = List.of(current.bubbles)..removeAt(index);
    selectedBubble = null;
    changed();
  }

  void changeBounds(int index, int bubble, Rect bounds) {
    final items = page(index).bubbles;
    if (bubble < 0 || bubble >= items.length) {
      return;
    }
    items[bubble] = items[bubble].withBounds(bounds);
    changed();
  }

  void cancel() {
    _cancelRequested = true;
    _token?.cancel();
    selecting = false;
    if (busy) {
      status = '已停止；已完成的译文会保留。';
    }
    changed();
  }

  Future<void> translate({Rect? crop, bool all = false}) async {
    if (busy || _disposed) {
      return;
    }
    // Loading settings can invalidate existing translations, before a new token exists.
    busy = true;
    _cancelRequested = false;
    final requestedIndex = activeIndex;
    changed();
    CancelToken? token;
    try {
      await ensureSettings();
      if (_disposed || _cancelRequested) {
        return;
      }
      final config = settings();
      config.validate(requireKey: true);
      token = CancelToken();
      _token = token;
      batching = all;
      selecting = false;
      completed = 0;
      failed = 0;
      final targets =
          all ? List.generate(pageCount, (i) => i) : [requestedIndex];
      for (final index in targets) {
        if (token.isCancelled || _disposed) {
          break;
        }
        if (all && page(index).translated) {
          completed++;
          continue;
        }
        status = '正在翻译第 ' + (index + 1).toString() + ' / $pageCount 张';
        changed();
        ui.Image? pixels;
        try {
          pixels = _surfaces[index]?.snapshot();
          pixels ??= await loadImage(index, token);
          if (token.isCancelled) {
            throw token.cancelError!;
          }
          final prepared = await prepareTranslationImage(pixels, crop: crop);
          pixels.dispose();
          pixels = null;
          if (token.isCancelled) {
            throw token.cancelError!;
          }
          final result = await client.image(prepared.dataUrl, config,
              crop: crop, cancelToken: token);
          if (token.isCancelled || _disposed) {
            break;
          }
          final state = page(index);
          state.bubbles = crop == null ? result : [...state.bubbles, ...result];
          state.original =
              crop == null ? List.of(result) : [...state.original, ...result];
          state.translated = crop == null || state.translated;
          state.visible = true;
          if (activeIndex == index) {
            selectedBubble = null;
          }
          completed++;
          if (!all) {
            status = result.isEmpty ? '未识别到文字。' : '图片翻译完成。';
          }
        } catch (error) {
          if (token.isCancelled || _disposed) {
            break;
          }
          failed++;
          status = translationError(error);
          if (!all ||
              (error is TranslationFailure &&
                  (error.status == 401 || error.status == 402))) {
            break;
          }
        } finally {
          pixels?.dispose();
        }
        changed();
      }
      if (all && !token.isCancelled && completed + failed == pageCount) {
        status = '整页翻译完成：成功 $completed 张，失败 $failed 张。再次点击可重试失败图片。';
      }
    } catch (error) {
      if (!_disposed && token?.isCancelled != true) {
        status = translationError(error);
      }
    } finally {
      busy = false;
      batching = false;
      _token = null;
      changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    if (_listenSettings) {
      translationStore.removeListener(_settingsChanged);
    }
    _surfaces.clear();
    _pages.clear();
    super.dispose();
  }
}

class ReaderImageSurface {
  final ui.Image Function() snapshot;
  final RenderBox? Function() box;
  ReaderImageSurface({required this.snapshot, required this.box});
}

class ReaderTranslationScope extends InheritedWidget {
  final ReaderTranslationController controller;
  const ReaderTranslationScope(
      {super.key, required this.controller, required super.child});
  static ReaderTranslationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderTranslationScope>()
      ?.controller;
  @override
  bool updateShouldNotify(ReaderTranslationScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Coordinates are normalized to the untransformed image; clamp without moving the opposite corner.
Rect editTranslationBounds(Rect start, Offset delta, {required bool resize}) {
  if (resize) {
    return Rect.fromLTWH(
        start.left,
        start.top,
        (start.width + delta.dx)
            .clamp(.015.clamp(0.0, 1 - start.left), 1 - start.left),
        (start.height + delta.dy)
            .clamp(.015.clamp(0.0, 1 - start.top), 1 - start.top));
  }
  return Rect.fromLTWH(
      (start.left + delta.dx).clamp(0, 1 - start.width),
      (start.top + delta.dy).clamp(0, 1 - start.height),
      start.width,
      start.height);
}
