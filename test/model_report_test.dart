import 'dart:convert';
import 'dart:io';

import 'package:athera/ai/model_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Object?> json;
  setUpAll(() {
    json = jsonDecode(File('assets/ai/backtest.json').readAsStringSync()) as Map<String, Object?>;
  });

  test('the bundled report parses and is internally consistent', () {
    final r = ModelReport.parse(json);
    expect(r.horizonMinutes, 120);
    expect(r.isSimulated, isTrue);
    expect(r.series.length, r.holdoutRows);
    expect(r.confusion.expand((x) => x).fold<int>(0, (a, b) => a + b), r.holdoutRows);
    final correct = r.confusion[0][0] + r.confusion[1][1] + r.confusion[2][2];
    expect(correct / r.holdoutRows, closeTo(r.accuracy, 0.0006));
    expect(r.accuracy, greaterThan(r.baselineAccuracy));
    expect(r.episodes.length, r.episodeCount);
  });

  test('every episode onset exists in the series', () {
    final r = ModelReport.parse(json);
    for (final e in r.episodes) {
      expect(r.series.indexOf(e.onset), isNonNegative, reason: e.onset);
    }
  });

  test('missing fields are errors, never defaults', () {
    final bad = Map<String, Object?>.from(json)..remove('accuracy');
    expect(() => ModelReport.parse(bad), throwsFormatException);
    final bad2 = Map<String, Object?>.from(json)..['data_kind'] = 'maybe';
    expect(() => ModelReport.parse(bad2), throwsFormatException);
    final bad3 = Map<String, Object?>.from(json)..['confusion'] = [[1]];
    expect(() => ModelReport.parse(bad3), throwsFormatException);
  });

  test('series arrays must have equal length', () {
    final s = Map<String, Object?>.from(json['series'] as Map)..['hr'] = [1.0];
    final bad = Map<String, Object?>.from(json)..['series'] = s;
    expect(() => ModelReport.parse(bad), throwsFormatException);
  });
}
