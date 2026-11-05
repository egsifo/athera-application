import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';

/// Three short pages, then straight into the app. No account, no hardware needed.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;
  bool _busy = false;

  static const _pages = <_Page>[
    _Page(Icons.monitor_heart_outlined, 'See your health at a glance',
        'Heart rate, SpO₂, blood pressure, respiration and temperature in one calm view, with clear labels for what is measured, derived or predicted.'),
    _Page(Icons.insights_rounded, 'Early warning, not a verdict',
        'ATHERA can connect to your own AI service for forecasts and risk classes. Results are always labelled as model output, and the app keeps working if the service is offline.'),
    _Page(Icons.sos_rounded, 'Built for unreliable links',
        'Crew view and SOS are designed for patchy communication. The demo simulates delivery, and real radios plug in through a transport interface.'),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool demo}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final c = context.read<AppController>();
    await c.completeOnboarding();
    if (!demo) {
      await c.setDemoMode(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: Sp.xl),
            const AtheraLogo(size: 84, animate: true),
            const SizedBox(height: Sp.m),
            const Text('ATHERA', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 8)),
            const SizedBox(height: 4),
            const Text('Predict. Protect. Connect.', style: TextStyle(color: AC.cyan, letterSpacing: 1.2)),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [for (final p in _pages) _PageView(p)],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index ? AC.cyan : AC.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.l, Sp.xl, Sp.s),
              child: Column(
                children: [
                  if (last) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _finish(demo: true),
                        icon: const Icon(Icons.rocket_launch_outlined),
                        label: const Text('Enter demo mode'),
                      ),
                    ),
                    const SizedBox(height: Sp.s),
                    TextButton(
                      onPressed: _busy ? null : () => _finish(demo: false),
                      child: const Text('Use with real sensors (no demo data)'),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                        child: const Text('Next'),
                      ),
                    ),
                  if (!last)
                    TextButton(
                      onPressed: () => _page.animateToPage(_pages.length - 1,
                          duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.m),
              child: Text(AppConfig.disclaimer,
                  textAlign: TextAlign.center, style: const TextStyle(color: AC.textDim, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _PageView extends StatelessWidget {
  const _PageView(this.p);
  final _Page p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(p.icon, size: 44, color: AC.cyan),
              const SizedBox(height: Sp.l),
              Text(p.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: Sp.m),
              Text(p.body, textAlign: TextAlign.center, style: const TextStyle(color: AC.textDim, height: 1.45, fontSize: 14)),
              const SizedBox(height: Sp.l),
              const DemoBadge(label: 'DEMO MODE AVAILABLE · NO ACCOUNT NEEDED'),
            ],
          ),
        ),
      ),
    );
  }
}
