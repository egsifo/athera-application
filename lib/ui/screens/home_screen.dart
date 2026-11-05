import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/rules.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../vital_format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'mission_control_screen.dart';
import 'sos_screen.dart';

/// Health overview: who, are we connected, how are they, what is the AI saying,
/// then the vitals. Everything here is read from [AppController].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGoTo});
  final void Function(int tab) onGoTo;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final a = c.selected;
    final alerts = c.openAlertsFor(a.id)..sort((x, y) => y.severity.index.compareTo(x.severity.index));

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        _HeaderCard(c: c),
        const SizedBox(height: Sp.m),
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _StatusCard(c: c)),
          const SizedBox(width: Sp.m),
          Expanded(child: _RiskCard(c: c, onTap: () => onGoTo(2))),
        ]),
        const SizedBox(height: Sp.m),
        _QuickActions(c: c, onGoTo: onGoTo),
        SectionHeader('Active alerts',
            trailing: alerts.isEmpty ? null : TextButton(onPressed: () => onGoTo(4), child: const Text('View all'))),
        if (alerts.isEmpty)
          const AtCard(
            child: Row(children: [
              Icon(Icons.check_circle_outline_rounded, color: AC.green, size: 20),
              SizedBox(width: Sp.m),
              Expanded(child: Text('No active alerts for this astronaut.', style: TextStyle(color: AC.textDim))),
            ]),
          )
        else
          for (final al in alerts.take(3)) _AlertRow(al),
        SectionHeader('Vital signs', subtitle: 'Tap a card for charts and history'),
        _VitalGrid(c: c, onGoTo: onGoTo),
        const SizedBox(height: Sp.m),
        _EcgCard(c: c),
        const SizedBox(height: Sp.l),
        const Text(
          'Research prototype. Not a medical device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AC.textDim, fontSize: 11),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final a = c.selected;
    final conn = c.connectionOf(a.id);
    final seen = c.samples.lastSeen(a.id);
    final (label, color, icon) = switch (conn) {
      Connection.connected => ('Connected', AC.green, Icons.sensors_rounded),
      Connection.disconnected => ('Disconnected', AC.red, Icons.sensors_off_rounded),
      Connection.unknown => ('No sensor data', AC.textDim, Icons.sensors_off_rounded),
    };
    return AtCard(
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: tint(AC.cyan, 0.15),
          child: Text(initials(a.name), style: const TextStyle(color: AC.cyan, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text('${a.callsign} · ${a.role.label}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.schedule_rounded, size: 13, color: AC.textDim.withAlpha(200)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  seen == null ? 'No data received' : 'Updated ${fmtTime(seen)} · ${fmtAgo(seen)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AC.textDim, fontSize: 12),
                ),
              ),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Pill(label, color: color, icon: icon),
          if (c.isSimulated) ...[const SizedBox(height: 6), const DemoBadge(dense: true)],
        ]),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final s = c.monitoringStatus(c.selected.id);
    final color = statusColor(s);
    return AtCard(
      semanticsLabel: 'Monitoring status ${s.label}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Expanded(child: Text('MONITORING', style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1))),
          KindTag(DataKind.derived),
        ]),
        const SizedBox(height: Sp.m),
        Row(children: [
          Icon(statusIcon(s), color: color, size: 26),
          const SizedBox(width: Sp.s),
          Flexible(child: Text(s.label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color))),
        ]),
        const SizedBox(height: 6),
        const Text('Rule-based thresholds on measured data', style: TextStyle(color: AC.textDim, fontSize: 11)),
      ]),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.c, required this.onTap});
  final AppController c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final snap = c.aiOf(c.selected.id);
    final risk = snap.risk;
    final stale = snap.isStale(DateTime.now());
    final Widget body;
    if (risk != null) {
      final color = riskColor(risk.riskClass);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(riskIcon(risk.riskClass), color: color, size: 22),
          const SizedBox(width: 6),
          Flexible(child: Text(risk.riskClass.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color))),
        ]),
        const SizedBox(height: 4),
        if (risk.riskScore != null)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(risk.riskScore!.round().toString(),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: color, fontFeatures: kTabular)),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 5),
              child: Text('/100 index', style: TextStyle(color: AC.textDim, fontSize: 11)),
            ),
          ])
        else
          const Text('No score provided', style: TextStyle(color: AC.textDim, fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          if (risk.isMock) const Pill('ILLUSTRATIVE', color: AC.blue, dense: true),
          if (stale) const Pill('STALE', color: AC.amber, dense: true),
          if (snap.error != null) const Pill('UPDATE FAILED', color: AC.red, dense: true),
        ]),
      ]);
    } else if (snap.loading) {
      body = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: Sp.s),
        Text('Asking AI service…', style: TextStyle(color: AC.textDim, fontSize: 13)),
      ]);
    } else if (snap.error != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.cloud_off_rounded, color: AC.amber, size: 22),
          SizedBox(width: 6),
          Flexible(child: Text('AI service unavailable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Text(snap.error!.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AC.textDim, fontSize: 11)),
      ]);
    } else {
      body = const Text('No AI result yet', style: TextStyle(color: AC.textDim));
    }
    return AtCard(
      onTap: onTap,
      semanticsLabel: 'AI risk assessment',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Expanded(child: Text('AI RISK', style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1))),
          KindTag(DataKind.predicted),
        ]),
        const SizedBox(height: Sp.m),
        body,
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.c, required this.onGoTo});
  final AppController c;
  final void Function(int) onGoTo;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, String label, VoidCallback f, {Color color = AC.cyan}) => Expanded(
          child: OutlinedButton(
            onPressed: f,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: tint(color, 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 22),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        btn(Icons.hub_rounded, 'Crew', () => onGoTo(3)),
        const SizedBox(width: Sp.s),
        btn(Icons.auto_graph_rounded, 'Analytics', () => onGoTo(2)),
        const SizedBox(width: Sp.s),
        btn(Icons.sos_rounded, 'Emergency',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SosScreen())),
            color: AC.red),
      ]),
      if (c.canViewMissionControl)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MissionControlScreen())),
            icon: const Icon(Icons.radar_rounded, size: 18),
            label: const Text('Mission control'),
          ),
        ),
    ]);
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow(this.a);
  final AlertEvent a;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(a.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        borderColor: tint(color, 0.45),
        padding: const EdgeInsets.all(Sp.m),
        child: Row(children: [
          Icon(severityIcon(a.severity), color: color, size: 22),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${a.category.label} · ${fmtAgo(a.createdAt)}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
            ]),
          ),
          if (a.isDemo) const DemoBadge(label: 'DEMO', dense: true),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _VitalGrid extends StatelessWidget {
  const _VitalGrid({required this.c, required this.onGoTo});
  final AppController c;
  final void Function(int) onGoTo;

  @override
  Widget build(BuildContext context) {
    final cards = <List<VitalType>>[
      [VitalType.heartRate],
      [VitalType.spo2],
      [VitalType.systolic, VitalType.diastolic],
      [VitalType.respiratoryRate],
      [VitalType.temperature],
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 640 ? 3 : 2;
      final w = (box.maxWidth - Sp.m * (cols - 1)) / cols;
      return Wrap(
        spacing: Sp.m,
        runSpacing: Sp.m,
        children: [
          for (final types in cards)
            SizedBox(width: w, child: VitalCard(c: c, astronautId: c.selected.id, types: types, onTap: () => onGoTo(1))),
        ],
      );
    });
  }
}

class VitalCard extends StatelessWidget {
  const VitalCard({super.key, required this.c, required this.astronautId, required this.types, this.onTap});
  final AppController c;
  final String astronautId;
  final List<VitalType> types;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = types.first;
    final isBp = types.length == 2;
    final now = DateTime.now().toUtc();
    final latest = [for (final t in types) c.samples.latest(astronautId, t)];
    final first = latest.first;
    final has = latest.every((s) => s != null);

    String value = '—';
    var unit = isBp ? 'mmHg' : unitOf(c, primary);
    var color = AC.text;
    if (has) {
      value = isBp
          ? '${latest[0]!.v.round()}/${latest[1]!.v.round()}'
          : valueText(c, primary, latest[0]!.v);
      var worst = Level.normal;
      for (var i = 0; i < types.length; i++) {
        final l = levelOf(types[i], latest[i]!.v);
        if (l.index > worst.index) worst = l;
      }
      color = levelColor(worst);
    } else if (first != null && isBp) {
      unit = 'mmHg';
    }

    final fresh = first != null && now.difference(first.t) <= freshWindow(primary);
    final (statusText, statusColorV) = first == null
        ? ('No data', AC.textDim)
        : fresh
            ? ('Fresh · ${fmtTime(first.t)}', AC.green)
            : ('Stale · ${fmtTime(first.t)} (${fmtAgo(first.t)})', AC.amber);
    if (!fresh) color = AC.textDim;

    final title = isBp ? 'Blood pressure' : primary.label;
    final spark = c.samples.series(astronautId, primary, within: const Duration(hours: 1));

    return AtCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Sp.m),
      semanticsLabel: '$title $value $unit. $statusText',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AC.textDim, fontSize: 12)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: color, fontFeatures: kTabular)),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(unit, style: const TextStyle(color: AC.textDim, fontSize: 11)),
          ),
        ]),
        Sparkline(samples: spark, color: fresh ? AC.cyan : AC.textDim),
        const SizedBox(height: 4),
        Row(children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColorV, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Expanded(child: Text(statusText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: statusColorV, fontSize: 10.5))),
        ]),
        const SizedBox(height: 4),
        const KindTag(DataKind.measured),
      ]),
    );
  }
}

class _EcgCard extends StatelessWidget {
  const _EcgCard({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final wave = c.demoEcg;
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('ECG', style: TextStyle(color: AC.textDim, fontSize: 12))),
          if (wave != null) const DemoBadge(label: 'DEMO DATA · SIMULATED WAVEFORM', dense: true),
        ]),
        const SizedBox(height: Sp.s),
        if (wave != null)
          EcgView(samples: wave)
        else
          const Row(children: [
            Icon(Icons.show_chart_rounded, color: AC.textDim),
            SizedBox(width: Sp.m),
            Expanded(
              child: Text(
                'ECG status: not available. A waveform appears here only when an ECG-capable sensor streams samples.',
                style: TextStyle(color: AC.textDim, fontSize: 13, height: 1.35),
              ),
            ),
          ]),
      ]),
    );
  }
}
