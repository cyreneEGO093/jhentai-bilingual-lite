// SPDX-License-Identifier: GPL-3.0-only
// Derivative addition replacing Syncfusion with Flutter's own canvas.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/gallery_stats.dart';

class NativeVisitChart extends StatefulWidget {
  final List<VisitStat> data;
  const NativeVisitChart({super.key, required this.data});
  @override
  State<NativeVisitChart> createState() => _NativeVisitChartState();
}

class _NativeVisitChartState extends State<NativeVisitChart> {
  int? _selected;
  @override
  Widget build(BuildContext context) {
    final index = _selected == null || widget.data.isEmpty
        ? null
        : _selected!.clamp(0, widget.data.length - 1);
    return Column(children: [
      Wrap(spacing: 16, children: [
        Text('● ${'visits'.tr}', style: const TextStyle(color: Colors.blue)),
        Text('● ${'imageAccesses'.tr}',
            style: const TextStyle(color: Colors.pink)),
      ]),
      Expanded(
          child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                    onTapDown: widget.data.isEmpty
                        ? null
                        : (d) => setState(() {
                              _selected = (((d.localPosition.dx - 40) /
                                          math.max(
                                              1, constraints.maxWidth - 80)) *
                                      (widget.data.length - 1))
                                  .round()
                                  .clamp(0, widget.data.length - 1);
                            }),
                    child: CustomPaint(
                      size: constraints.biggest,
                      painter: _VisitPainter(widget.data, index,
                          Theme.of(context).colorScheme.onSurface),
                    ),
                  ))),
      SizedBox(
          height: 34,
          child: Text(
              index == null || widget.data.isEmpty
                  ? '点击图表查看数值'
                  : '${widget.data[index].period}  ${'visits'.tr}: ${widget.data[index].visits}  ${'imageAccesses'.tr}: ${widget.data[index].hits}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11))),
    ]);
  }
}

class _VisitPainter extends CustomPainter {
  final List<VisitStat> data;
  final int? selected;
  final Color textColor;
  _VisitPainter(this.data, this.selected, this.textColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 90 || size.height < 40 || data.isEmpty) {
      return;
    }
    final plot = Rect.fromLTWH(40, 10, size.width - 80, size.height - 36);
    void label(String text, Offset at, Color color) {
      final painter = TextPainter(
          text:
              TextSpan(text: text, style: TextStyle(fontSize: 9, color: color)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: 80);
      painter.paint(canvas, at);
    }

    final maxVisits = math.max(1.0, data.map((d) => d.visits).reduce(math.max));
    final maxHits = math.max(1.0, data.map((d) => d.hits).reduce(math.max));
    for (var n = 0; n <= 4; n++) {
      final y = plot.bottom - plot.height * n / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y),
          Paint()..color = textColor.withValues(alpha: .15));
      label(_short(maxVisits * n / 4), Offset(0, y - 5), Colors.blue);
      label(
          _short(maxHits * n / 4), Offset(plot.right + 4, y - 5), Colors.pink);
    }
    void line(double Function(VisitStat) value, double maxValue, Color color) {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final point = Offset(
            plot.left + plot.width * i / math.max(1, data.length - 1),
            plot.bottom -
                value(data[i]).clamp(0, maxValue) / maxValue * plot.height);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        if (i == selected || data.length == 1) {
          canvas.drawCircle(point, 3, Paint()..color = color);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    line((d) => d.visits, maxVisits, Colors.blue);
    line((d) => d.hits, maxHits, Colors.pink);
    label(data.first.period, Offset(plot.left, plot.bottom + 6), textColor);
    if (data.length > 1) {
      label(data.last.period, Offset(plot.right - 30, plot.bottom + 6),
          textColor);
    }
  }

  String _short(double n) => n >= 1e6
      ? '${(n / 1e6).toStringAsFixed(1)}M'
      : n >= 1e3
          ? '${(n / 1e3).toStringAsFixed(1)}K'
          : n.toStringAsFixed(0);
  @override
  bool shouldRepaint(_VisitPainter old) =>
      old.data != data ||
      old.selected != selected ||
      old.textColor != textColor;
}
