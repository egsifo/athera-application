import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            builder: (context, v, child) => Opacity(opacity: v, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AtheraLogo(size: 120, animate: true),
                const SizedBox(height: Sp.xl),
                const Text('ATHERA',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 10)),
                const SizedBox(height: Sp.s),
                const Text('Predict. Protect. Connect.', style: TextStyle(color: AC.cyan, letterSpacing: 1.5)),
                const SizedBox(height: Sp.xxl),
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(minHeight: 3),
                  ),
                ),
                const SizedBox(height: Sp.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
                  child: Text(message ?? 'Starting…',
                      textAlign: TextAlign.center, style: const TextStyle(color: AC.textDim, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
