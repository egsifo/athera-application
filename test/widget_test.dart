import 'dart:convert';
import 'dart:io';

import 'package:athera/ai/model_report.dart';
import 'package:athera/ui/screens/model_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ModelReport> _load() async =>
    ModelReport.parse(jsonDecode(File('assets/ai/backtest.json').readAsStringSync()));

void main() {
  testWidgets('model report card renders honestly (simulated data banner, baseline, limits)', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ModelReportScreen(loader: _load)));
    await tester.pumpAndSettle();
    expect(find.textContaining('SIMULATED'), findsWidgets);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Naive baseline'), findsOneWidget);
    expect(find.text('CONFUSION MATRIX'), findsOneWidget);
    expect(find.text('LIMITS, STATED PLAINLY'), findsOneWidget);
  });

  testWidgets('report load failure shows an error, not a blank screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ModelReportScreen(loader: () async => throw const FormatException('bad'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });
}
