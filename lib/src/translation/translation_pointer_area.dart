// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// An explicit editing surface owns its pointer before the reader's custom
/// double-tap/scale recognizers can claim it. Outside these small controls the
/// reader continues to receive normal pan/zoom gestures.
class TranslationPointerArea extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onStart;
  final GestureDragUpdateCallback? onUpdate;
  final GestureDragEndCallback? onEnd;
  final VoidCallback? onCancel;
  const TranslationPointerArea(
      {super.key,
      required this.child,
      this.onTap,
      this.onStart,
      this.onUpdate,
      this.onEnd,
      this.onCancel});

  @override
  State<TranslationPointerArea> createState() => _TranslationPointerAreaState();
}

class _TranslationPointerAreaState extends State<TranslationPointerArea> {
  PointerDownEvent? _down;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new, (_) {}),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_down != null) {
              return;
            }
            _down = event;
            _dragging = false;
          },
          onPointerMove: (event) {
            final down = _down;
            if (down == null || event.pointer != down.pointer) {
              return;
            }
            final first = !_dragging;
            if (first && (event.position - down.position).distance < 6) {
              return;
            }
            if (first) {
              _dragging = true;
              widget.onStart?.call(DragStartDetails(
                  globalPosition: down.position,
                  localPosition: down.localPosition));
            }
            widget.onUpdate?.call(DragUpdateDetails(
                globalPosition: event.position,
                localPosition: event.localPosition,
                delta: first
                    ? event.localPosition - down.localPosition
                    : event.localDelta));
          },
          onPointerUp: (event) {
            if (event.pointer != _down?.pointer) {
              return;
            }
            final dragged = _dragging;
            _down = null;
            _dragging = false;
            if (dragged) {
              widget.onEnd?.call(DragEndDetails());
            } else {
              widget.onTap?.call();
            }
          },
          onPointerCancel: (event) {
            if (event.pointer != _down?.pointer) {
              return;
            }
            _down = null;
            _dragging = false;
            widget.onCancel?.call();
          },
          child: widget.child,
        ),
      );
}
