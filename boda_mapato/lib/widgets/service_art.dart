import 'package:flutter/material.dart';

/// The four services of the app as small flat pictures: stacked boxes (shop and depot), a house (rentals), scissors and a comb (salon)
/// and a pikipiki with a bajaji (transport). Used on the sign-in page and in the loading ring that turns around them.
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

/// A pikipiki (motorbike) in a 100 x 100 box.
void _pikipiki(final Canvas canvas) {
  const Color dark = Color(0xFF111827);
    for (final Offset hub in const <Offset>[Offset(25, 70), Offset(77, 70)]) {
      canvas.drawCircle(hub, 15, _line(dark, 6));
      canvas.drawCircle(hub, 8, _line(const Color(0xFF9CA3AF), 2));
      canvas.drawCircle(hub, 3, _fill(const Color(0xFFE5E7EB)));
    }
    final Path frame = Path()
      ..moveTo(25, 70)
      ..lineTo(40, 52)
      ..lineTo(58, 50)
      ..lineTo(70, 56)
      ..lineTo(77, 70)
      ..moveTo(40, 52)
      ..lineTo(48, 70)
      ..lineTo(25, 70);
    canvas.drawPath(frame, _line(const Color(0xFFF59E0B), 6));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 44, 24, 8), const Radius.circular(3)), _fill(dark));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(52, 40, 18, 10), const Radius.circular(4)), _fill(const Color(0xFF1D4ED8)));
    canvas.drawLine(const Offset(70, 56), const Offset(68, 34), _line(dark, 4));
    canvas.drawLine(const Offset(62, 33), const Offset(77, 33), _line(dark, 4));
    canvas.drawCircle(const Offset(80, 42), 5, _fill(const Color(0xFFFCD34D)));
    canvas.drawLine(const Offset(40, 68), const Offset(8, 74), _line(const Color(0xFF9CA3AF), 4));
}

/// A bajaji (three-wheeler, the tuk-tuk) in a 132 x 100 scene, seen from the front-left: a light canopy on three pillars, a blue body, a
/// big windscreen, a headlight and bumper at the front, the passengers' windows along the side.
void _bajaji(final Canvas canvas) {
  const Color dark = Color(0xFF111827);
  const Color blue = Color(0xFF2563EB);
  const Color deep = Color(0xFF1D4ED8);
  const Color navy = Color(0xFF1E3A8A);
  const Color glass = Color(0xFFBFDBFE);

  // the rear wheel, then the body over it
  canvas.drawCircle(const Offset(120, 80), 10, _fill(dark));
  canvas.drawCircle(const Offset(120, 80), 4.5, _fill(const Color(0xFFE5E7EB)));
  final Path body = Path()
    ..moveTo(72, 70)
    ..quadraticBezierTo(72, 58, 80, 57)
    ..lineTo(124, 54)
    ..quadraticBezierTo(132, 54, 132, 64)
    ..lineTo(132, 78)
    ..lineTo(72, 78)
    ..close();
  canvas.drawPath(body, _fill(blue));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(98, 62, 32, 6), const Radius.circular(3)), _fill(deep));

  // the passengers' side windows with a person in each
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(103, 36, 26, 20), const Radius.circular(3)), _fill(glass));
  canvas.drawCircle(const Offset(112, 44), 3.5, _fill(navy));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(107, 47, 9, 9), const Radius.circular(2)), _fill(navy));
  canvas.drawCircle(const Offset(122, 44), 3.5, _fill(const Color(0xFF475569)));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(117, 47, 9, 9), const Radius.circular(2)), _fill(const Color(0xFF475569)));

  // the windscreen, with a bright streak across it
  final Path screen = Path()..moveTo(78, 38)..lineTo(100, 36)..lineTo(102, 56)..lineTo(76, 58)..close();
  canvas.drawPath(screen, _fill(glass));
  canvas.drawPath(Path()..moveTo(82, 38)..lineTo(90, 37.5)..lineTo(80, 57.5)..lineTo(77, 58)..close(), _fill(Colors.white.withValues(alpha: 0.55)));

  // the pillars and the canopy
  canvas.drawLine(const Offset(77, 38), const Offset(76, 58), _line(navy, 2.5));
  canvas.drawLine(const Offset(101, 36), const Offset(102, 56), _line(navy, 2.5));
  canvas.drawLine(const Offset(130, 36), const Offset(130, 54), _line(navy, 2.5));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(71, 28, 62, 11), const Radius.circular(8)), _fill(navy));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(71, 26, 62, 10), const Radius.circular(8)), _fill(const Color(0xFFE0ECFF)));

  // the front: headlight, bumper and the wheel
  canvas.drawCircle(const Offset(79, 67), 4.5, _fill(const Color(0xFFFEF3C7)));
  canvas.drawCircle(const Offset(79, 67), 2.5, _fill(const Color(0xFFFCD34D)));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(70, 74, 28, 4), const Radius.circular(2)), _fill(navy));
  canvas.drawCircle(const Offset(86, 80), 9, _fill(dark));
  canvas.drawCircle(const Offset(86, 80), 4, _fill(const Color(0xFFE5E7EB)));
}

/// The whole scene, 132 wide by 100 high: the pikipiki (facing left, as in the picture it follows) with the bajaji in front of its right side.
void _transportScene(final Canvas canvas) {
  canvas.save();
  canvas.translate(80.5, 17);
  canvas.scale(-0.85, 0.85);
  _pikipiki(canvas);
  canvas.restore();
  _bajaji(canvas);
}

/// The pikipiki and the bajaji, squeezed into a square (the loading ring).
class BikeArtPainter extends ServiceArtPainter {
  const BikeArtPainter();

  @override
  void art(final Canvas canvas) {
    canvas.save();
    canvas.translate(0, 14);
    canvas.scale(0.75);
    _transportScene(canvas);
    canvas.restore();
  }
}

/// The same scene at full size, for a picture that is wider than it is tall (the Transport tile on the sign-in page).
class TransportArtPainter extends CustomPainter {
  const TransportArtPainter();

  /// The shape it is drawn for: this wide for every 100 high.
  static const double aspect = 1.32;

  @override
  void paint(final Canvas canvas, final Size size) {
    final double scale = size.height / 100 < size.width / (100 * aspect) ? size.height / 100 : size.width / (100 * aspect);
    canvas.save();
    canvas.translate((size.width - 100 * aspect * scale) / 2, (size.height - 100 * scale) / 2);
    canvas.scale(scale);
    canvas.drawOval(Rect.fromLTWH(2, 86, 100 * aspect - 4, 8), Paint()..color = const Color(0xFF0A2E8A).withValues(alpha: 0.16));
    _transportScene(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}
