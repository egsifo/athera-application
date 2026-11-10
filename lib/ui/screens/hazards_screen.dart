import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../wellness/hazards.dart';
import '../widgets/common.dart';

/// NASA's five spaceflight hazards and what ATHERA does about each.
class HazardsScreen extends StatelessWidget {
  const HazardsScreen({super.key, this.initialId});
  final String? initialId;

  Widget _list(String title, List<String> items) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final i in items)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $i', style: const TextStyle(fontSize: 14, height: 1.35))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spaceflight hazards')),
      body: ListView(padding: const EdgeInsets.all(Sp.l), children: [
        const InfoBanner(
          'NASA\'s Human Research Program groups the health risks of spaceflight into five hazards. This is a short guide, not medical advice.',
        ),
        const SizedBox(height: Sp.m),
        for (final h in kHazards)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.m),
            child: AtCard(
              borderColor: h.id == initialId ? tint(AC.cyan, 0.6) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(h.summary, style: const TextStyle(color: AC.textDim, height: 1.35)),
                const SizedBox(height: Sp.m),
                _list('Health effects', h.effects),
                _list('What ATHERA tracks', h.watch),
                const Text('DAILY HABIT',
                    style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(h.habit, style: const TextStyle(fontSize: 14, height: 1.35)),
              ]),
            ),
          ),
      ]),
    );
  }
}
