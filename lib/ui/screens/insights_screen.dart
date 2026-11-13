import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../insights/anomaly.dart';
import '../../insights/data_quality.dart';
import '../../insights/insights_report.dart';
import '../../insights/trends.dart';
import '../../state/app_controller.dart';
import '../../state/wellness_state.dart';
import '../widgets/common.dart';

/// Personal insights: data quality, deviations from the astronaut's own baseline,
/// trends, and a plain explanation of the AI result. Everything is computed on
/// the device from stored observations; with too little history it says so.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  static Color _qualityColor(QualityStatus s) => switch (s) {
        QualityStatus.reliable => AC.green,
        QualityStatus.limited => AC.amber,
        QualityStatus.insufficient => AC.red,
      };

  static Color _sevColor(AnomalySeverity s) => switch (s) {
        AnomalySeverity.normal => AC.green,
        AnomalySeverity.unusual => AC.amber,
        AnomalySeverity.attention => AC.red,
      };

  static String _sevText(AnomalySeverity s) => switch (s) {
        AnomalySeverity.normal => 'Normal for you',
        AnomalySeverity.unusual => 'Unusual for you',
        AnomalySeverity.attention => 'Needs attention',
      };

  static String _kindText(AnomalyKind k) => switch (k) {
        AnomalyKind.deviation => 'Deviation',
        AnomalyKind.persistent => 'Repeated change',
        AnomalyKind.multivariate => 'Several together',
      };

  InsightsReport _build(AppController c, WellnessState w) {
    final id = c.selected.id;
    final now = DateTime.now().toUtc();
    return InsightsReport.build(InsightsInput(
      now: now,
      vitals: {
        for (final t in VitalType.values)
          t: c.samples.series(id, t, within: const Duration(days: 7), now: now, usableOnly: false),
      },
      checkIns: w.checkIns,
      risk: c.aiOf(id).risk,
      simulated: c.isSimulated,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final w = context.watch<WellnessState>();
    final r = _build(c, w);
    return Scaffold(
      appBar: AppBar(title: const Text('Personal insights')),
      body: ListView(padding: const EdgeInsets.all(Sp.l), children: [
        if (r.simulated)
          const InfoBanner('Built from SIMULATED demo data. The method is real; the numbers are not an astronaut\'s.',
              icon: Icons.science_outlined, color: AC.amber),
        const SectionHeader('Data quality', subtitle: 'Can the analysis below be trusted right now?'),
        _QualityCard(q: r.quality),
        const SectionHeader('Compared with your own baseline',
            subtitle: 'Robust median and spread of your earlier observations. This is not a medical limit.'),
        if (r.checks.isEmpty)
          const EmptyState(
            icon: Icons.insights_rounded,
            title: 'No observations yet',
            message: 'Take a measurement or do a daily check-in to start learning your baseline.',
          )
        else
          AtCard(child: Column(children: [for (final ch in r.checks) _CheckRow(ch: ch)])),
        SectionHeader('Unusual patterns', subtitle: '${r.anomalies.length} found'),
        if (r.anomalies.isEmpty)
          const AtCard(
            child: Text('Nothing differs from your usual pattern right now. Indicators without enough history are not judged.',
                style: TextStyle(color: AC.textDim, height: 1.35)),
          )
        else
          for (final a in r.anomalies) _AnomalyCard(a: a, sevColor: _sevColor(a.severity), sevText: _sevText(a.severity), kind: _kindText(a.kind)),
        const SectionHeader('Trends', subtitle: 'From your daily check-ins'),
        if (r.trends.isEmpty)
          const AtCard(child: Text(TrendEngine.insufficientText, style: TextStyle(color: AC.textDim)))
        else
          for (final t in r.trends) _TrendRow(t: t),
        const SectionHeader('Why this AI result?'),
        _ExplainCard(e: r.explained),
        const SizedBox(height: Sp.m),
        const Text(
          'Personal deviations, medical threshold alerts, AI predictions and data-quality warnings are four different things and are kept apart. '
          'A deviation is not a diagnosis. Correlation is not causation.',
          style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: Sp.xl),
      ]),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.q});
  final QualityReport q;

  @override
  Widget build(BuildContext context) {
    final color = InsightsScreen._qualityColor(q.status);
    return AtCard(
      borderColor: tint(color, 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(q.headline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
          Pill('${q.score}/100', color: color),
        ]),
        const SizedBox(height: Sp.s),
        LinearProgressIndicator(value: q.score / 100, color: color, backgroundColor: AC.surface2, minHeight: 6),
        const SizedBox(height: Sp.s),
        Text(
          q.aiReliable ? 'AI analysis can be treated as reliable.' : 'AI analysis is less reliable until these are fixed:',
          style: const TextStyle(color: AC.textDim, fontSize: 13),
        ),
        for (final i in q.issues)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: AC.amber),
              const SizedBox(width: 6),
              Expanded(child: Text('${i.series}: ${i.message}', style: const TextStyle(fontSize: 13))),
            ]),
          ),
        if (q.issues.isEmpty) const Padding(padding: EdgeInsets.only(top: 4), child: Text('No problems found.', style: TextStyle(fontSize: 13))),
      ]),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.ch});
  final IndicatorCheck ch;

  @override
  Widget build(BuildContext context) {
    final i = ch.reading.indicator;
    final b = ch.baseline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              b == null
                  ? 'Not enough history yet (needs ${i.minObservations} observations)'
                  : 'Now ${ch.reading.current.toStringAsFixed(1)} ${i.unit} · your median ${b.median.toStringAsFixed(1)} · ${b.n} obs.',
              style: const TextStyle(color: AC.textDim, fontSize: 12),
            ),
          ]),
        ),
        if (b != null) Pill(InsightsScreen._sevText(ch.severity), color: InsightsScreen._sevColor(ch.severity), dense: true),
      ]),
    );
  }
}

class _AnomalyCard extends StatelessWidget {
  const _AnomalyCard({required this.a, required this.sevColor, required this.sevText, required this.kind});
  final Anomaly a;
  final Color sevColor;
  final String sevText, kind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        borderColor: tint(sevColor, 0.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(kind, color: AC.blue, dense: true),
            const SizedBox(width: Sp.s),
            Pill(sevText, color: sevColor, dense: true),
            const Spacer(),
            if (a.simulated) const Pill('DEMO', color: AC.amber, dense: true),
          ]),
          const SizedBox(height: Sp.s),
          Text(a.explanation, style: const TextStyle(height: 1.35)),
          const SizedBox(height: Sp.s),
          Text('What to do: ${a.action}', style: const TextStyle(color: AC.cyan, fontSize: 13, height: 1.35)),
          const SizedBox(height: Sp.s),
          Text(
            'Method: ${a.method}. Confidence ${(a.confidence * 100).round()}% (grows with history). '
            'Deviation: ${a.deviation.entries.map((e) => '${e.key} ${e.value >= 0 ? '+' : ''}${e.value.toStringAsFixed(1)}σ').join(', ')}.',
            style: const TextStyle(color: AC.textDim, fontSize: 11, height: 1.3),
          ),
        ]),
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.t});
  final TrendResult t;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (t.direction) {
      TrendDirection.improving => (Icons.trending_up_rounded, AC.green),
      TrendDirection.declining => (Icons.trending_down_rounded, AC.amber),
      TrendDirection.stable => (Icons.trending_flat_rounded, AC.blue),
      TrendDirection.insufficient => (Icons.hourglass_empty_rounded, AC.textDim),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(t.summary, style: const TextStyle(height: 1.35, fontSize: 13))),
        ]),
      ),
    );
  }
}

class _ExplainCard extends StatelessWidget {
  const _ExplainCard({required this.e});
  final ExplainedRisk? e;

  @override
  Widget build(BuildContext context) {
    if (e == null) {
      return const AtCard(
        child: Text('No AI result yet. Open Analytics and run an assessment; the reasons the model reports will appear here.',
            style: TextStyle(color: AC.textDim, height: 1.35)),
      );
    }
    final x = e!;
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(x.reliable ? 'Reasons reported by the model' : 'Reasons reported by the model (use with caution)',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: Sp.s),
        if (x.reasons.isEmpty)
          const Text('None reported.', style: TextStyle(color: AC.textDim))
        else
          for (final r in x.reasons)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $r', style: const TextStyle(height: 1.35))),
        for (final cv in x.caveats)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AC.amber),
              const SizedBox(width: 6),
              Expanded(child: Text(cv, style: const TextStyle(fontSize: 13, color: AC.textDim, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}
