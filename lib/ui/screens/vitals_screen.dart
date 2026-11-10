import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/stats.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../vital_format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class VitalsScreen extends StatelessWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final id = c.selected.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        RangeSelector(c: c),
        const SizedBox(height: Sp.m),
        if (!c.samples.hasAny(id))
          const AtCard(
            child: EmptyState(
              icon: Icons.sensors_off_rounded,
              title: 'No measurements yet',
              message: 'Connect a sensor, or turn on demo mode in Settings to see simulated data.',
            ),
          )
        else ...[
          for (final types in const [
            [VitalType.heartRate],
            [VitalType.spo2],
            [VitalType.temperature],
            [VitalType.respiratoryRate],
            [VitalType.systolic, VitalType.diastolic],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.m),
              child: VitalChartCard(c: c, astronautId: id, types: types),
            ),
          _EcgSection(c: c),
        ],
      ],
    );
  }
}

class RangeSelector extends StatelessWidget {
  const RangeSelector({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TimeRange>(
        showSelectedIcon: false,
        segments: [
          for (final r in TimeRange.values) ButtonSegment<TimeRange>(value: r, label: Text(r.label)),
        ],
        selected: {c.range},
        onSelectionChanged: (s) => c.setRange(s.first),
      ),
    );
  }
}

/// Chart + min/max/avg/latest + data-quality line for one vital (or the two
/// blood-pressure components). Reused by the crew member detail screen.
class VitalChartCard extends StatelessWidget {
  const VitalChartCard({super.key, required this.c, required this.astronautId, required this.types});
  final AppController c;
  final String astronautId;
  final List<VitalType> types;

  @override
  Widget build(BuildContext context) {
    final isBp = types.length == 2;
    final primary = types.first;
    final now = DateTime.now().toUtc();
    final window = c.range.duration;
    final start = now.subtract(window);

    final lines = <ChartLine>[];
    final summaries = <VitalType, Summary>{};
    for (var i = 0; i < types.length; i++) {
      final t = types[i];
      final s = c.samples.series(astronautId, t, within: window, now: now);
      summaries[t] = summarize(s);
      lines.add(ChartLine(s, i == 0 ? AC.cyan : AC.blue, label: isBp ? t.shortLabel : ''));
    }
    final q = assessQuality(c.samples, astronautId, primary, window, now: now);
    final simulated = c.samples.simulatedAstronauts.contains(astronautId);

    final (qText, qColor) = !q.hasData
        ? ('No valid data in this period', AC.textDim)
        : q.isPoor
            ? ('Poor data quality', AC.red)
            : q.isFair
                ? ('Some gaps or invalid readings', AC.amber)
                : ('Good data coverage', AC.green);

    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(isBp ? 'Blood pressure' : primary.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          if (simulated) const DemoBadge(label: 'DEMO', dense: true),
          const SizedBox(width: 4),
          const KindTag(DataKind.measured),
        ]),
        const SizedBox(height: Sp.s),
        if (isBp)
          const Row(children: [
            _Legend(color: AC.cyan, label: 'Systolic'),
            SizedBox(width: Sp.m),
            _Legend(color: AC.blue, label: 'Diastolic'),
          ]),
        const SizedBox(height: Sp.s),
        TimeSeriesChart(
          lines: lines,
          start: start,
          end: now,
          vital: primary,
          map: (v) => toDisplay(c, primary, v),
          unit: isBp ? 'mmHg' : unitOf(c, primary),
          decimals: isBp ? 0 : (usesFahrenheit(c, primary) ? 1 : primary.decimals),
          showLimits: !isBp,
        ),
        const SizedBox(height: Sp.s),
        for (final t in types)
          _StatsRow(c: c, type: t, summary: summaries[t]!, label: isBp ? t.shortLabel : null),
        const Divider(height: Sp.l),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: qColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              q.hasData
                  ? '$qText · coverage ${(q.coverage * 100).round()}%'
                      '${q.gapCount > 0 ? ' · ${q.gapCount} gap${q.gapCount == 1 ? '' : 's'} (longest ${fmtDuration(q.longestGap)})' : ''}'
                      '${q.invalidCount > 0 ? ' · ${q.invalidCount} invalid' : ''}'
                  : qText,
              style: TextStyle(color: qColor, fontSize: 12),
            ),
          ),
        ]),
        if (summaries[primary]!.latestAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Latest measurement at ${fmtTime(summaries[primary]!.latestAt!)}',
                style: const TextStyle(color: AC.textDim, fontSize: 11)),
          ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AC.textDim, fontSize: 12)),
      ]);
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.c, required this.type, required this.summary, this.label});
  final AppController c;
  final VitalType type;
  final Summary summary;
  final String? label;

  @override
  Widget build(BuildContext context) {
    Widget cell(String name, double? v, {bool strong = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: AC.textDim, fontSize: 11)),
            Text(valueText(c, type, v),
                style: TextStyle(
                    fontSize: strong ? 17 : 15,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: kTabular)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        if (label != null) SizedBox(width: 34, child: Text(label!, style: const TextStyle(color: AC.textDim, fontSize: 11))),
        cell('Latest', summary.latest, strong: true),
        cell('Min', summary.min),
        cell('Avg', summary.mean),
        cell('Max', summary.max),
      ]),
    );
  }
}

class _EcgSection extends StatelessWidget {
  const _EcgSection({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final wave = c.demoEcg;
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('ECG waveform', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          if (wave != null) const DemoBadge(label: 'DEMO · SIMULATED', dense: true),
        ]),
        const SizedBox(height: Sp.m),
        if (wave != null) ...[
          EcgView(samples: wave, height: 110),
          const SizedBox(height: Sp.s),
          const Text('A synthetic waveform generated from the simulated heart rate. It is not a real ECG and must not be used for rhythm analysis.',
              style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35)),
        ] else
          const Text(
            'No ECG samples available. This chart appears only when an ECG-capable device streams waveform data.',
            style: TextStyle(color: AC.textDim, fontSize: 13, height: 1.35),
          ),
      ]),
    );
  }
}
