// SPDX-License-Identifier: GPL-3.0-only
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'reader_translation_controller.dart';
import 'translation_store.dart';
import 'translation_pointer_area.dart';

/// Image-relative translations and edit handles; the toolbar stays in the viewport.
class TranslationImageLayer extends StatefulWidget {
  final String imageId;
  final int pageIndex;
  final ui.Image image;
  final Widget child;
  const TranslationImageLayer(
      {super.key,
      required this.imageId,
      this.pageIndex = 0,
      required this.image,
      required this.child});
  @override
  State<TranslationImageLayer> createState() => _TranslationImageLayerState();
}

class _TranslationImageLayerState extends State<TranslationImageLayer> {
  final _surfaceKey = GlobalKey();
  ReaderTranslationController? _controller;
  late final _surface = ReaderImageSurface(
      snapshot: () => widget.image.clone(),
      box: () => _surfaceKey.currentContext?.findRenderObject() as RenderBox?);
  Offset? _start;
  Offset? _end;
  Rect? _dragBounds;
  Offset? _dragStart;
  bool _resizing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ReaderTranslationScope.maybeOf(context);
    if (controller == _controller) {
      return;
    }
    _controller?.removeListener(_refresh);
    _controller?.detach(widget.pageIndex, _surface);
    _controller = controller;
    controller?.attach(widget.pageIndex, _surface);
    controller?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(TranslationImageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex) {
      _controller?.detach(oldWidget.pageIndex, _surface);
      _controller?.attach(widget.pageIndex, _surface);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_refresh);
    _controller?.detach(widget.pageIndex, _surface);
    super.dispose();
  }

  Offset _point(Offset global) {
    final box = _surface.box()!;
    final local = box.globalToLocal(global);
    return Offset(local.dx / box.size.width, local.dy / box.size.height);
  }

  Offset _clamped(Offset global) {
    final p = _point(global);
    return Offset(p.dx.clamp(0, 1), p.dy.clamp(0, 1));
  }

  void _beginDrag(int index, Offset global, {bool resize = false}) {
    _controller!.select(widget.pageIndex, index);
    _dragBounds = _controller!.page(widget.pageIndex).bubbles[index].bounds;
    _dragStart = _point(global);
    _resizing = resize || HardwareKeyboard.instance.isShiftPressed;
  }

  void _drag(int index, Offset global) {
    if (_dragBounds == null || _dragStart == null) {
      return;
    }
    _controller!.changeBounds(
        widget.pageIndex,
        index,
        editTranslationBounds(_dragBounds!, _point(global) - _dragStart!,
            resize: _resizing));
  }

  void _finishSelection() {
    final start = _start, end = _end;
    setState(() {
      _start = null;
      _end = null;
    });
    if (start == null || end == null) {
      return;
    }
    final rect = Rect.fromPoints(start, end);
    if (rect.width < .015 || rect.height < .015) {
      return;
    }
    _controller!.translate(crop: rect);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return widget.child;
    }
    final page = controller.page(widget.pageIndex);
    final active = controller.activeIndex == widget.pageIndex;
    return Stack(children: [
      widget.child,
      Positioned.fill(child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
          return const SizedBox();
        }
        return Stack(key: _surfaceKey, clipBehavior: Clip.hardEdge, children: [
          if (page.visible)
            for (var i = 0; i < page.bubbles.length; i++) _bubble(i, size),
          if (page.visible && controller.editing)
            for (var i = 0; i < page.bubbles.length; i++)
              ..._bubbleHandles(i, size),
          if (active && controller.selecting)
            Positioned.fill(
                child: MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    child: TranslationPointerArea(
                        key: const Key('translation-crop-surface'),
                        onStart: (d) => setState(() {
                              _start = _clamped(d.globalPosition);
                              _end = _start;
                            }),
                        onUpdate: (d) =>
                            setState(() => _end = _clamped(d.globalPosition)),
                        onEnd: (_) => _finishSelection(),
                        onCancel: () => setState(() {
                              _start = null;
                              _end = null;
                            }),
                        child: ColoredBox(
                            color: Colors.blue.withValues(alpha: .08))))),
          if (active && controller.selecting && _start != null && _end != null)
            Positioned.fromRect(
                rect: Rect.fromPoints(
                    Offset(_start!.dx * size.width, _start!.dy * size.height),
                    Offset(_end!.dx * size.width, _end!.dy * size.height)),
                child: IgnorePointer(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue, width: 2),
                            color: Colors.blue.withValues(alpha: .15))))),
        ]);
      })),
    ]);
  }

  Widget _bubble(int index, Size size) {
    final controller = _controller!;
    final bubble = controller.page(widget.pageIndex).bubbles[index];
    final r = bubble.bounds;
    final selected = controller.editing &&
        controller.activeIndex == widget.pageIndex &&
        controller.selectedBubble == index;
    final settings = translationStore.settings;
    return Positioned.fromRect(
        rect: Rect.fromLTWH(r.left * size.width, r.top * size.height,
            r.width * size.width, r.height * size.height),
        child: IgnorePointer(
            ignoring: !controller.editing,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: TranslationPointerArea(
                      key: Key('translation-bubble-$index'),
                      onTap: () => controller.select(widget.pageIndex, index),
                      onStart: (d) => _beginDrag(index, d.globalPosition),
                      onUpdate: (d) => _drag(index, d.globalPosition),
                      onEnd: (_) => _endDrag(),
                      onCancel: _endDrag,
                      child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: settings.opacity),
                              borderRadius: BorderRadius.circular(6),
                              border: selected ? Border.all(color: Colors.blue, width: 2) : null,
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 2)
                              ]),
                          child: Center(
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                      width: (r.width * size.width - 8)
                                          .clamp(12, double.infinity),
                                      child: Text(bubble.translated,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: const Color(0xff102019),
                                              fontSize: settings.fontSize,
                                              height: 1.25,
                                              decoration: TextDecoration.none)))))))),
            ])));
  }

  List<Widget> _bubbleHandles(int index, Size size) {
    final bubble = _controller!.page(widget.pageIndex).bubbles[index];
    final r = bubble.bounds;
    final mobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final extent =
        (mobile ? 32.0 : 24.0).clamp(0.0, size.shortestSide / 2).toDouble();
    Offset bounded(double x, double y) => Offset(
        x.clamp(0.0, size.width - extent).toDouble(),
        y.clamp(0.0, size.height - extent).toDouble());
    var move = bounded(r.left * size.width, r.top * size.height);
    var resize =
        bounded(r.right * size.width - extent, r.bottom * size.height - extent);
    // Tiny/edge bubbles still need two separate, reachable hit targets.
    if ((move & Size.square(extent)).overlaps(resize & Size.square(extent))) {
      move = Offset(
          (r.center.dx * size.width - extent)
              .clamp(0.0, size.width - extent * 2)
              .toDouble(),
          (r.center.dy * size.height - extent / 2)
              .clamp(0.0, size.height - extent)
              .toDouble());
      resize = move + Offset(extent, 0);
    }
    Widget handle(Offset position, bool resizing) => Positioned(
        left: position.dx,
        top: position.dy,
        width: extent,
        height: extent,
        child: MouseRegion(
            cursor: resizing
                ? SystemMouseCursors.resizeDownRight
                : SystemMouseCursors.move,
            child: Semantics(
                label: resizing ? '拖动缩放译文框' : '拖动移动译文框',
                child: TranslationPointerArea(
                    key: ValueKey(
                        'translation-${resizing ? 'resize' : 'move'}-corner-${widget.pageIndex}-$index'),
                    onTap: () => _controller!.select(widget.pageIndex, index),
                    onStart: (d) =>
                        _beginDrag(index, d.globalPosition, resize: resizing),
                    onUpdate: (d) => _drag(index, d.globalPosition),
                    onEnd: (_) => _endDrag(),
                    onCancel: _endDrag,
                    child: Center(
                        child: Container(
                            width: mobile ? 24 : 20,
                            height: mobile ? 24 : 20,
                            decoration: BoxDecoration(
                                color: const Color(0xff215947),
                                border: Border.all(color: Colors.white),
                                borderRadius: BorderRadius.circular(4)),
                            child: Icon(
                                resizing ? Icons.south_east : Icons.open_with,
                                size: mobile ? 18 : 15,
                                color: Colors.white)))))));
    return [handle(move, false), handle(resize, true)];
  }

  void _endDrag() {
    _dragBounds = null;
    _dragStart = null;
  }
}
