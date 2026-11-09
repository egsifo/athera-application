import 'package:flutter/material.dart';

import '../../ai/model_report.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

/// Honest evaluation card for the ATHERA risk model: every number comes from
/// `assets/ai/backtest.json`, produced by replaying the real model over a
/// held-out slice of SIMULATED data.
class ModelReportScreen extends StatefulWidget {
  const ModelReportScreen({super.key, this.loader});

  /// Test hook: replaces asset loading.
  final Future<ModelReport> Function()? loader;

  @override
  State<ModelReportScreen> createState() => _ModelReportScreenState();
}

class _ModelReportScreenState extends State<ModelReportScreen> {
  late final Future<ModelReport> _future = (widget.loader ?? ModelReport.load)();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model report card')),
      body: FutureBuilder<ModelReport>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingBox();
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(Sp.l),
              child: InfoBanner(
                'The model report could not be loaded: ${snap.error}',
                icon: Icons.error_outline_rounded,
                color: AC.red,
              ),
            );
          }
          return _Body(report: snap.data!);
        },
      ),
    );
  }
}

String _pct(double? v) => v == null ? 'n/a' : '${(v * 100).toStringAsFixed(1)}%';

class _Body extends StatefulWidget {
  const _Body({required this.report});
  final ModelReport report;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int _episode = 0;

  static const _names = ['Safe', 'Early warning', 'Critical'];
  static const _colors = [AC.green, AC.amber, AC.red];

  Widget _stat(String label, String value, {Color color = AC.text, String? note}) => Expanded(
        child: AtCard(
          padding: const EdgeInsets.all(Sp.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AC.textDim, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w600)),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note, style: const TextStyle(color: AC.textDim, fontSize: 11)),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final crit = r.perClass['CRITICAL'];
    final gain = r.gainOverBaseline * 100;
    return ListView(padding: const EdgeInsets.all(Sp.l), children: [
      if (r.isSimulated)
        const InfoBanner(
          'Evaluated on SIMULATED data, not on astronauts. This shows how the pipeline behaves, not that it is clinically valid.',
          icon: Icons.science_outlined,
          color: AC.amber,
        )
      else
        InfoBanner(
          'Evaluated on data supplied by the team (${r.source}). Not clinically validated.',
          icon: Icons.fact_check_outlined,
          color: AC.blue,
        ),
      const SizedBox(height: Sp.m),
      Text(
        'Predicts the worst state within the next ${r.horizonMinutes} minutes. Tested on the last ${r.holdoutRows} readings '
        '(${r.periodStart.substring(0, 10)} to ${r.periodEnd.substring(0, 10)}), which the model never saw during training.',
        style: const TextStyle(color: AC.textDim, height: 1.35),
      ),
      const SizedBox(height: Sp.m),
      Row(children: [
        _stat('Accuracy', _pct(r.accuracy), color: AC.cyan),
        const SizedBox(width: Sp.s),
        _stat('Naive baseline', _pct(r.baselineAccuracy), note: '"future = now"'),
      ]),
      const SizedBox(height: Sp.s),
      Row(children: [
        _stat('Critical recall', _pct(crit?.recall), color: AC.red, note: 'caught before it happened'),
        const SizedBox(width: Sp.s),
        _stat('Critical precision', _pct(crit?.precision), note: 'alarms that were real'),
      ]),
      const SizedBox(height: Sp.s),
      Text(
        'Gain over the baseline: ${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} points. '
        'Always compare against the baseline: accuracy alone flatters rare-event models.',
        style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
      ),
      const SectionHeader('Confusion matrix', subtitle: 'Rows: what really happened. Columns: what the model predicted.'),
      AtCard(child: _Confusion(report: r)),
      const SectionHeader('By class'),
      AtCard(
        child: Column(children: [
          for (var i = 0; i < r.classes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _colors[i], shape: BoxShape.circle)),
                const SizedBox(width: Sp.s),
                Expanded(child: Text(_names[i])),
                Text('n=${r.perClass[r.classes[i]]?.support ?? 0}   ', style: const TextStyle(color: AC.textDim, fontSize: 12)),
                Text('recall ${_pct(r.perClass[r.classes[i]]?.recall)}   precision ${_pct(r.perClass[r.classes[i]]?.precision)}',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
        ]),
      ),
      SectionHeader('Critical episodes',
          subtitle: '${r.episodeCount} distinct episodes in the test period (small sample)'),
      AtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Warned (any level) before onset: ${r.episodesWarned} of ${r.episodeCount}'),
          const SizedBox(height: 4),
          Text('Warned "critical" before onset: ${r.episodesWarnedCritical} of ${r.episodeCount}'),
          const SizedBox(height: 4),
          Text(r.medianLeadMinutes == null
              ? 'Median lead time: n/a'
              : 'Median lead time: ${r.medianLeadMinutes!.toStringAsFixed(0)} min (measured up to the ${r.horizonMinutes} min horizon)'),
          const SizedBox(height: 4),
          Text('Critical alarms raised: ${r.criticalAlarms}, of which confirmed: ${r.criticalAlarmsConfirmed}'),
        ]),
      ),
      const SectionHeader('Replay an episode', subtitle: 'Strips show what the model said versus what happened, 15 min per step.'),
      if (r.episodes.isEmpty)
        const EmptyState(icon: Icons.history_toggle_off_rounded, title: 'No critical episodes', message: 'Nothing to replay.')
      else ...[
        Wrap(spacing: Sp.s, children: [
          for (var i = 0; i < r.episodes.length; i++)
            ChoiceChip(
              label: Text(r.episodes[i].onset.substring(5, 16)),
              selected: i == _episode,
              onSelected: (_) => setState(() => _episode = i),
            ),
        ]),
        const SizedBox(height: Sp.m),
        _Replay(report: r, episode: r.episodes[_episode]),
      ],
      const SectionHeader('Limits, stated plainly'),
      AtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Limit(r.isSimulated
              ? 'The data is simulated. Real astronaut data was not available.'
              : 'The data comes from the team, not from a clinical trial.'),
          const _Limit('The "critical" label comes from simple rule thresholds, not from clinicians.'),
          _Limit('Only ${r.episodeCount} critical episodes exist in the test period, so recall has wide uncertainty.'),
          const _Limit('The model can be retrained on new data with the same schema; these numbers would then change.'),
          const _Limit('This is decision support. It is not a diagnosis and not a medical device.'),
        ]),
      ),
      const SizedBox(height: Sp.xl),
    ]);
  }
}

class _Limit extends StatelessWidget {
  const _Limit(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ', style: TextStyle(color: AC.textDim)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ]),
      );
}

class _Confusion extends StatelessWidget {
  const _Confusion({required this.report});
  final ModelReport report;

  @override
  Widget build(BuildContext context) {
    const names = ['Safe', 'Early', 'Critical'];
    const colors = [AC.green, AC.amber, AC.red];
    final maxV = report.confusion.expand((r) => r).fold<int>(1, (a, b) => b > a ? b : a);
    Widget cell(Widget child) => Expanded(child: Padding(padding: const EdgeInsets.all(2), child: child));
    return Column(children: [
      Row(children: [
        const SizedBox(width: 64),
        for (final n in names)
          cell(Center(child: Text(n, style: const TextStyle(color: AC.textDim, fontSize: 11)))),
      ]),
      for (var a = 0; a < 3; a++)
        Row(children: [
          SizedBox(width: 64, child: Text(names[a], style: const TextStyle(color: AC.textDim, fontSize: 11))),
          for (var p = 0; p < 3; p++)
            cell(Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint(a == p ? colors[a] : AC.blue, 0.08 + 0.5 * (report.confusion[a][p] / maxV)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${report.confusion[a][p]}', style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
        ]),
      const SizedBox(height: Sp.s),
      const Text('Actual = worst state that really occurred in the next 2 hours.',
          style: TextStyle(color: AC.textDim, fontSize: 11)),
    ]);
  }
}

class _Replay extends StatelessWidget {
  const _Replay({required this.report, required this.episode});
  final ModelReport report;
  final Episode episode;

  static const _before = 16; // 4 h before onset
  static const _after = 8;

  @override
  Widget build(BuildContext context) {
    final s = report.series;
    final at = s.indexOf(episode.onset);
    if (at < 0) {
      return const InfoBanner('This episode is outside the replay window.', icon: Icons.info_outline_rounded);
    }
    final from = (at - _before).clamp(0, s.length - 1);
    final to = (at + _after).clamp(0, s.length - 1);
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Onset ${episode.onset.substring(0, 16)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          episode.leadAnyMin == null
              ? 'No earlier warning from the model for this episode.'
              : 'First warning ${episode.leadAnyMin} min before onset'
                  '${episode.leadCriticalMin == null ? '' : ', critical call ${episode.leadCriticalMin} min before'}.',
          style: const TextStyle(color: AC.textDim, fontSize: 12),
        ),
        const SizedBox(height: Sp.m),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: _ReplayPainter(s, from, to, at)),
        ),
        const SizedBox(height: Sp.s),
        const Wrap(spacing: Sp.m, children: [
          _Key('Now (rule)'),
          _Key('Model prediction'),
          _Key('What happened next'),
        ]),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(color: AC.textDim, fontSize: 11));
}

class _ReplayPainter extends CustomPainter {
  _ReplayPainter(this.s, this.from, this.to, this.onset);
  final ReportSeries s;
  final int from, to, onset;

  static const _colors = [AC.green, AC.amber, AC.red];

  @override
  void paint(Canvas canvas, Size size) {
    final n = to - from + 1;
    if (n <= 0) return;
    final w = size.width / n;
    const stripH = 22.0, gap = 6.0;
    final rows = [s.now, s.pred, s.actual];
    for (var r = 0; r < rows.length; r++) {
      for (var i = 0; i < n; i++) {
        final v = rows[r][from + i].clamp(0, 2);
        final rect = Rect.fromLTWH(i * w + 0.5, r * (stripH + gap), w - 1, stripH);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = tint(_colors[v], 0.85));
      }
    }
    // Risk line (0..100) below the strips.
    final top = 3 * (stripH + gap) + 4;
    final h = size.height - top;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = i * w + w / 2;
      final y = top + h * (1 - (s.risk[from + i].clamp(0, 100)) / 100);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AC.predicted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Onset marker.
    final ox = (onset - from) * w + w / 2;
    canvas.drawLine(Offset(ox, 0), Offset(ox, size.height), Paint()..color = tint(AC.text, 0.7)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter old) => old.from != from || old.to != to || old.s != s;
}
