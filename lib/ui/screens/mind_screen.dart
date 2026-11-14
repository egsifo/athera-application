import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../mind/mind_scenarios.dart';
import '../../state/wellness_state.dart';
import '../widgets/common.dart';
import '../widgets/wellbeing_card.dart';
import 'check_in_screen.dart';
import 'laila_screen.dart';

/// Astro Mind: mental well-being dashboard, history, alerts and the simulation center.
class MindScreen extends StatefulWidget {
  const MindScreen({super.key});
  @override
  State<MindScreen> createState() => _MindScreenState();
}

class _MindScreenState extends State<MindScreen> {
  int _range = 1; // 0: 7 days, 1: 30 days, 2: all

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WellnessState>();
    final a = w.wellbeing;
    final series = w.wellbeingSeries;
    final now = DateTime.now().toUtc();
    final cut = switch (_range) {
      0 => now.subtract(const Duration(days: 7)),
      1 => now.subtract(const Duration(days: 30)),
      _ => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    };
    final view = [for (final p in series) if (!p.$1.isBefore(cut)) p];
    final alerts = w.wellbeingAlerts;

    return Scaffold(
      appBar: AppBar(title: const Text('Astro Mind')),
      body: ListView(padding: const EdgeInsets.all(Sp.l), children: [
        if (w.simActive)
          InfoBanner('SIMULATION running: ${w.simScenario!.label}. ${w.simScenario!.note}',
              icon: Icons.science_outlined, color: AC.amber),
        if (w.urgentSupport)
          const Padding(
            padding: EdgeInsets.only(top: Sp.s),
            child: InfoBanner('URGENT HUMAN SUPPORT requested. Contact the mission medical officer or mission control now.',
                icon: Icons.priority_high_rounded, color: AC.red),
          ),
        const SizedBox(height: Sp.m),
        WellbeingCard(a: a),
        const SizedBox(height: Sp.m),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LailaScreen())),
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: const Text('Talk to Laila'),
            ),
          ),
          const SizedBox(width: Sp.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckInScreen())),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Daily check-in'),
            ),
          ),
        ]),
        const SizedBox(height: Sp.s),
        OutlinedButton.icon(
          onPressed: w.urgentSupport ? w.clearHumanSupport : w.requestHumanSupport,
          style: OutlinedButton.styleFrom(foregroundColor: AC.red, side: const BorderSide(color: AC.red)),
          icon: const Icon(Icons.support_agent_rounded, size: 18),
          label: Text(w.urgentSupport ? 'Cancel human-support request' : 'I need human support now'),
        ),
        const SectionHeader('Well-being over time', subtitle: 'Daily score from your check-ins (higher is better)'),
        Wrap(spacing: Sp.s, children: [
          for (final e in const ['7 days', '30 days', 'All'].asMap().entries)
            ChoiceChip(label: Text(e.value), selected: e.key == _range, onSelected: (_) => setState(() => _range = e.key)),
        ]),
        const SizedBox(height: Sp.s),
        AtCard(child: SizedBox(height: 190, child: _chart(view))),
        SectionHeader('Support alerts', subtitle: '${alerts.length} in your check-in history'),
        if (alerts.isEmpty)
          const AtCard(child: Text('No alerts. Support is only suggested when your own reports show it.', style: TextStyle(color: AC.textDim)))
        else
          for (final al in alerts.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s),
              child: AtCard(
                borderColor: tint(supportColor(al.level), 0.5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Pill(al.title, color: supportColor(al.level), dense: true),
                    const Spacer(),
                    Text(al.at.toIso8601String().substring(0, 10), style: const TextStyle(color: AC.textDim, fontSize: 12)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Why: ${al.reasons.join(', ')}', style: const TextStyle(fontSize: 13, height: 1.3)),
                  if (al.indicators.isNotEmpty)
                    Text('Low indicators: ${al.indicators.join(', ')}', style: const TextStyle(fontSize: 12, color: AC.textDim)),
                  const SizedBox(height: 4),
                  Text(al.action, style: TextStyle(fontSize: 12, color: supportColor(al.level), height: 1.3)),
                ]),
              ),
            ),
        const SectionHeader('Simulation center', subtitle: 'Watch the whole app react. All values are simulated.'),
        _SimCenter(w: w),
        const SizedBox(height: Sp.l),
        const Text(
          'Astro Mind summarises your own reports. It does not diagnose depression or any condition. '
          'A score is never the only reason for an alert. If you feel unsafe, contact a person immediately.',
          style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: Sp.xl),
      ]),
    );
  }

  Widget _chart(List<(DateTime, int)> v) {
    if (v.length < 2) return const Center(child: Text('Needs at least 2 check-ins.', style: TextStyle(color: AC.textDim)));
    final t0 = v.first.$1;
    return LineChart(LineChartData(
      minY: 0,
      maxY: 100,
      minX: 0,
      maxX: v.last.$1.difference(t0).inHours / 24.0,
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
        HorizontalRangeAnnotation(y1: 0, y2: 55, color: AC.amber.withAlpha(20)),
      ]),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, interval: 25, reservedSize: 28,
              getTitlesWidget: (y, m) => Text(y.toStringAsFixed(0), style: const TextStyle(color: AC.textDim, fontSize: 10))),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: (v.last.$1.difference(t0).inDays / 4).clamp(1, 1e9).toDouble(),
            getTitlesWidget: (x, m) => Text(t0.add(Duration(days: x.round())).toIso8601String().substring(5, 10),
                style: const TextStyle(color: AC.textDim, fontSize: 10)),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (final p in v) FlSpot(p.$1.difference(t0).inHours / 24.0, p.$2.toDouble())],
          color: AC.cyan,
          barWidth: 2,
          isCurved: false,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }
}

class _SimCenter extends StatelessWidget {
  const _SimCenter({required this.w});
  final WellnessState w;

  @override
  Widget build(BuildContext context) {
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
          for (final s in MindScenario.values)
            ChoiceChip(label: Text(s.label), selected: w.simScenario == s, onSelected: (_) => w.startSim(s)),
        ]),
        const SizedBox(height: Sp.m),
        if (!w.simActive)
          const Text('Pick a scenario. The dashboard, Home, guidance, insights and Laila all change with it. Reset returns to your real data.',
              style: TextStyle(color: AC.textDim, fontSize: 13, height: 1.35))
        else ...[
          Text('${w.simScenario!.label}: day ${w.simDay} of $kMindDays', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: w.simDay / kMindDays, minHeight: 6, backgroundColor: AC.surface2, color: AC.amber),
          const SizedBox(height: Sp.m),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: w.simRunning ? w.pauseSim : (w.simDay >= kMindDays ? () => w.startSim(w.simScenario!) : w.resumeSim),
              icon: Icon(w.simRunning ? Icons.pause_rounded : (w.simDay >= kMindDays ? Icons.replay_rounded : Icons.play_arrow_rounded), size: 18),
              label: Text(w.simRunning ? 'Pause' : (w.simDay >= kMindDays ? 'Replay' : 'Resume')),
            ),
            const SizedBox(width: Sp.s),
            OutlinedButton.icon(onPressed: w.resetSim, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: const Text('Reset')),
            const Spacer(),
            SegmentedButton<double>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 1, label: Text('1x')),
                ButtonSegment(value: 2, label: Text('2x')),
                ButtonSegment(value: 4, label: Text('4x')),
              ],
              selected: {w.simSpeed},
              onSelectionChanged: (s) => w.setSimSpeed(s.first),
            ),
          ]),
        ],
      ]),
    );
  }
}
