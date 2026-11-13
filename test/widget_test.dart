import 'dart:convert';
import 'dart:io';

import 'package:athera/ai/model_report.dart';
import 'package:athera/data/real_data.dart';
import 'package:athera/ui/screens/blood_screen.dart';
import 'package:athera/ui/screens/radiation_screen.dart';
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

  testWidgets('radiation screen shows real-data banner, units and honesty note', (tester) async {
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<IssRadiation> load() async =>
        IssRadiation.parse(jsonDecode(File('assets/data/iss_radiation.json').readAsStringSync()));
    await tester.pumpWidget(MaterialApp(home: RadiationScreen(loader: load)));
    await tester.pumpAndSettle();
    expect(find.textContaining('MEASURED'), findsOneWidget);
    expect(find.textContaining('µGy/day'), findsOneWidget);
    expect(find.textContaining('not converted to mSv'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Data gaps'.toUpperCase()), findsOneWidget);
  });

  testWidgets('blood screen shows marker chart and limits', (tester) async {
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<BloodPanel> load() async =>
        BloodPanel.parse(jsonDecode(File('assets/data/i4_blood.json').readAsStringSync()));
    await tester.pumpWidget(MaterialApp(home: BloodScreen(loader: load)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only 4 people'), findsOneWidget);
    expect(find.text('Reference range'), findsOneWidget);
    expect(find.text('LIMITS'), findsOneWidget);
  });
}
