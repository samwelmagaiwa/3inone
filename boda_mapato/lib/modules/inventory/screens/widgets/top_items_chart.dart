import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One bar: what it is called (a service or a product) and its figure.
class TopItem {
  const TopItem({required this.name, required this.value});

  final String name;
  final double value;
}

/// The colours of the bars, in order (blue, teal, green, mint, yellow, orange, red, pink) and of the trend line drawn through their tops.
const List<Color> kTopItemColors = <Color>[
  Color(0xFF007BFF),
  Color(0xFF17A2B8),
  Color(0xFF28A745),
  Color(0xFF20C997),
  Color(0xFFFFC107),
  Color(0xFFFD7E14),
  Color(0xFFDC3545),
  Color(0xFFE83E8C),
];
const Color kTopItemsTrend = Color(0xFF003580);

/// Short money: 11.5M, 120K, 950.
String shortAmount(final double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(v.abs() >= 100000 ? 0 : 1)}K';

  return v.round().toString();
}

/// Bars, one colour each, with their figure above in the same colour and a smooth trend line through their tops (white-ringed dots), on a
/// light grid: the chart the dashboards show for what earned most. The bars are the services (or goods) and [legend] says what the figure is.
class TopItemsChart extends StatelessWidget {
  const TopItemsChart({super.key, required this.items, required this.legend, required this.trendLabel, this.height = 300});

  final List<TopItem> items;

  /// What the bars are ("Sales (TSH)"), and the name of the line ("Trend line").
  final String legend;
  final String trendLabel;
  final double height;

  @override
  Widget build(final BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 6),
            child: Wrap(spacing: 18, runSpacing: 4, children: <Widget>[
              _key(kTopItemsTrend, trendLabel),
              _key(kTopItemColors.first, legend),
            ]),
          ),
          SizedBox(
            height: height,
            child: TweenAnimationBuilder<double>(
              key: ValueKey<String>(items.map((final TopItem i) => '${i.name}:${i.value}').join('|')),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (final BuildContext context, final double t, final Widget? _) => CustomPaint(
                key: const ValueKey<String>('top_items_chart'),
                size: Size.infinite,
                painter: _TopItemsPainter(items, t),
              ),
            ),
          ),
        ],
      );

  Widget _key(final Color color, final String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

class _TopItemsPainter extends CustomPainter {
  _TopItemsPainter(this.items, this.t);

  final List<TopItem> items;
  final double t;

  static double _niceCeil(final double v) {
    if (v <= 0) return 1;
    final double p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final double m in <double>[1, 2, 2.5, 5, 10]) {
      if (v <= m * p) return m * p;
    }

    return 10 * p;
  }

  @override
  void paint(final Canvas canvas, final Size size) {
    if (items.isEmpty) return;
    const double left = 44, right = 8, top = 26, bottom = 78;
    final double w = size.width - left - right;
    final double h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;

    final double dataMax = items.map((final TopItem i) => i.value).reduce(math.max);
    final double max = _niceCeil(dataMax * 1.12);
    final double step = max / 5;

    // grid and the figures down the side
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (int i = 0; i <= 5; i++) {
      final double y = top + h - h * (i / 5);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      _text(canvas, shortAmount(step * i), Offset(left - 6, y), const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600), align: _Align.right, middle: true);
    }

    final double slot = w / items.length;
    final double barW = math.min(slot * 0.56, 64);
    final List<Offset> tops = <Offset>[];

    for (int i = 0; i < items.length; i++) {
      final Color color = kTopItemColors[i % kTopItemColors.length];
      final double cx = left + slot * i + slot / 2;
      final double bh = h * (items[i].value / max) * t;
      final Rect rect = Rect.fromLTWH(cx - barW / 2, top + h - bh, barW, bh);
      canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), Paint()..color = color);
      tops.add(Offset(cx, rect.top));
    }

    // trend line through the tops, smooth
    if (tops.length > 1) {
      final Path path = Path()..moveTo(tops.first.dx, tops.first.dy);
      for (int i = 0; i < tops.length - 1; i++) {
        final Offset p0 = i == 0 ? tops[i] : tops[i - 1];
        final Offset p1 = tops[i];
        final Offset p2 = tops[i + 1];
        final Offset p3 = i + 2 < tops.length ? tops[i + 2] : tops[i + 1];
        final Offset c1 = p1 + (p2 - p0) / 6;
        final Offset c2 = p2 - (p3 - p1) / 6;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      }
      canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.28)..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round);
      canvas.drawPath(path, Paint()..color = kTopItemsTrend..style = PaintingStyle.stroke..strokeWidth = 3.2..strokeCap = StrokeCap.round);
    }
    for (final Offset p in tops) {
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = kTopItemsTrend);
    }

    // figures above, in the colour of the bar; names under, slanted
    for (int i = 0; i < items.length; i++) {
      final Color color = kTopItemColors[i % kTopItemColors.length];
      _text(canvas, shortAmount(items[i].value), Offset(tops[i].dx, tops[i].dy - 19), TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900), align: _Align.center, middle: false, lift: true);
      final String name = items[i].name.length > 16 ? '${items[i].name.substring(0, 15)}…' : items[i].name;
      canvas.save();
      canvas.translate(left + slot * i + slot / 2 + 4, top + h + 10);
      canvas.rotate(-math.pi / 4);
      _text(canvas, name.toUpperCase(), Offset.zero, const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800), align: _Align.right, middle: false);
      canvas.restore();
    }
  }

  void _text(final Canvas canvas, final String s, final Offset at, final TextStyle style, {required final _Align align, required final bool middle, final bool lift = false}) {
    final TextPainter tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    double dx = at.dx;
    if (align == _Align.center) dx -= tp.width / 2;
    if (align == _Align.right) dx -= tp.width;
    double dy = at.dy;
    if (middle) dy -= tp.height / 2;
    if (lift) dy -= tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(final _TopItemsPainter old) => old.t != t || old.items != items;
}

enum _Align { center, right }
