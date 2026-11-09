import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/insights.dart';
import '../../analytics/sample_store.dart';
import '../../analytics/stats.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../export_helper.dart';
import '../vital_format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'model_report_screen.dart';

/// "Analytics" tab: AI forecasts / risk (from the external service) and
/// descriptive insights (computed by the app). The two are kept visually and
/// verbally separate.
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.auto_awesome_outlined, size: 18), label: Text('AI forecast')),
              ButtonSegment(value: 1, icon: Icon(Icons.query_stats_rounded, size: 18), label: Text('Insights')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ),
        const SizedBox(height: Sp.m),
        if (_view == 0) _ForecastView(c: c) else _InsightsView(c: c),
      ],
    );
  }
}

// ===========================================================================
// AI forecast + risk
// ===========================================================================
class _ForecastView extends StatefulWidget {
  const _ForecastView({required this.c});
  final AppController c;

  @override
  State<_ForecastView> createState() => _ForecastViewState();
}

class _ForecastViewState extends State<_ForecastView> {
  VitalType _vital = VitalType.heartRate;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final id = c.selected.id;
    final snap = c.aiOf(id);
    final risk = snap.risk;
    final forecast = snap.forecast;
    final illustrative = (risk?.isMock ?? false) || (forecast?.isMock ?? false) || c.aiService.isIllustrative;
    final hasForecast = c.aiService.supportsForecast;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ConnectionCard(c: c, snap: snap),
      if (illustrative) ...[
        const SizedBox(height: Sp.m),
        const InfoBanner(
          'ILLUSTRATIVE RESULTS. These are scripted fixtures for the demo. They are not produced by a trained model and are not medical predictions.',
          icon: Icons.science_outlined,
        ),
      ],
      if (risk != null && risk.inputSimulated) ...[
        const SizedBox(height: Sp.m),
        const InfoBanner(
          'DEMO INPUT. The model received SIMULATED readings, so this result does not describe a real person.',
          icon: Icons.science_outlined,
          color: AC.amber,
        ),
      ],
      if (!hasForecast) ...[
        const SizedBox(height: Sp.m),
        const InfoBanner(
          'This model predicts the overall health state ahead of time. It does not forecast individual vital signs, so no forecast chart is shown.',
          icon: Icons.info_outline_rounded,
        ),
      ],
      if (snap.error != null) ...[
        const SizedBox(height: Sp.m),
        InfoBanner(
          '${snap.error!.headline}. ${snap.error!.message}'
          '${snap.hasResult ? ' Showing the last result below.' : ''} The rest of the app keeps working.',
          icon: Icons.cloud_off_rounded,
          color: AC.amber,
        ),
      ],
      if (hasForecast) ...[
        _horizon(c),
        const SectionHeader('Forecast vs measured', subtitle: 'Solid = measured · dashed violet = predicted'),
        _forecastChart(c, id, forecast),
      ],
      const SectionHeader('Risk assessment'),
      _RiskCard(risk: risk, snap: snap),
      if (risk != null && risk.warnings.isNotEmpty) ...[
        const SectionHeader('Model warnings', subtitle: 'Reported by the AI service'),
        for (final w in risk.warnings) _WarningTile(w),
      ],
      if (risk != null && risk.anomalies.isNotEmpty) ...[
        const SectionHeader('Anomalies detected by the model', subtitle: 'Statistical flags, not confirmed medical events'),
        for (final a in risk.anomalies) _AnomalyTile(a),
      ],
      const SectionHeader('Risk history'),
      _RiskHistory(c: c, id: id, version: snap.resultAt),
      const SizedBox(height: Sp.m),
      AtCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModelReportScreen())),
        child: const Row(children: [
          Icon(Icons.fact_check_outlined, color: AC.cyan),
          SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Model report card', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('How well the risk model did on data it never saw (simulated)',
                  style: TextStyle(color: AC.textDim, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AC.textDim),
        ]),
      ),
    ]);
  }

  Widget _horizon(AppController c) {
    final horizons = c.modelStatus?.supportedHorizonsSeconds ?? const <int>[];
    String label(int s) => s >= 3600 ? '${s ~/ 3600} h' : '${s ~/ 60} min';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Forecast horizon'),
      if (horizons.isEmpty)
        Text('${label(c.aiHorizonSec)} (the service did not list other horizons)',
            style: const TextStyle(color: AC.textDim, fontSize: 13))
      else
        Wrap(spacing: Sp.s, children: [
          for (final h in horizons)
            ChoiceChip(
              label: Text(label(h)),
              selected: c.aiHorizonSec == h,
              onSelected: (_) => c.setHorizon(h),
            ),
        ]),
    ]);
  }

  Widget _forecastChart(AppController c, String id, ForecastResult? f) {
    final now = DateTime.now().toUtc();
    const window = Duration(hours: 1);
    final start = now.subtract(window);
    final actual = c.samples.series(id, _vital, within: window, now: now);
    final predicted = <Sample>[];
    if (f != null) {
      for (final p in f.predictions) {
        final v = p.values[_vital];
        if (v != null) predicted.add(Sample(p.timestamp.toUtc(), v, DataQuality.good, f.generatedAt));
      }
    }
    final forecastable = VitalType.values.where((t) => t.isForecastable).toList();
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
          for (final t in forecastable)
            ChoiceChip(
              label: Text(t.shortLabel),
              selected: t == _vital,
              onSelected: (_) => setState(() => _vital = t),
            ),
        ]),
        const SizedBox(height: Sp.m),
        Row(children: [
          const _Legend(color: AC.cyan, label: 'Measured', dashed: false),
          const SizedBox(width: Sp.l),
          const _Legend(color: AC.predicted, label: 'Predicted', dashed: true),
          const Spacer(),
          const KindTag(DataKind.predicted),
        ]),
        const SizedBox(height: Sp.s),
        if (f == null)
          const SizedBox(
            height: 120,
            child: Center(
              child: Text('No forecast available yet.', style: TextStyle(color: AC.textDim)),
            ),
          )
        else ...[
          TimeSeriesChart(
            lines: [
              ChartLine(actual, AC.cyan, label: 'measured'),
              ChartLine(predicted, AC.predicted, dashed: true, label: 'PREDICTED'),
            ],
            start: start,
            end: now,
            vital: _vital,
            map: (v) => toDisplay(c, _vital, v),
            unit: unitOf(c, _vital),
            decimals: usesFahrenheit(c, _vital) ? 1 : _vital.decimals,
            showLimits: false,
          ),
          const SizedBox(height: Sp.s),
          Text(
            '${f.modelName} ${f.modelVersion} · horizon ${f.horizonSeconds ~/ 60} min · generated ${fmtTime(f.generatedAt)}'
            '${predicted.isEmpty ? '\nThe model returned no values for ${_vital.label.toLowerCase()}.' : ''}',
            style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
          ),
        ],
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.dashed});
  final Color color;
  final String label;
  final bool dashed;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        dashed
            ? Row(children: [for (var i = 0; i < 3; i++) Container(width: 4, height: 3, margin: const EdgeInsets.only(right: 2), color: color)])
            : Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AC.textDim, fontSize: 12)),
      ]);
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.c, required this.snap});
  final AppController c;
  final AiSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ms = c.modelStatus;
    final err = c.modelStatusError;
    final (label, color) = ms != null && err == null
        ? ('Connected', AC.green)
        : err != null
            ? ('Unavailable', AC.red)
            : ('Unknown', AC.textDim);
    final at = snap.resultAt;
    final stale = snap.isStale(DateTime.now());
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('AI service', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          Pill(label, color: color, icon: Icons.cloud_outlined),
        ]),
        const SizedBox(height: Sp.s),
        KeyValueRow('Source', c.aiService.name),
        if (ms != null) ...[
          KeyValueRow('Service version', ms.serviceVersion),
          KeyValueRow('Mode', ms.mode),
          if (ms.forecastModel != null) KeyValueRow('Forecast model', '${ms.forecastModel!.name} ${ms.forecastModel!.version}'),
          if (ms.riskModel != null) KeyValueRow('Risk model', '${ms.riskModel!.name} ${ms.riskModel!.version}'),
        ],
        KeyValueRow(
          'Last prediction',
          at == null ? 'none yet' : '${fmtTime(at)} · ${fmtAgo(at)}${stale ? ' (stale)' : ''}',
          valueColor: at == null || stale ? AC.amber : AC.text,
        ),
        if (err != null) KeyValueRow('Status', '${err.headline}', valueColor: AC.red),
        const SizedBox(height: Sp.s),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: snap.loading ? null : () => c.refreshAi(c.selected.id),
            icon: snap.loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(snap.loading ? 'Requesting…' : 'Refresh now'),
          ),
        ),
      ]),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.risk, required this.snap});
  final RiskResult? risk;
  final AiSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final r = risk;
    if (r == null) {
      return AtCard(
        child: EmptyState(
          icon: snap.error != null ? Icons.cloud_off_rounded : Icons.hourglass_empty_rounded,
          title: snap.error != null ? 'AI service unavailable' : 'No risk assessment yet',
          message: snap.error?.message ?? 'The first result appears after the forecast window has enough sensor data.',
        ),
      );
    }
    final color = riskColor(r.riskClass);
    final probs = r.classProbabilities;
    return AtCard(
      borderColor: tint(color, 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(riskIcon(r.riskClass), color: color, size: 28),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(r.riskClass.label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color))),
          const KindTag(DataKind.predicted),
        ]),
        const SizedBox(height: Sp.m),
        if (r.riskScore != null)
          KeyValueRow('Risk index', '${r.riskScore!.toStringAsFixed(0)} / 100 (model-defined; not a probability)')
        else
          const KeyValueRow('Risk index', 'not provided by the model'),
        if (r.currentClass != null) KeyValueRow('Now (model rule)', r.currentClass!.label),
        if (r.horizonMinutes != null)
          KeyValueRow('Predicted in', r.horizonMinutes! >= 60 && r.horizonMinutes! % 60 == 0 ? '${r.horizonMinutes! ~/ 60} h' : '${r.horizonMinutes} min'),
        KeyValueRow('Model', '${r.modelName} ${r.modelVersion}'),
        KeyValueRow('Generated', '${fmtDateTime(r.generatedAt)} · received ${fmtTime(r.receivedAt)}'),
        if (r.isMock) const KeyValueRow('Result type', 'ILLUSTRATIVE fixture', valueColor: AC.blue),
        if (r.status == ResultStatus.degraded) const KeyValueRow('Result type', 'Degraded (reduced inputs)', valueColor: AC.amber),
        if (probs != null && probs.isNotEmpty) ...[
          const SizedBox(height: Sp.m),
          const Text('Class probabilities reported by the model', style: TextStyle(color: AC.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          for (final e in probs.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 100, child: Text(e.key.label, style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value.clamp(0.0, 1.0),
                      minHeight: 8,
                      color: riskColor(e.key),
                      backgroundColor: AC.surface2,
                    ),
                  ),
                ),
                SizedBox(width: 48, child: Text('${(e.value * 100).toStringAsFixed(0)}%', textAlign: TextAlign.end)),
              ]),
            ),
        ],
        if (r.contributingFeatures.isNotEmpty) ...[
          const SizedBox(height: Sp.m),
          const Text('Contributing features (as reported)', style: TextStyle(color: AC.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          for (final f in r.contributingFeatures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  f.direction == 'increase'
                      ? Icons.arrow_upward_rounded
                      : f.direction == 'decrease'
                          ? Icons.arrow_downward_rounded
                          : Icons.remove_rounded,
                  size: 16,
                  color: AC.textDim,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${f.feature}${f.weight == null ? '' : '  (${f.weight!.toStringAsFixed(2)})'}'
                    '${f.description == null ? '' : '\n${f.description}'}',
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
              ]),
            ),
        ],
        const SizedBox(height: Sp.m),
        const Text(
          'A model classification is a screening signal. It is not a diagnosis.',
          style: TextStyle(color: AC.textDim, fontSize: 11),
        ),
      ]),
    );
  }
}

class _WarningTile extends StatelessWidget {
  const _WarningTile(this.w);
  final ModelWarning w;
  @override
  Widget build(BuildContext context) {
    final color = w.severity == 'critical' ? AC.red : (w.severity == 'warning' ? AC.amber : AC.blue);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        padding: const EdgeInsets.all(Sp.m),
        borderColor: tint(color, 0.4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: Sp.m),
          Expanded(child: Text(w.message, style: const TextStyle(fontSize: 13, height: 1.35))),
          Pill(w.code, color: color, dense: true),
        ]),
      ),
    );
  }
}

class _AnomalyTile extends StatelessWidget {
  const _AnomalyTile(this.a);
  final AnomalyReport a;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        padding: const EdgeInsets.all(Sp.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.bubble_chart_outlined, color: AC.predicted, size: 20),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.metric, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(a.description, style: const TextStyle(color: AC.textDim, fontSize: 13)),
              if (a.timestamp != null || a.score != null)
                Text(
                  [
                    if (a.timestamp != null) fmtTime(a.timestamp!),
                    if (a.score != null) 'score ${a.score!.toStringAsFixed(2)}',
                  ].join(' · '),
                  style: const TextStyle(color: AC.textDim, fontSize: 11),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RiskHistory extends StatefulWidget {
  const _RiskHistory({required this.c, required this.id, required this.version});
  final AppController c;
  final String id;
  final DateTime? version;

  @override
  State<_RiskHistory> createState() => _RiskHistoryState();
}

class _RiskHistoryState extends State<_RiskHistory> {
  late Future<List<RiskResult>> _future = widget.c.riskHistory(widget.id);

  @override
  void didUpdateWidget(covariant _RiskHistory old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.version != widget.version) {
      _future = widget.c.riskHistory(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RiskResult>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AtCard(child: SizedBox(height: 90, child: LoadingBox()));
        }
        if (snap.hasError) {
          return InfoBanner('Could not read stored risk history: ${snap.error}', icon: Icons.storage_rounded, color: AC.amber);
        }
        final items = snap.data ?? const <RiskResult>[];
        if (items.isEmpty) {
          return const AtCard(child: Text('No assessments stored yet.', style: TextStyle(color: AC.textDim)));
        }
        final counts = {for (final k in RiskClass.values) k: 0};
        for (final r in items) {
          counts[r.riskClass] = (counts[r.riskClass] ?? 0) + 1;
        }
        final anyMock = items.any((r) => r.isMock);
        return AtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Risk index over time', style: TextStyle(fontWeight: FontWeight.w600))),
              if (anyMock) const Pill('ILLUSTRATIVE', color: AC.blue, dense: true),
            ]),
            const SizedBox(height: Sp.s),
            RiskHistoryChart(items: items),
            const Divider(height: Sp.xl),
            const Text('Risk category distribution', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: Sp.s),
            for (final k in RiskClass.values)
              if ((counts[k] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 100, child: Text(k.label, style: const TextStyle(fontSize: 13))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: counts[k]! / items.length,
                          minHeight: 8,
                          color: riskColor(k),
                          backgroundColor: AC.surface2,
                        ),
                      ),
                    ),
                    SizedBox(width: 70, child: Text('${counts[k]} of ${items.length}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
                  ]),
                ),
          ]),
        );
      },
    );
  }
}

// ===========================================================================
// Insights (computed by the app, descriptive only)
// ===========================================================================
class _InsightsView extends StatefulWidget {
  const _InsightsView({required this.c});
  final AppController c;

  @override
  State<_InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<_InsightsView> {
  Duration _window = const Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final id = c.selected.id;
    final now = DateTime.now().toUtc();
    final windows = const {
      '15 min': Duration(minutes: 15),
      '1 h': Duration(hours: 1),
      '6 h': Duration(hours: 6),
      '24 h': Duration(hours: 24),
    };
    final insights = buildInsights(c.samples, id, _window, now: now);
    final rows = baselineRows(c.samples, id, _window, now: now);
    final corr = buildCorrelations(c.samples, id, now: now);
    final base = baselineFor(c.samples, id, _window, now: now);
    final anomalies = c.aiOf(id).risk?.anomalies ?? const <AnomalyReport>[];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const InfoBanner(
        'Calculated by the app from measured data. These are descriptions, not predictions and not diagnoses.',
        icon: Icons.calculate_outlined,
      ),
      const SizedBox(height: Sp.m),
      Wrap(spacing: Sp.s, children: [
        for (final e in windows.entries)
          ChoiceChip(label: Text(e.key), selected: _window == e.value, onSelected: (_) => setState(() => _window = e.value)),
      ]),
      const SectionHeader('Insights'),
      if (insights.isEmpty)
        AtCard(
          child: Text(
            base == null
                ? 'No notable changes detected. A personal baseline needs more than 6 h of stored data before the comparison window.'
                : 'No notable changes relative to the baseline in this window.',
            style: const TextStyle(color: AC.textDim, height: 1.4),
          ),
        )
      else
        for (final i in insights) _InsightTile(i),
      const SectionHeader('Change vs baseline',
          subtitle: 'Baseline = first 6 h of stored data for this astronaut'),
      AtCard(
        child: Column(children: [
          const _TableHead(['Vital', 'Baseline', 'Now', 'Δ', 'Rate/h']),
          const Divider(),
          for (final r in rows) _BaselineRowView(c: c, row: r),
        ]),
      ),
      if (base == null)
        const Padding(
          padding: EdgeInsets.only(top: Sp.s),
          child: Text('Baseline comparison unavailable: not enough history yet.', style: TextStyle(color: AC.textDim, fontSize: 12)),
        ),
      const SectionHeader('Associations', subtitle: 'Last 6 h · correlation is not causation'),
      if (corr.isEmpty)
        const AtCard(child: Text('Not enough overlapping data to compute associations.', style: TextStyle(color: AC.textDim)))
      else
        AtCard(
          child: Column(children: [
            for (final x in corr)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${x.a.shortLabel} ↔ ${x.b.shortLabel}')),
                  Text('r = ${x.r.toStringAsFixed(2)}', style: const TextStyle(fontFeatures: kTabular)),
                  const SizedBox(width: Sp.m),
                  SizedBox(width: 72, child: Text('${x.strength}, n=${x.n}', textAlign: TextAlign.end, style: const TextStyle(color: AC.textDim, fontSize: 12))),
                ]),
              ),
          ]),
        ),
      const SectionHeader('Data quality'),
      AtCard(
        child: Column(children: [
          const _TableHead(['Vital', 'Coverage', 'Gaps', 'Invalid', 'Delayed']),
          const Divider(),
          for (final t in VitalType.values) _QualityRowView(q: assessQuality(c.samples, id, t, _window, now: now)),
        ]),
      ),
      if (anomalies.isNotEmpty) ...[
        const SectionHeader('From the AI service', subtitle: 'Not computed by the app'),
        for (final a in anomalies) _AnomalyTile(a),
      ],
      const SectionHeader('Export'),
      AtCard(
        child: Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Measurements (24 h)'),
            onPressed: () async {
              final csv = await c.observationsCsvFor(id, const Duration(hours: 24));
              if (context.mounted) await shareCsv(context, 'athera_${c.selected.callsign}_observations.csv', csv);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Alerts'),
            onPressed: () async {
              final csv = await c.alertsCsvAll();
              if (context.mounted) await shareCsv(context, 'athera_alerts.csv', csv);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Emergencies'),
            onPressed: () async {
              final csv = await c.emergenciesCsvAll();
              if (context.mounted) await shareCsv(context, 'athera_emergencies.csv', csv);
            },
          ),
        ]),
      ),
      if (c.isSimulated)
        const Padding(
          padding: EdgeInsets.only(top: Sp.s),
          child: Text('Exports include an is_simulated column so demo data is never mistaken for measurements.',
              style: TextStyle(color: AC.textDim, fontSize: 12)),
        ),
    ]);
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile(this.i);
  final Insight i;
  @override
  Widget build(BuildContext context) {
    final color = i.severityHint > 0 ? AC.amber : (i.kind == InsightKind.dataQuality ? AC.blue : AC.cyan);
    final icon = switch (i.kind) {
      InsightKind.baselineChange => Icons.compare_arrows_rounded,
      InsightKind.rateOfChange => Icons.trending_up_rounded,
      InsightKind.dataQuality => Icons.rule_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        padding: const EdgeInsets.all(Sp.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(i.detail, style: const TextStyle(color: AC.textDim, fontSize: 13, height: 1.35)),
              const SizedBox(height: 6),
              const KindTag(DataKind.derived),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead(this.cols);
  final List<String> cols;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < cols.length; i++)
        Expanded(
          flex: i == 0 ? 3 : 2,
          child: Text(cols[i],
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: const TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 0.5)),
        ),
    ]);
  }
}

class _BaselineRowView extends StatelessWidget {
  const _BaselineRowView({required this.c, required this.row});
  final AppController c;
  final BaselineRow row;
  @override
  Widget build(BuildContext context) {
    final t = row.type;
    final cmp = row.comparison;
    final d = t == VitalType.temperature ? 2 : 1;
    final notable = cmp?.isNotable ?? false;
    Widget cell(String s, {int flex = 2, Color? color}) => Expanded(
          flex: flex,
          child: Text(s, textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: color ?? AC.text, fontFeatures: kTabular)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(flex: 3, child: Text(t.shortLabel)),
        cell(cmp == null ? '—' : fmtNum(cmp.baselineMean, d)),
        cell(cmp == null ? '—' : fmtNum(cmp.currentMean, d)),
        cell(cmp == null ? '—' : '${cmp.delta >= 0 ? '+' : ''}${fmtNum(cmp.delta, d)}', color: notable ? AC.amber : AC.textDim),
        cell(row.slopePerHour == null ? '—' : '${row.slopePerHour! >= 0 ? '+' : ''}${row.slopePerHour!.toStringAsFixed(d)}', color: AC.textDim),
      ]),
    );
  }
}

class _QualityRowView extends StatelessWidget {
  const _QualityRowView({required this.q});
  final QualityReport q;
  @override
  Widget build(BuildContext context) {
    final color = !q.hasData ? AC.textDim : (q.isPoor ? AC.red : (q.isFair ? AC.amber : AC.green));
    Widget cell(String s, {Color? col}) => Expanded(
          flex: 2,
          child: Text(s, textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: col ?? AC.text, fontFeatures: kTabular)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(flex: 3, child: Text(q.type.shortLabel)),
        cell(q.hasData ? '${(q.coverage * 100).round()}%' : '—', col: color),
        cell(q.hasData ? '${q.gapCount}' : '—'),
        cell('${q.invalidCount}'),
        cell('${q.delayedCount}'),
      ]),
    );
  }
}
