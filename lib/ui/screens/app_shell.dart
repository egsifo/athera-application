import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../vital_format.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'ai_screen.dart';
import 'alerts_screen.dart';
import 'crew_screen.dart';
import 'health_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';
import 'vitals_screen.dart';

/// Bottom-navigation shell. Five primary destinations; SOS and Settings are
/// always one tap away in the app bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  StreamSubscription<AlertEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    _sub = c.newAlerts.listen((a) {
      if (!mounted) return;
      showSnack(context, '${a.title} · ${a.category.label}', error: a.severity == AlertSeverity.critical);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Tabs: 0 Home, 1 Vitals, 2 Health, 3 Analytics, 4 Crew. Index 5 opens Alerts.
  static const int tabAlerts = 5;

  void _openAlerts() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('Alerts')), body: const AlertsScreen())));

  void _goTo(int i) {
    if (i == tabAlerts) {
      _openAlerts();
      return;
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final openCount = c.openAlerts.where((a) => a.isOpen).length;
    final pages = <Widget>[
      HomeScreen(onGoTo: _goTo),
      const VitalsScreen(),
      const HealthScreen(),
      const AiScreen(),
      const CrewScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Sp.l,
        title: Row(children: [
          const AtheraLogo(size: 26),
          const SizedBox(width: Sp.s),
          const Text('ATHERA', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          if (c.crew.length > 1 && c.accessPolicy.canViewOtherAstronauts(c.settings.role)) _AstronautMenu(c),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: IconButton.filled(
              tooltip: 'Emergency SOS',
              style: IconButton.styleFrom(backgroundColor: AC.sosRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SosScreen())),
              icon: const Icon(Icons.sos_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Alerts',
            onPressed: _openAlerts,
            icon: Badge(
              isLabelVisible: openCount > 0,
              label: Text('$openCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (c.isSimulated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: tint(AC.blue, 0.14),
              child: const Text(
                'DEMO DATA · all readings are simulated, not medical evidence',
                textAlign: TextAlign.center,
                style: TextStyle(color: AC.blue, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
              ),
            ),
          if (c.persistenceWarning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.s),
              child: InfoBanner(c.persistenceWarning!, icon: Icons.storage_rounded, color: AC.amber),
            ),
          Expanded(child: pages[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Vitals'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Health'),
          NavigationDestination(
              icon: Icon(Icons.auto_graph_outlined), selectedIcon: Icon(Icons.auto_graph_rounded), label: 'Analytics'),
          NavigationDestination(
              icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: 'Crew'),
        ],
      ),
    );
  }
}

class _AstronautMenu extends StatelessWidget {
  const _AstronautMenu(this.c);
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final a = c.selected;
    return PopupMenuButton<String>(
      tooltip: 'Switch astronaut',
      color: AC.surface2,
      onSelected: c.selectAstronaut,
      itemBuilder: (_) => [
        for (final m in c.crew)
          PopupMenuItem<String>(
            value: m.id,
            child: Row(children: [
              Icon(m.id == a.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: AC.cyan),
              const SizedBox(width: Sp.s),
              Text('${m.callsign} · ${m.name}'),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Chip(
          visualDensity: VisualDensity.compact,
          avatar: CircleAvatar(
            backgroundColor: tint(AC.cyan, 0.2),
            child: Text(initials(a.name), style: const TextStyle(fontSize: 9, color: AC.cyan)),
          ),
          label: Text(a.callsign, style: const TextStyle(fontSize: 12)),
          side: const BorderSide(color: AC.border),
          backgroundColor: AC.surface,
        ),
      ),
    );
  }
}
