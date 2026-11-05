import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../analytics/sample_store.dart';
import '../../analytics/stats.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';

/// One line on a [TimeSeriesChart]. Dashed lines are used for PREDICTED data so
/// a forecast can never be mistaken for a measurement.
class ChartLine {
  const ChartLine(this.samples, this.color, {this.dashed = false, this.label = ''});
  final List<Sample> samples;
  final Color color;
  final bool dashed;
  final String label;
}

double _identity(double v) => v;

class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.lines,
    required this.start,
    required this.end,
    required this.vital,
    this.map = _identity,
    this.unit = '',
    this.height = 170,
    this.decimals = 0,
    this.showLimits = true,
  });

  final List<ChartLine> lines;
  final DateTime start;
  final DateTime end;
  final VitalType vital;
  final double Function(double) map;
  final String unit;
  final double height;
  final int decimals;
  final bool showLimits;

  @override
  Widget build(BuildContext context) {
    final shown = lines.where((l) => l.samples.isNotEmpty).toList();
    if (shown.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No data in this period', style: TextStyle(color: AC.textDim))),
      );
    }
    final startMs = start.toUtc().millisecondsSinceEpoch;
    double xOf(DateTime t) => (t.toUtc().millisecondsSinceEpoch - startMs) / 60000.0;
    final spanMin = math.max(1.0, xOf(end));
    final bucketMin = spanMin / 240.0;
    final gapMin = math.max(3.0 * vital.nominalIntervalSec / 60.0, bucketMin * 2.5);

    var lo = double.infinity, hi = -double.infinity, maxX = spanMin;
    final bars = <LineChartBarData>[];
    for (final l in shown) {
      final src = l.dashed ? l.samples : downsample(l.samples, 240);
      final spots = <FlSpot>[];
      DateTime? prev;
      for (final s in src) {
        final y = map(s.v);
        if (y < lo) lo = y;
        if (y > hi) hi = y;
        if (prev != null && s.t.difference(prev).inSeconds / 60.0 > gapMin) {
          spots.add(FlSpot.nullSpot); // visible break where data is missing
        }
        final x = xOf(s.t);
        if (x > maxX) maxX = x;
        spots.add(FlSpot(x, y));
        prev = s.t;
      }
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        color: l.color,
        barWidth: l.dashed ? 2.0 : 1.8,
        dashArray: l.dashed ? const [6, 4] : null,
        dotData: FlDotData(show: l.dashed || spots.length < 4),
      ));
    }
    final minPad = (map(vital.practicalDelta) - map(0)).abs();
    final pad = math.max((hi - lo) * 0.15, minPad);
    final minY = lo - pad;
    final maxY = hi + pad;

    final limits = <HorizontalLine>[];
    if (showLimits) {
      void addLimit(double v) {
        final y = map(v);
        if (y > minY && y < maxY) {
          limits.add(HorizontalLine(y: y, color: tint(AC.amber, 0.45), strokeWidth: 1, dashArray: const [3, 5]));
        }
      }

      if (vital.alertHigh < vital.validMax) addLimit(vital.alertHigh);
      addLimit(vital.alertLow);
    }

    final xInterval = math.max(1.0, (maxX / 4).roundToDouble());
    const axisStyle = TextStyle(color: AC.textDim, fontSize: 10);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: bars,
          extraLinesData: ExtraLinesData(horizontalLines: limits),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: tint(AC.border, 0.8), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(decimals), style: axisStyle),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: xInterval,
                getTitlesWidget: (v, meta) {
                  final t = start.toUtc().add(Duration(seconds: (v * 60).round()));
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(fmtTime(t, seconds: false), style: axisStyle),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AC.surface2,
              getTooltipItems: (touched) => [
                for (final s in touched)
                  LineTooltipItem(
                    '${fmtTime(start.toUtc().add(Duration(seconds: (s.x * 60).round())))}\n'
                    '${s.y.toStringAsFixed(decimals)} $unit'
                    '${shown[s.barIndex].label.isEmpty ? '' : '  ${shown[s.barIndex].label}'}',
                    TextStyle(color: shown[s.barIndex].color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny dependency-free trend line for cards (fast, no axes).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.samples, required this.color, this.height = 34});
  final List<Sample> samples;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ExcludeSemantics(child: CustomPaint(painter: _SparkPainter(samples, color))),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.samples, this.color);
  final List<Sample> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final pts = samples.length > 120 ? downsample(samples, 120) : samples;
    var lo = pts.first.v, hi = pts.first.v;
    for (final s in pts) {
      lo = math.min(lo, s.v);
      hi = math.max(hi, s.v);
    }
    final range = math.max(hi - lo, 1e-6);
    final t0 = pts.first.t.millisecondsSinceEpoch;
    final span = math.max(1, pts.last.t.millisecondsSinceEpoch - t0);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = (pts[i].t.millisecondsSinceEpoch - t0) / span * size.width;
      final y = size.height - 3 - ((pts[i].v - lo) / range) * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = tint(color, 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.samples != samples || old.color != color;
}

/// ECG waveform painter. Only used when waveform samples exist.
class EcgView extends StatelessWidget {
  const EcgView({super.key, required this.samples, this.height = 90});
  final List<double> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Semantics(
        label: 'ECG waveform',
        child: CustomPaint(painter: _EcgPainter(samples)),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter(this.samples);
  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = tint(AC.border, 0.7)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += size.width / 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (samples.length < 2) return;
    var lo = samples.first, hi = samples.first;
    for (final v in samples) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final range = math.max(hi - lo, 1e-6);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i / (samples.length - 1) * size.width;
      final y = size.height - 6 - ((samples[i] - lo) / range) * (size.height - 12);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = AC.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant _EcgPainter old) => old.samples != samples;
}

/// History of the model-defined risk index (0-100, not a probability).
class RiskHistoryChart extends StatelessWidget {
  const RiskHistoryChart({super.key, required this.items, this.height = 130});
  final List<RiskResult> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pts = items.where((r) => r.riskScore != null).toList()
      ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    if (pts.length < 2) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text(
            pts.isEmpty
                ? 'No risk scores yet. The model may not provide a score.'
                : 'One score so far. History appears after more assessments.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AC.textDim, fontSize: 13),
          ),
        ),
      );
    }
    final t0 = pts.first.generatedAt.millisecondsSinceEpoch;
    final spots = [
      for (final r in pts) FlSpot((r.generatedAt.millisecondsSinceEpoch - t0) / 60000.0, r.riskScore!.clamp(0, 100).toDouble()),
    ];
    const axisStyle = TextStyle(color: AC.textDim, fontSize: 10);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          minX: 0,
          maxX: math.max(1.0, spots.last.x),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(color: tint(AC.border, 0.8), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 25,
                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: axisStyle),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: AC.predicted,
              barWidth: 1.8,
              isCurved: false,
              dotData: FlDotData(show: spots.length < 25),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AC.surface2,
              getTooltipItems: (touched) => [
                for (final s in touched)
                  LineTooltipItem(
                    '${fmtTime(pts[s.spotIndex].generatedAt)}\nindex ${s.y.toStringAsFixed(0)}\n${pts[s.spotIndex].riskClass.label}',
                    const TextStyle(color: AC.predicted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple topology diagram. Nodes are crew members plus the base station;
/// edges come from the link service. Nothing is drawn unless a scan returned it.
class TopologyView extends StatelessWidget {
  const TopologyView({
    super.key,
    required this.crew,
    required this.links,
    required this.connected,
    this.onTapMember,
    this.height = 230,
  });

  final List<Astronaut> crew;
  final Map<String, CrewLink> links;
  final bool Function(String astronautId) connected;
  final void Function(String astronautId)? onTapMember;
  final double height;

  static const _baseId = 'base';

  Map<String, int> _depths() {
    final depth = <String, int>{_baseId: 0};
    for (var pass = 0; pass < 6; pass++) {
      for (final l in links.values) {
        final via = l.viaId;
        if (via != null && depth.containsKey(via) && !depth.containsKey(l.astronautId)) {
          depth[l.astronautId] = depth[via]! + 1;
        }
      }
    }
    return depth;
  }

  Map<String, Offset> _layout(Size size) {
    final depth = _depths();
    final byDepth = <int, List<String>>{};
    for (final a in crew) {
      if (!links.containsKey(a.id)) continue;
      byDepth.putIfAbsent(depth[a.id] ?? 1, () => []).add(a.id);
    }
    final maxDepth = byDepth.keys.isEmpty ? 1 : byDepth.keys.reduce(math.max);
    final pos = <String, Offset>{_baseId: Offset(size.width / 2, 28)};
    final rowH = (size.height - 70) / math.max(1, maxDepth);
    byDepth.forEach((d, ids) {
      for (var i = 0; i < ids.length; i++) {
        pos[ids[i]] = Offset(size.width * (i + 1) / (ids.length + 1), 28 + d * rowH);
      }
    });
    return pos;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, height);
      final pos = _layout(size);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTapMember == null
            ? null
            : (d) {
                String? hit;
                var best = 34.0;
                pos.forEach((id, p) {
                  final dist = (p - d.localPosition).distance;
                  if (id != _baseId && dist < best) {
                    best = dist;
                    hit = id;
                  }
                });
                if (hit != null) onTapMember!(hit!);
              },
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Semantics(
            label: 'Network diagram with ${links.length} crew links',
            child: CustomPaint(
              painter: _TopologyPainter(
                pos: pos,
                crew: crew,
                links: links,
                connected: {for (final a in crew) a.id: connected(a.id)},
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _TopologyPainter extends CustomPainter {
  _TopologyPainter({required this.pos, required this.crew, required this.links, required this.connected});
  final Map<String, Offset> pos;
  final List<Astronaut> crew;
  final Map<String, CrewLink> links;
  final Map<String, bool> connected;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * e, paint);
      d += dash + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Edges first
    for (final l in links.values) {
      final from = pos[l.viaId ?? 'base'];
      final to = pos[l.astronautId];
      if (from == null || to == null) continue;
      final alive = (connected[l.astronautId] ?? false);
      final p = Paint()
        ..strokeWidth = l.transport == LinkTransport.baseStation ? 2.4 : 1.8
        ..color = alive ? tint(AC.cyan, 0.75) : tint(AC.red, 0.55);
      switch (l.transport) {
        case LinkTransport.baseStation:
        case LinkTransport.bluetooth:
          canvas.drawLine(from, to, p);
        case LinkTransport.localNetwork:
          _dashed(canvas, from, to, p, 2, 4);
        case LinkTransport.meshRelay:
          _dashed(canvas, from, to, p, 8, 5);
      }
    }
    // Base station node
    final basePos = pos['base'];
    if (basePos != null) {
      final r = Rect.fromCenter(center: basePos, width: 30, height: 30);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..color = AC.surface2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AC.blue,
      );
      _label(canvas, 'BASE', basePos + const Offset(0, 24), AC.textDim);
    }
    // Crew nodes
    for (final a in crew) {
      final p = pos[a.id];
      if (p == null) continue;
      final ok = connected[a.id] ?? false;
      final color = ok ? AC.cyan : AC.red;
      canvas.drawCircle(p, 15, Paint()..color = AC.surface2);
      canvas.drawCircle(
        p,
        15,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
      _label(canvas, a.callsign.isEmpty ? '?' : a.callsign.substring(0, 1), p + const Offset(0, -6), AC.text, size: 12);
      _label(canvas, a.callsign, p + const Offset(0, 22), AC.textDim);
    }
  }

  void _label(Canvas canvas, String text, Offset center, Color color, {double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter old) => true;
}
