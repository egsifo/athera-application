import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../wellness/body_systems.dart';
import '../../wellness/vital_status.dart';

Color statusColor(VStatus s) => switch (s) {
      VStatus.none => AC.textDim,
      VStatus.ok => AC.green,
      VStatus.watch => AC.amber,
      VStatus.critical => AC.red,
    };

String statusWord(VStatus s) => switch (s) {
      VStatus.none => 'No data',
      VStatus.ok => 'In range',
      VStatus.watch => 'Watch',
      VStatus.critical => 'Check now',
    };

IconData systemIcon(String id) => switch (id) {
      'mind' => Icons.psychology_alt_outlined,
      'heart' => Icons.favorite_border_rounded,
      'lungs' => Icons.air_rounded,
      'body' => Icons.thermostat_rounded,
      'muscle' => Icons.fitness_center_rounded,
      _ => Icons.circle_outlined,
    };

/// Tappable human figure. Each hotspot shows a body system and its status
/// colour; tapping opens details. The status comes from [statusOf].
class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.statusOf, required this.onSelect});
  final VStatus Function(BodySystem) statusOf;
  final void Function(BodySystem) onSelect;

  // Hotspot centres as fractions of the figure box (x, y).
  static const _spots = <String, Offset>{
    'mind': Offset(0.50, 0.085),
    'lungs': Offset(0.39, 0.27),
    'heart': Offset(0.62, 0.33),
    'body': Offset(0.50, 0.50),
    'muscle': Offset(0.40, 0.76),
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.62,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _FigurePainter())),
            for (final s in kBodySystems)
              if (_spots[s.id] != null)
                Positioned(
                  left: _spots[s.id]!.dx * w - 28,
                  top: _spots[s.id]!.dy * h - 28,
                  width: 56,
                  height: 56,
                  child: _Hotspot(system: s, status: statusOf(s), onTap: () => onSelect(s)),
                ),
          ]);
        }),
      ),
    );
  }
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({required this.system, required this.status, required this.onTap});
  final BodySystem system;
  final VStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Semantics(
      button: true,
      label: '${system.name}: ${statusWord(status)}. Tap for details.',
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint(color, 0.18),
              border: Border.all(color: color, width: 1.6),
            ),
            child: Icon(systemIcon(system.id), color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()
      ..color = tint(AC.blue, 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tint(AC.blue, 0.06);
    Offset p(double x, double y) => Offset(x * s.width, y * s.height);

    // Head and neck
    final head = Rect.fromCenter(center: p(0.5, 0.085), width: s.width * 0.20, height: s.height * 0.115);
    canvas.drawOval(head, fill);
    canvas.drawOval(head, line);
    canvas.drawLine(p(0.5, 0.145), p(0.5, 0.175), line);

    // Torso
    final torso = Path()
      ..moveTo(p(0.30, 0.19).dx, p(0.30, 0.19).dy)
      ..quadraticBezierTo(p(0.50, 0.165).dx, p(0.50, 0.165).dy, p(0.70, 0.19).dx, p(0.70, 0.19).dy)
      ..lineTo(p(0.66, 0.56).dx, p(0.66, 0.56).dy)
      ..quadraticBezierTo(p(0.50, 0.59).dx, p(0.50, 0.59).dy, p(0.34, 0.56).dx, p(0.34, 0.56).dy)
      ..close();
    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, line);

    // Arms
    for (final side in [-1.0, 1.0]) {
      final a = Path()
        ..moveTo(p(0.5 + side * 0.20, 0.20).dx, p(0.5 + side * 0.20, 0.20).dy)
        ..lineTo(p(0.5 + side * 0.31, 0.38).dx, p(0.5 + side * 0.31, 0.38).dy)
        ..lineTo(p(0.5 + side * 0.34, 0.54).dx, p(0.5 + side * 0.34, 0.54).dy);
      canvas.drawPath(a, line);
    }

    // Legs
    for (final side in [-1.0, 1.0]) {
      final l = Path()
        ..moveTo(p(0.5 + side * 0.13, 0.575).dx, p(0.5 + side * 0.13, 0.575).dy)
        ..lineTo(p(0.5 + side * 0.15, 0.78).dx, p(0.5 + side * 0.15, 0.78).dy)
        ..lineTo(p(0.5 + side * 0.13, 0.97).dx, p(0.5 + side * 0.13, 0.97).dy);
      canvas.drawPath(l, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
