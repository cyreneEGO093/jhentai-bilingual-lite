// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'reader_translation_controller.dart';
import 'translation_pointer_area.dart';
import 'translation_settings_page.dart';

class ReaderTranslationToolbar extends StatefulWidget {
  final ReaderTranslationController controller;
  final void Function(int)? onPageSelected;
  const ReaderTranslationToolbar(
      {super.key, required this.controller, this.onPageSelected});
  @override
  State<ReaderTranslationToolbar> createState() =>
      _ReaderTranslationToolbarState();
}

class _ReaderTranslationToolbarState extends State<ReaderTranslationToolbar> {
  bool _expanded = false;
  Offset _position = const Offset(.025, .025);
  Offset? _dragStart;
  Offset? _positionStart;
  Rect? _boundsStart;
  Offset? _imageStart;
  RenderBox? _imageBox;
  int? _bubbleIndex;
  int? _pageIndex;
  ReaderTranslationController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_refresh);
  }

  @override
  void didUpdateWidget(ReaderTranslationToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_refresh);
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(_refresh);
    super.dispose();
  }

  void _beginEdit(Offset global) {
    _imageBox = c.activeSurface?.box();
    _bubbleIndex = c.selectedBubble;
    _pageIndex = c.activeIndex;
    if (_imageBox == null || _bubbleIndex == null) {
      return;
    }
    _imageStart = _imageBox!.globalToLocal(global);
    _boundsStart = c.current.bubbles[_bubbleIndex!].bounds;
  }

  void _edit(Offset global, bool resize) {
    final box = _imageBox;
    if (box == null ||
        !box.attached ||
        _boundsStart == null ||
        _imageStart == null ||
        _bubbleIndex == null ||
        _pageIndex != c.activeIndex) {
      return;
    }
    final delta = box.globalToLocal(global) - _imageStart!;
    c.changeBounds(
        _pageIndex!,
        _bubbleIndex!,
        editTranslationBounds(_boundsStart!,
            Offset(delta.dx / box.size.width, delta.dy / box.size.height),
            resize: resize));
  }

  void _endEdit() {
    _imageBox = null;
    _boundsStart = null;
    _imageStart = null;
  }

  Widget _button(String label, VoidCallback? action, {String? key}) =>
      TextButton(
          key: key == null ? null : Key(key),
          onPressed: action,
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size(44, 44),
              textStyle: TextStyle(fontSize: 13 * c.settings().toolScale)),
          child: Text(label));

  Widget _editHandle(String label, bool resize) => TranslationPointerArea(
      key:
          Key(resize ? 'translation-resize-handle' : 'translation-move-handle'),
      onStart: (d) => _beginEdit(d.globalPosition),
      onUpdate: (d) => _edit(d.globalPosition, resize),
      onEnd: (_) => _endEdit(),
      onCancel: _endEdit,
      child: _button(label, c.selectedBubble == null ? null : () {}));

  void _choosePage(int index) {
    c.activate(index);
    widget.onPageSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
          child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final scale = c.settings().toolScale;
        final width =
            math.min(_expanded ? 340 * scale : 48 * scale, size.width);
        final double left = (_position.dx * size.width)
            .clamp(0.0, math.max(0.0, size.width - width))
            .toDouble();
        final double top = (_position.dy * size.height)
            .clamp(0.0, math.max(0.0, size.height - 48 * scale))
            .toDouble();
        return Stack(children: [
          Positioned(
              left: left,
              top: top,
              width: width,
              child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height - top),
                  child: Material(
                      color: const Color(0xff215947),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: IconTheme(
                          data: const IconThemeData(color: Colors.white),
                          child: DefaultTextStyle(
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13 * scale),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TranslationPointerArea(
                                        onTap: () => setState(
                                            () => _expanded = !_expanded),
                                        onStart: (d) {
                                          _dragStart = d.globalPosition;
                                          _positionStart = Offset(left, top);
                                        },
                                        onUpdate: (d) {
                                          if (_dragStart == null) {
                                            return;
                                          }
                                          final p = _positionStart! +
                                              d.globalPosition -
                                              _dragStart!;
                                          setState(() => _position = Offset(
                                              p.dx.clamp(
                                                      0.0,
                                                      math.max(0.0,
                                                          size.width - width)) /
                                                  size.width,
                                              p.dy.clamp(
                                                      0.0,
                                                      math.max(
                                                          0.0,
                                                          size.height -
                                                              48 * scale)) /
                                                  size.height));
                                        },
                                        child: IconButton(
                                            key: const Key(
                                                'image-translation-tools'),
                                            tooltip: _expanded
                                                ? '收起翻译工具（拖动可移动）'
                                                : '展开翻译工具（拖动可移动）',
                                            iconSize: 22 * scale,
                                            constraints: BoxConstraints(
                                                minWidth: 48 * scale,
                                                minHeight: 48 * scale),
                                            icon: Icon(_expanded
                                                ? Icons.close
                                                : Icons.translate),
                                            onPressed: () => setState(
                                                () => _expanded = !_expanded))),
                                    if (_expanded)
                                      Flexible(
                                          child: SingleChildScrollView(
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(children: [
                                                          IconButton(
                                                              tooltip: '上一张',
                                                              onPressed: c.activeIndex >
                                                                      0
                                                                  ? () => _choosePage(
                                                                      c.activeIndex -
                                                                          1)
                                                                  : null,
                                                              icon: const Icon(Icons
                                                                  .chevron_left)),
                                                          Expanded(
                                                              child: Text(
                                                                  '当前第 ' +
                                                                      (c.activeIndex +
                                                                              1)
                                                                          .toString() +
                                                                      ' / ' +
                                                                      c.pageCount
                                                                          .toString() +
                                                                      ' 张',
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center)),
                                                          IconButton(
                                                              tooltip: '下一张',
                                                              onPressed: c.activeIndex +
                                                                          1 <
                                                                      c
                                                                          .pageCount
                                                                  ? () => _choosePage(
                                                                      c.activeIndex +
                                                                          1)
                                                                  : null,
                                                              icon: const Icon(Icons
                                                                  .chevron_right)),
                                                        ]),
                                                        Wrap(children: [
                                                          _button(
                                                              '整图',
                                                              c.busy
                                                                  ? null
                                                                  : () => c
                                                                      .translate(),
                                                              key:
                                                                  'translate-image'),
                                                          _button(
                                                              '整页翻译',
                                                              c.busy
                                                                  ? null
                                                                  : () => c
                                                                      .translate(
                                                                          all:
                                                                              true),
                                                              key:
                                                                  'translate-all-images'),
                                                          if (c.busy)
                                                            _button(
                                                                '停止', c.cancel,
                                                                key:
                                                                    'stop-image-translation'),
                                                          _button(
                                                              c.selecting
                                                                  ? '退出框选'
                                                                  : '框选',
                                                              c.busy
                                                                  ? null
                                                                  : c.toggleSelection,
                                                              key: 'snip-image'),
                                                          _button(
                                                              c.current.visible
                                                                  ? '原图'
                                                                  : '译文',
                                                              c.toggleVisible),
                                                          _button(
                                                              c.editing
                                                                  ? '完成调整'
                                                                  : '调整',
                                                              c.current.bubbles
                                                                          .isEmpty &&
                                                                      !c.editing
                                                                  ? null
                                                                  : c.toggleEditing),
                                                          IconButton(
                                                              tooltip: '翻译设置',
                                                              icon: const Icon(
                                                                  Icons
                                                                      .settings,
                                                                  size: 20),
                                                              onPressed: () =>
                                                                  openTranslationSettings(
                                                                      context)),
                                                        ]),
                                                        if (c.editing) ...[
                                                          const Text(
                                                              '点选译文框后直接拖动，或拖动下方按钮移动、缩放。'),
                                                          Wrap(children: [
                                                            _editHandle(
                                                                '移动', false),
                                                            _editHandle(
                                                                '缩放', true),
                                                            _button('重置框位',
                                                                c.resetBounds),
                                                            _button(
                                                                '删除选中框',
                                                                c.selectedBubble ==
                                                                        null
                                                                    ? null
                                                                    : c.deleteSelected),
                                                          ]),
                                                        ],
                                                        if (c.busy &&
                                                            c.batching)
                                                          Text('已完成 ' +
                                                              c.completed
                                                                  .toString() +
                                                              ' 张，失败 ' +
                                                              c.failed
                                                                  .toString() +
                                                              ' 张'),
                                                        if (c.status != null)
                                                          Text(c.status!,
                                                              key: const Key(
                                                                  'image-translation-status')),
                                                        const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                    top: 6),
                                                            child: Text(
                                                                '整页翻译将处理本作品全部图片（含未浏览图片），会产生 API 用量。')),
                                                      ])))),
                                  ]))))))
        ]);
      })));
}
