import 'package:flutter/material.dart';

/// The four services of the app as small flat pictures: stacked boxes (shop and depot), a house (rentals), scissors and a comb (salon)
/// and a pikipiki with a bajaji (transport, see [TransportArt]). Used on the sign-in page and in the loading ring that turns around them.
// Each is drawn in a 100 x 100 box, flat, in the colours of its service.

abstract class ServiceArtPainter extends CustomPainter {
  const ServiceArtPainter();

  void art(final Canvas canvas);

  @override
  void paint(final Canvas canvas, final Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawOval(const Rect.fromLTWH(10, 86, 80, 8), Paint()..color = const Color(0xFF0A2E8A).withValues(alpha: 0.16));
    art(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}

Paint _fill(final Color c) => Paint()..color = c;
Paint _line(final Color c, final double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

/// Stacked boxes (the shop and depot, inventory).
class BoxesArtPainter extends ServiceArtPainter {
  const BoxesArtPainter();

  void _box(final Canvas canvas, final double x, final double y, final double s, final Color face, final Color top, final Color side) {
    canvas.drawRect(Rect.fromLTWH(x, y, s, s * 0.8), _fill(face));
    canvas.drawPath(Path()..moveTo(x, y)..lineTo(x + s * 0.25, y - s * 0.22)..lineTo(x + s * 1.25, y - s * 0.22)..lineTo(x + s, y)..close(), _fill(top));
    canvas.drawPath(Path()..moveTo(x + s, y)..lineTo(x + s * 1.25, y - s * 0.22)..lineTo(x + s * 1.25, y + s * 0.58)..lineTo(x + s, y + s * 0.8)..close(), _fill(side));
    canvas.drawLine(Offset(x + s * 0.5, y), Offset(x + s * 0.5, y + s * 0.8), _line(Colors.white.withValues(alpha: 0.45), 1.5));
  }

  @override
  void art(final Canvas canvas) {
    _box(canvas, 8, 56, 36, const Color(0xFF4B5563), const Color(0xFF6B7280), const Color(0xFF374151));
    _box(canvas, 52, 60, 34, const Color(0xFFF59E0B), const Color(0xFFFBBF24), const Color(0xFFD97706));
    _box(canvas, 30, 26, 34, const Color(0xFFF59E0B), const Color(0xFFFBBF24), const Color(0xFFD97706));
  }
}

/// A house with a blue roof (rentals).
class HouseArtPainter extends ServiceArtPainter {
  const HouseArtPainter();

  @override
  void art(final Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(20, 46, 60, 42), _fill(const Color(0xFFF3F4F6)));
    canvas.drawPath(Path()..moveTo(12, 48)..lineTo(50, 14)..lineTo(88, 48)..close(), _fill(const Color(0xFF1D4ED8)));
    canvas.drawPath(Path()..moveTo(50, 14)..lineTo(88, 48)..lineTo(76, 48)..lineTo(50, 24)..close(), _fill(const Color(0xFF1E3A8A)));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(43, 62, 14, 26), const Radius.circular(2)), _fill(const Color(0xFF1E3A8A)));
    canvas.drawRect(const Rect.fromLTWH(26, 56, 12, 12), _fill(const Color(0xFF60A5FA)));
    canvas.drawRect(const Rect.fromLTWH(62, 56, 12, 12), _fill(const Color(0xFF60A5FA)));
    canvas.drawRect(const Rect.fromLTWH(26, 56, 12, 12), _line(const Color(0xFF1E3A8A), 1.5));
    canvas.drawRect(const Rect.fromLTWH(62, 56, 12, 12), _line(const Color(0xFF1E3A8A), 1.5));
    canvas.drawRect(const Rect.fromLTWH(66, 20, 8, 16), _fill(const Color(0xFF9A3412)));
  }
}

/// Scissors and a comb (the salon).
class SalonArtPainter extends ServiceArtPainter {
  const SalonArtPainter();

  @override
  void art(final Canvas canvas) {
    const Color purple = Color(0xFF7C3AED);
    canvas.drawCircle(const Offset(24, 70), 11, _line(purple, 4));
    canvas.drawCircle(const Offset(46, 74), 11, _line(purple, 4));
    canvas.drawLine(const Offset(30, 61), const Offset(52, 14), _line(const Color(0xFF6B7280), 4));
    canvas.drawLine(const Offset(42, 64), const Offset(24, 16), _line(const Color(0xFF9CA3AF), 4));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(64, 14, 22, 70), const Radius.circular(4)), _fill(const Color(0xFF1E3A8A)));
    for (int i = 0; i < 7; i++) {
      canvas.drawRect(Rect.fromLTWH(64, 18 + i * 9.0, 8, 4), _fill(const Color(0xFF93C5FD)));
    }
  }
}

/// The pictures of transport the app uses: a bajaji (a tuk-tuk with its driver) and a pikipiki (a motorbike with its rider).
const String bajajiAsset = 'assets/images/bajaji.png';
const String pikipikiAsset = 'assets/images/pikipiki.png';

/// Transport: a pikipiki and a bajaji side by side, both facing right. It fills the room it is given (a little over twice as wide as it is
/// high) and sits on the bottom edge.
class TransportArt extends StatelessWidget {
  const TransportArt({super.key});

  /// How much wider than high each picture is.
  static const double _bajajiAspect = 338 / 209;
  static const double _pikipikiAspect = 145 / 126;

  /// The pikipiki is this much of the bajaji's height, and the two overlap by a tenth of the height.
  static const double _bikeShare = 0.88;
  static const double _overlap = 0.1;

  @override
  Widget build(final BuildContext context) {
    return LayoutBuilder(
      builder: (final BuildContext context, final BoxConstraints box) {
        const double across = _bajajiAspect + _bikeShare * _pikipikiAspect - _overlap;
        final double fit = box.maxWidth / across;
        final double bajajiH = box.maxHeight < fit ? box.maxHeight : fit;
        final double bikeH = bajajiH * _bikeShare;
        return SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              Positioned(right: 0, bottom: 0, height: bajajiH, width: bajajiH * _bajajiAspect, child: Image.asset(bajajiAsset, fit: BoxFit.contain, alignment: Alignment.bottomRight)),
              Positioned(left: 0, bottom: 0, height: bikeH, width: bikeH * _pikipikiAspect, child: Image.asset(pikipikiAsset, fit: BoxFit.contain, alignment: Alignment.bottomLeft)),
            ],
          ),
        );
      },
    );
  }
}
