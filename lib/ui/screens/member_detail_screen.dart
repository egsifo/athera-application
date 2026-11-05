import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../vital_format.dart';
import '../widgets/common.dart';
import 'crew_screen.dart' show connectionStyle;
import 'home_screen.dart' show VitalCard;
import 'vitals_screen.dart';

/// Commander view of one crew member: latest vitals, AI result, alerts, history.
class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.astronautId});
  final String astronautId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final a = c.crew.firstWhere((m) => m.id == astronautId, orElse: () => c.selected);
    final (cLabel, cColor, cIcon) = connectionStyle(c.connectionOf(a.id));
    final snap = c.aiOf(a.id);
    final risk = snap.risk;
    final alerts = c.openAlertsFor(a.id);
    final allowed = c.accessPolicy.canViewOtherAstronauts(c.settings.role) || a.id == c.selected.id;

    return Scaffold(
      appBar: AppBar(title: Text(a.callsign)),
      body: !allowed
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Not available for this role',
              message: 'Prototype access policy: astronauts see only their own data.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
              children: [
                AtCard(
                  child: Row(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: tint(AC.cyan, 0.15),
                      child: Text(initials(a.name), style: const TextStyle(color: AC.cyan)),
                    ),
                    const SizedBox(width: Sp.m),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text('${a.callsign} · ${a.role.label}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
                        Text('Last data: ${fmtAgo(c.samples.lastSeen(a.id))}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
                      ]),
                    ),
                    Pill(cLabel, color: cColor, icon: cIcon),
                  ]),
                ),
                const SectionHeader('Latest vitals'),
                LayoutBuilder(builder: (context, box) {
                  final w = (box.maxWidth - Sp.m) / 2;
                  return Wrap(spacing: Sp.m, runSpacing: Sp.m, children: [
                    for (final types in const [
                      [VitalType.heartRate],
                      [VitalType.spo2],
                      [VitalType.systolic, VitalType.diastolic],
                      [VitalType.respiratoryRate],
                      [VitalType.temperature],
                    ])
                      SizedBox(width: w, child: VitalCard(c: c, astronautId: a.id, types: types)),
                  ]);
                }),
                const SectionHeader('AI assessment'),
                AtCard(
                  child: risk == null
                      ? Text(
                          snap.error != null ? 'AI service unavailable: ${snap.error!.message}' : 'No AI result yet.',
                          style: const TextStyle(color: AC.textDim),
                        )
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(riskIcon(risk.riskClass), color: riskColor(risk.riskClass)),
                            const SizedBox(width: Sp.s),
                            Text(risk.riskClass.label,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: riskColor(risk.riskClass))),
                            const Spacer(),
                            const KindTag(DataKind.predicted),
                          ]),
                          const SizedBox(height: Sp.s),
                          KeyValueRow('Model', '${risk.modelName} ${risk.modelVersion}'),
                          KeyValueRow('Generated', fmtDateTime(risk.generatedAt)),
                          if (risk.riskScore != null) KeyValueRow('Risk index', '${risk.riskScore!.round()} / 100 (not a probability)'),
                          if (risk.isMock) const KeyValueRow('Result type', 'ILLUSTRATIVE fixture', valueColor: AC.blue),
                          for (final w in risk.warnings) Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• ${w.message}', style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.35)),
                          ),
                        ]),
                ),
                const SectionHeader('Active alerts'),
                if (alerts.isEmpty)
                  const AtCard(child: Text('No active alerts.', style: TextStyle(color: AC.textDim)))
                else
                  for (final al in alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.s),
                      child: AtCard(
                        borderColor: tint(severityColor(al.severity), 0.45),
                        padding: const EdgeInsets.all(Sp.m),
                        child: Row(children: [
                          Icon(severityIcon(al.severity), color: severityColor(al.severity), size: 20),
                          const SizedBox(width: Sp.m),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(al.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${al.category.label} · ${fmtAgo(al.createdAt)}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                const SectionHeader('Health history'),
                RangeSelector(c: c),
                const SizedBox(height: Sp.m),
                for (final types in const [
                  [VitalType.heartRate],
                  [VitalType.spo2],
                  [VitalType.respiratoryRate],
                  [VitalType.temperature],
                  [VitalType.systolic, VitalType.diastolic],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sp.m),
                    child: VitalChartCard(c: c, astronautId: a.id, types: types),
                  ),
              ],
            ),
    );
  }
}
