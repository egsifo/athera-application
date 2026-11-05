import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Original temporary vector mark: an orbit ring around an "A" whose crossbar
/// is a pulse line. Drawn in code, no assets.
class AtheraLogo extends StatefulWidget {
  const AtheraLogo({super.key, this.size = 96, this.animate = false});
  final double size;
  final bool animate;

  @override
  State<AtheraLogo> createState() => _AtheraLogoState();
}

class _AtheraLogoState extends State<AtheraLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (widget.animate && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ATHERA logo',
      image: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _LogoPainter(_c.value * 2 * math.pi),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.angle);
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round
      ..color = tint(AC.cyan, 0.9);
    // Open ring (270 degrees)
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.92), math.pi * 0.75, math.pi * 1.5, false, ring);

    // "A"
    final a = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AC.text;
    final top = Offset(c.dx, c.dy - r * 0.46);
    final left = Offset(c.dx - r * 0.38, c.dy + r * 0.40);
    final right = Offset(c.dx + r * 0.38, c.dy + r * 0.40);
    canvas.drawPath(Path()..moveTo(left.dx, left.dy)..lineTo(top.dx, top.dy)..lineTo(right.dx, right.dy), a);

    // Pulse crossbar
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AC.cyan;
    final y = c.dy + r * 0.12;
    final w = r * 0.30;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - w, y)
        ..lineTo(c.dx - w * 0.35, y)
        ..lineTo(c.dx - w * 0.15, y - r * 0.18)
        ..lineTo(c.dx + w * 0.10, y + r * 0.16)
        ..lineTo(c.dx + w * 0.30, y)
        ..lineTo(c.dx + w, y),
      p,
    );

    // Orbiting dot
    final o = Offset(c.dx + r * 0.92 * math.cos(angle - math.pi / 4), c.dy + r * 0.92 * math.sin(angle - math.pi / 4));
    canvas.drawCircle(o, size.width * 0.04, Paint()..color = AC.cyan);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.angle != angle;
}
