import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../wellness/guidance.dart';
import 'common.dart';

Color guidanceColor(GuidanceLevel l) => switch (l) {
      GuidanceLevel.allClear => AC.green,
      GuidanceLevel.selfCare => AC.cyan,
      GuidanceLevel.tellCrew => AC.amber,
      GuidanceLevel.contactGround => AC.amber,
      GuidanceLevel.urgent => AC.red,
    };

IconData guidanceIcon(GuidanceLevel l) => switch (l) {
      GuidanceLevel.allClear => Icons.check_circle_outline_rounded,
      GuidanceLevel.selfCare => Icons.self_improvement_rounded,
      GuidanceLevel.tellCrew => Icons.record_voice_over_rounded,
      GuidanceLevel.contactGround => Icons.support_agent_rounded,
      GuidanceLevel.urgent => Icons.priority_high_rounded,
    };

/// "What to do now": the guidance engine's output as a card. Compact mode
/// (home screen) shows the headline and the first action only.
class GuidanceCard extends StatelessWidget {
  const GuidanceCard({super.key, required this.guidance, this.compact = false, this.onTap, this.onBrief});
  final Guidance guidance;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onBrief;

  @override
  Widget build(BuildContext context) {
    final g = guidance;
    final color = guidanceColor(g.level);
    final real = g.actions.length > 1 ? g.actions.sublist(0, g.actions.length - 1) : g.actions;
    final shown = compact ? real.take(1).toList() : real;
    final foot = g.actions.length > 1 ? g.actions.last : null;
    return AtCard(
      onTap: onTap,
      borderColor: tint(color, 0.55),
      semanticsLabel: 'What to do now. ${g.level.label}. ${g.headline}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(guidanceIcon(g.level), color: color, size: 20),
          const SizedBox(width: Sp.s),
          const Text('WHAT TO DO NOW',
              style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
          const Spacer(),
          Pill(g.level.label, color: color, dense: true),
        ]),
        const SizedBox(height: Sp.s),
        Text(g.headline, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        if (!compact && g.signals.isNotEmpty) ...[
          const SizedBox(height: Sp.s),
          for (final s in g.signals)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $s', style: const TextStyle(color: AC.textDim, fontSize: 13)),
            ),
        ],
        const SizedBox(height: Sp.m),
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.m),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: tint(color, 0.18),
                child: Text('${i + 1}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shown[i].text, style: const TextStyle(fontSize: 14, height: 1.3)),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(shown[i].why, style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.3)),
                  ],
                ]),
              ),
            ]),
          ),
        if (!compact && foot != null)
          Text(foot.text, style: const TextStyle(color: AC.textDim, fontSize: 11, fontStyle: FontStyle.italic)),
        if (onBrief != null && g.level.rank >= GuidanceLevel.tellCrew.rank) ...[
          const SizedBox(height: Sp.m),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBrief,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Prepare flight-surgeon brief'),
            ),
          ),
        ],
      ]),
    );
  }
}
