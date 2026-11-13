import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/real_data.dart';
import '../widgets/common.dart';

/// Real blood tests from the four Inspiration4 crew members (NASA OSDR).
class BloodScreen extends StatefulWidget {
  const BloodScreen({super.key, this.loader});
  final Future<BloodPanel> Function()? loader;

  @override
  State<BloodScreen> createState() => _BloodScreenState();
}

class _BloodScreenState extends State<BloodScreen> {
  late final Future<BloodPanel> _future = (widget.loader ?? BloodPanel.load)();
  String? _panel;
  String? _marker;

  static const _crewColors = [AC.cyan, AC.amber, AC.green, AC.predicted];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crew blood tests (real)')),
      body: FutureBuilder<BloodPanel>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingBox();
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: InfoBanner('The blood data could not be loaded: ${snap.error}',
                  icon: Icons.error_outline_rounded, color: AC.red),
            );
          }
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(BloodPanel p) {
    final panels = p.markers.map((m) => m.panel).toSet().toList();
    final panel = _panel ?? panels.first;
    final list = p.markers.where((m) => m.panel == panel).toList();
    final cur = list.firstWhere((m) => m.id == _marker, orElse: () => list.first);
    final change = cur.changeAtLandingPct(p.timepoints);
    final crew = cur.values.keys.toList();

    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      InfoBanner(
        'MEASURED. ${p.source}. Only 4 people: this is descriptive, not statistical evidence, and the reference '
        'ranges are for the general population.',
        icon: Icons.bloodtype_outlined,
        color: AC.cyan,
      ),
      const SizedBox(height: Sp.m),
      Wrap(spacing: Sp.s, children: [
        for (final n in panels)
          ChoiceChip(
              label: Text(n),
              selected: n == panel,
              onSelected: (_) => setState(() {
                    _panel = n;
                    _marker = null;
                  })),
      ]),
      const SizedBox(height: Sp.m),
      DropdownButtonFormField<String>(
        initialValue: cur.id,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Marker'),
        items: [
          for (final m in list)
            DropdownMenuItem(
              value: m.id,
              child: Text(m.outOfRangeCount > 0 ? '${m.label}  (${m.outOfRangeCount} outside range)' : m.label,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _marker = v),
      ),
      SectionHeader(cur.label, subtitle: 'Unit: ${cur.unit}. ${p.timepointNote}'),
      AtCard(child: SizedBox(height: 230, child: _chart(p, cur))),
      const SizedBox(height: Sp.s),
      Wrap(spacing: Sp.m, children: [
        for (var i = 0; i < crew.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _crewColors[i % 4], shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(crew[i], style: const TextStyle(color: AC.textDim, fontSize: 12)),
          ]),
      ]),
      const SizedBox(height: Sp.m),
      AtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KeyValueRow('Reference range',
              cur.refMin == null && cur.refMax == null ? 'not provided' : '${cur.refMin ?? '…'} to ${cur.refMax ?? '…'} ${cur.unit}'),
          KeyValueRow('Change, 3 days before launch to day of return',
              change == null ? 'n/a' : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% (crew average)'),
          KeyValueRow('Values outside the reference range', '${cur.outOfRangeCount}'),
        ]),
      ),
      const SectionHeader('Limits'),
      AtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in p.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• ', style: TextStyle(color: AC.textDim)),
                Expanded(child: Text(n, style: const TextStyle(fontSize: 13, height: 1.35))),
              ]),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Text('• This is information, not a diagnosis.', style: TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      const SizedBox(height: Sp.xl),
    ]);
  }

  Widget _chart(BloodPanel p, BloodMarker m) {
    final vals = m.values.values.expand((l) => l).whereType<double>().toList();
    if (vals.isEmpty) return const Center(child: Text('No values.', style: TextStyle(color: AC.textDim)));
    var lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
    if (m.refMin != null && m.refMin! < lo) lo = m.refMin!;
    if (m.refMax != null && m.refMax! > hi) hi = m.refMax!;
    final pad = (hi - lo) == 0 ? 1.0 : (hi - lo) * 0.1;
    final crew = m.values.keys.toList();
    return LineChart(LineChartData(
      minX: 0,
      maxX: (p.timepoints.length - 1).toDouble(),
      minY: lo - pad,
      maxY: hi + pad,
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
        if (m.refMin != null && m.refMax != null)
          HorizontalRangeAnnotation(y1: m.refMin!, y2: m.refMax!, color: AC.green.withAlpha(25)),
      ]),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (y, meta) => Text(y.toStringAsFixed(y.abs() < 10 ? 1 : 0),
                style: const TextStyle(color: AC.textDim, fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 22,
            getTitlesWidget: (x, meta) {
              final i = x.round();
              return i < 0 || i >= p.timepoints.length
                  ? const SizedBox.shrink()
                  : Text(p.timepoints[i], style: const TextStyle(color: AC.textDim, fontSize: 9));
            },
          ),
        ),
      ),
      lineBarsData: [
        for (var c = 0; c < crew.length; c++)
          LineChartBarData(
            spots: [
              for (var i = 0; i < p.timepoints.length; i++)
                if (m.values[crew[c]]![i] != null) FlSpot(i.toDouble(), m.values[crew[c]]![i]!),
            ],
            color: _crewColors[c % 4],
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
      ],
    ));
  }
}
