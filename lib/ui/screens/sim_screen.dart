import 'dart:async';

import 'package:flutter/material.dart';

import '../../sim/emergency_sim.dart';

/// Mission Emergency Simulator screen. Every number shown is simulated.
class SimScreen extends StatefulWidget {
  const SimScreen({super.key});
  @override
  State<SimScreen> createState() => _SimScreenState();
}

class _SimScreenState extends State<SimScreen> {
  SimScenario _scenario = SimScenario.hypoxia;
  late SimEngine _engine = SimEngine(_scenario);
  Timer? _timer;
  bool _running = false;
  int _speed = 1;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(SimScenario s) {
    _timer?.cancel();
    setState(() {
      _scenario = s;
      _engine = SimEngine(s);
      _running = false;
    });
  }

  void _start() {
    _timer?.cancel();
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      var more = true;
      for (var i = 0; i < _speed && more; i++) {
        more = _engine.step();
      }
      if (!more) {
        _timer?.cancel();
        _running = false;
      }
      if (mounted) setState(() {});
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _reset() => _pick(_scenario);

  static Color _sev(int s) => switch (s) {
        3 => const Color(0xFFE5484D),
        2 => const Color(0xFFF76B15),
        1 => const Color(0xFFFFB224),
        _ => const Color(0xFF8B8D98),
      };

  @override
  Widget build(BuildContext context) {
    final s = _engine.now;
    final eta = _engine.history.length > 20 ? _engine.spo2SecondsTo(90) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Mission emergency simulator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('SIMULATION. All values are generated for training and demonstration. They are not clinical or orbital data, and no alert here is a diagnosis.'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SimScenario>(
            initialValue: _scenario,
            decoration: const InputDecoration(labelText: 'Scenario', border: OutlineInputBorder()),
            items: [for (final v in SimScenario.values) DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : _pick(v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _engine.done ? null : (_running ? _pause : _start),
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                label: Text(_running ? 'Pause' : (_engine.history.isEmpty ? 'Start' : 'Resume')),
              ),
              OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('Reset')),
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 1, label: Text('1x')), ButtonSegment(value: 4, label: Text('4x')), ButtonSegment(value: 10, label: Text('10x'))],
                selected: {_speed},
                onSelectionChanged: (v) => setState(() => _speed = v.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: s == null ? 0 : (s.t + 1) / _scenario.durationSeconds),
          if (s != null) ...[
            const SizedBox(height: 12),
            Text('t = ${s.t} s', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Heart rate', '${s.hr.round()} bpm'),
              _chip('SpO₂', '${s.spo2.toStringAsFixed(1)} %'),
              _chip('Resp.', '${s.rr.round()} /min'),
              _chip('Temp.', '${s.temp.toStringAsFixed(1)} °C'),
              _chip('Dose rate', '${s.doseRate.toStringAsFixed(0)} µGy/h'),
              _chip('Absorbed dose', '${s.cumDoseUGy.toStringAsFixed(1)} µGy'),
            ]),
            if (eta != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('If the current SpO₂ trend continues, it would reach 90% in about ${eta.round()} s. A simple extrapolation, not a validated prediction.')),
            if (_scenario.isNav) ...[
              const SizedBox(height: 12),
              _NavPanel(engine: _engine),
            ],
          ],
          const SizedBox(height: 16),
          Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_engine.events.isEmpty) const Text('Press Start.'),
          for (final e in _engine.events.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 6, backgroundColor: _sev(e.severity)),
              title: Text('${e.t} s  ${e.title}'),
              subtitle: Text(e.detail),
            ),
          if (_engine.done) ...[
            const SizedBox(height: 16),
            Text('Scenario report', style: Theme.of(context).textTheme.titleMedium),
            for (final l in _engine.report().lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String k, String v) => Chip(label: Text('$k  $v'));
}

class _NavPanel extends StatelessWidget {
  const _NavPanel({required this.engine});
  final SimEngine engine;

  @override
  Widget build(BuildContext context) {
    final s = engine.now!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Position relative to the spacecraft (SIMULATED)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1.4,
            child: CustomPaint(painter: _MapPainter(engine, Theme.of(context).colorScheme)),
          ),
          const SizedBox(height: 8),
          if (s.navSigma == null)
            const Text('Navigation unavailable. Follow approved mission emergency procedures and contact mission support. The last known position stays on the map; no route is shown.')
          else
            Text('Distance ${s.distance.toStringAsFixed(1)} m, position uncertainty about ±${s.navSigma!.toStringAsFixed(1)} m. Link ${s.commOk ? 'up' : 'down'}.'),
        ]),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.e, this.cs);
  final SimEngine e;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const range = 55.0; // metres shown from centre to edge
    final k = (size.shortestSide / 2) / range;
    final ring = Paint()
      ..color = cs.outlineVariant
      ..style = PaintingStyle.stroke;
    for (final r in [10.0, 30.0, 50.0]) {
      canvas.drawCircle(c, r * k, ring);
    }
    canvas.drawCircle(c, 6, Paint()..color = cs.primary);
    final path = Path();
    var first = true;
    SimSnapshot? lastFix;
    for (final h in e.history) {
      final p = c + Offset(h.x * k, -h.y * k);
      if (first) {
        path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
      }
      if (h.navSigma != null) lastFix = h;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = cs.secondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final cur = e.now!;
    if (lastFix != null && cur.navSigma == null) {
      final lp = c + Offset(lastFix.x * k, -lastFix.y * k);
      canvas.drawCircle(lp, 7, Paint()..color = const Color(0xFFF76B15));
    } else {
      final p = c + Offset(cur.x * k, -cur.y * k);
      canvas.drawCircle(p, 6, Paint()..color = const Color(0xFFE5484D));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
