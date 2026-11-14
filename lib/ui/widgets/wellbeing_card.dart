import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../mind/wellbeing.dart';
import 'common.dart';

Color supportColor(SupportLevel l) => switch (l) {
      SupportLevel.stable => AC.green,
      SupportLevel.attention => AC.amber,
      SupportLevel.elevated => const Color(0xFFFB923C),
      SupportLevel.urgent => AC.red,
    };

/// Mental-health status next to the physical vitals. Self-reported, not clinical.
class WellbeingCard extends StatelessWidget {
  const WellbeingCard({super.key, required this.a, this.onTap, this.compact = false});
  final WellbeingAssessment a;
  final VoidCallback? onTap;
  final bool compact;

  static IconData _trendIcon(WellbeingTrend t) => switch (t) {
        WellbeingTrend.improving => Icons.trending_up_rounded,
        WellbeingTrend.declining => Icons.trending_down_rounded,
        WellbeingTrend.stable => Icons.trending_flat_rounded,
        WellbeingTrend.insufficient => Icons.hourglass_empty_rounded,
      };

  static String _trendText(WellbeingTrend t) => switch (t) {
        WellbeingTrend.improving => 'Improving',
        WellbeingTrend.declining => 'Declining',
        WellbeingTrend.stable => 'Stable',
        WellbeingTrend.insufficient => 'Trend needs 4+ check-ins',
      };

  @override
  Widget build(BuildContext context) {
    final color = supportColor(a.level);
    return AtCard(
      onTap: onTap,
      borderColor: tint(color, 0.5),
      semanticsLabel: 'Mental well-being: ${a.levelLabel}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.psychology_alt_rounded, color: color),
          const SizedBox(width: Sp.s),
          const Expanded(child: Text('Mental well-being', style: TextStyle(fontWeight: FontWeight.w600))),
          if (a.simulated) const Pill('DEMO', color: AC.amber, dense: true),
          const SizedBox(width: Sp.s),
          Pill(a.levelLabel, color: color, dense: true),
        ]),
        const SizedBox(height: Sp.m),
        if (!a.hasData)
          Text(a.reasons.join('. '), style: const TextStyle(color: AC.textDim))
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${a.score}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: color)),
            const Text(' / 100', style: TextStyle(color: AC.textDim)),
            const Spacer(),
            Icon(_trendIcon(a.trend), size: 18, color: AC.textDim),
            const SizedBox(width: 4),
            Text(_trendText(a.trend), style: const TextStyle(color: AC.textDim, fontSize: 12)),
          ]),
          if (!compact) ...[
            const SizedBox(height: Sp.m),
            for (final i in a.indicators)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 64, child: Text(i.name, style: const TextStyle(fontSize: 12, color: AC.textDim))),
                  Expanded(
                    child: LinearProgressIndicator(
                        value: i.score / 100, minHeight: 6, color: i.score >= 60 ? AC.green : (i.score >= 40 ? AC.amber : AC.red), backgroundColor: AC.surface2),
                  ),
                  SizedBox(width: 86, child: Text('  ${i.note}', style: const TextStyle(fontSize: 11, color: AC.textDim))),
                ]),
              ),
          ],
          if (a.reasons.isNotEmpty) ...[
            const SizedBox(height: Sp.s),
            Text(a.reasons.join(' · '), style: const TextStyle(fontSize: 12, color: AC.textDim, height: 1.3)),
          ],
        ],
        const SizedBox(height: Sp.s),
        Text(a.action, style: TextStyle(color: color, fontSize: 13, height: 1.3)),
        const SizedBox(height: Sp.s),
        const Text('Self-reported summary. Not a clinical measurement or a diagnosis.', style: TextStyle(fontSize: 10, color: AC.textDim)),
      ]),
    );
  }
}
