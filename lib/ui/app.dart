import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_controller.dart';
import '../state/wellness_state.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

class AtheraApp extends StatefulWidget {
  const AtheraApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<AtheraApp> createState() => _AtheraAppState();
}

class _AtheraAppState extends State<AtheraApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: widget.controller),
        ChangeNotifierProvider<WellnessState>(create: (ctx) => WellnessState(ctx.read<AppController>())),
      ],
      child: MaterialApp(
        title: 'ATHERA',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.dark,
        darkTheme: buildTheme(),
        home: const _RootGate(),
      ),
    );
  }
}

/// Splash while the controller boots, onboarding on first run, then the app.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final Widget child;
    if (c.bootstrapping) {
      child = SplashScreen(message: c.bootMessage, key: const ValueKey('splash'));
    } else if (!c.settings.onboardingDone) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else {
      child = const AppShell(key: ValueKey('shell'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}
