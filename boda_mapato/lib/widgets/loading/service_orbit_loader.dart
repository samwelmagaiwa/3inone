import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../service_art.dart';

/// How far along a wait with no known end looks, from the seconds it has lasted: it climbs quickly at first and slows towards 97%, so it
/// never claims to be finished before it is. (The whole thing disappears when the work is done.)
int orbitPercent(final double seconds) => (97 * (1 - math.exp(-math.max(0, seconds) / 2.5))).floor();

/// The loading ring of the app: the four services (shop and depot, rentals, salon, transport) turn round a ring in the colours of the
/// app, and the percentage is in the middle. Without a [progress] it is a wait of unknown length, so the percentage climbs towards 97%.
class ServiceOrbitLoader extends StatefulWidget {
  const ServiceOrbitLoader({super.key, this.message, this.progress, this.size = 210});

  /// What is being waited for ("Signing in..."), under the ring.
  final String? message;

  /// The real progress, 0 to 1, when it is known.
  final double? progress;

  final double size;

  @override
  State<ServiceOrbitLoader> createState() => _ServiceOrbitLoaderState();
}

class _ServiceOrbitLoaderState extends State<ServiceOrbitLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  final Stopwatch _clock = Stopwatch()..start();

  static const List<CustomPainter> _pictures = <CustomPainter>[BoxesArtPainter(), HouseArtPainter(), SalonArtPainter(), BikeArtPainter()];

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  /// The percentage shown: the real one when given, otherwise the climbing one.
  int get _percent => widget.progress != null ? (widget.progress!.clamp(0.0, 1.0) * 100).round() : orbitPercent(_clock.elapsedMilliseconds / 1000);

  @override
  Widget build(final BuildContext context) {
    final double size = widget.size.w;
    final double orbit = size * 0.38;
    final double disc = size * 0.25;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('orbit_loader'),
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _turn,
            builder: (final BuildContext context, final Widget? child) {
              final double angle = _turn.value * 2 * math.pi;
              final int percent = _percent;
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // the dark round plate with a cyan glow
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: <Color>[Color(0xEE0B3AA8), Color(0xF2061B4E)]),
                      boxShadow: <BoxShadow>[BoxShadow(color: const Color(0xFF22D3EE).withValues(alpha: 0.45), blurRadius: 28, spreadRadius: 2)],
                    ),
                  ),
                  // the ring the services turn on, with a bright arc running round it
                  Positioned.fill(child: CustomPaint(painter: _RingPainter(angle: angle, orbit: orbit, progress: percent / 100))),
                  // the four services, going round, always upright
                  for (int i = 0; i < _pictures.length; i++)
                    Transform.translate(
                      offset: Offset(math.cos(angle + i * math.pi / 2 - math.pi / 2) * orbit, math.sin(angle + i * math.pi / 2 - math.pi / 2) * orbit),
                      child: Container(
                        key: ValueKey<String>('orbit_item_$i'),
                        width: disc,
                        height: disc,
                        padding: EdgeInsets.all(disc * 0.08),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFF22D3EE), width: 2),
                          boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))],
                        ),
                        child: CustomPaint(painter: _pictures[i]),
                      ),
                    ),
                  // the percentage in the middle
                  Row(
                    key: const ValueKey<String>('orbit_percent'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text('$percent', style: TextStyle(color: Colors.white, fontSize: size * 0.2, fontWeight: FontWeight.w900, shadows: const <Shadow>[Shadow(color: Color(0xFF22D3EE), blurRadius: 12)])),
                      Text('%', style: TextStyle(color: const Color(0xFF7CE0F0), fontSize: size * 0.1, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.message != null && widget.message!.isNotEmpty) ...<Widget>[
          SizedBox(height: 14.h),
          Text(
            widget.message!,
            key: const ValueKey<String>('orbit_message'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w800, letterSpacing: 2.4, shadows: const <Shadow>[Shadow(color: Color(0xFF22D3EE), blurRadius: 10)]),
          ),
        ],
      ],
    );
  }
}

/// The ring under the turning services: a faint track, a bright arc running round it, and the progress curve round the percentage.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.angle, required this.orbit, required this.progress});

  final double angle;
  final double orbit;
  final double progress;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Offset c = size.center(Offset.zero);

    canvas.drawCircle(c, orbit, Paint()..color = Colors.white.withValues(alpha: 0.18)..style = PaintingStyle.stroke..strokeWidth = 3);

    // the bright arc running round the ring, a little faster than the services
    final Rect ring = Rect.fromCircle(center: c, radius: orbit);
    canvas.drawArc(
      ring,
      angle * 2,
      math.pi * 0.7,
      false,
      Paint()
        ..shader = const SweepGradient(colors: <Color>[Colors.transparent, Color(0xFF22D3EE), Color(0xFF4ADE80)], stops: <double>[0, 0.7, 1]).createShader(ring)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // the progress curve round the percentage
    final Rect inner = Rect.fromCircle(center: c, radius: size.width * 0.2);
    canvas.drawCircle(c, size.width * 0.2, Paint()..color = Colors.white.withValues(alpha: 0.12)..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawArc(
      inner,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant final _RingPainter old) => old.angle != angle || old.progress != progress;
}
