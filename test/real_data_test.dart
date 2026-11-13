import 'dart:convert';
import 'dart:io';

import 'package:athera/data/real_data.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _json(String f) => jsonDecode(File(f).readAsStringSync());

void main() {
  group('IssRadiation (real NASA RadLab asset)', () {
    late IssRadiation d;
    setUpAll(() => d = IssRadiation.parse(_json('assets/data/iss_radiation.json')));

    test('parses, is labelled measured and keeps the uGy unit', () {
      expect(d.instruments.keys, containsAll(['DosTel1', 'DosTel2']));
      expect(d.unit, contains('NOT dose equivalent'));
    });
    test('statistics are plausible for the ISS and computed from the data', () {
      final s = RadStats(d.instruments['DosTel2']!);
      expect(s.completeDays, greaterThan(500));
      expect(s.meanDailyDoseUGy, inInclusiveRange(200, 1500)); // roughly 0.2 to 1.5 mGy/day on the ISS
      expect(s.quietMedianRate, inInclusiveRange(1, 15));
      expect(s.peakInstant!.max, greaterThan(s.peakDay!.mean));
    });
    test('the long 2022-2024 gap is detected, not filled', () {
      final g = RadStats.gaps(d.instruments['DosTel2']!);
      expect(g.any((x) => x.$1.isBefore(DateTime(2023, 7)) && x.$2.isAfter(DateTime(2023, 12, 31))), isTrue);
    });
    test('malformed data is rejected', () {
      final bad = _json('assets/data/iss_radiation.json') as Map<String, Object?>;
      expect(() => IssRadiation.parse({...bad, 'kind': 'simulated'}), throwsFormatException);
      expect(() => IssRadiation.parse({...bad, 'instruments': <String, Object?>{}}), throwsFormatException);
      final ins = {'X': {'days': [['2020-01-02', 1.0, 1.0, 2.0, 5, 1], ['2020-01-01', 1.0, 1.0, 2.0, 5, 1]]}};
      expect(() => IssRadiation.parse({...bad, 'instruments': ins}), throwsFormatException);
      final impossible = {'X': {'days': [['2020-01-01', 5.0, 1.0, 2.0, 5, 1]]}};
      expect(() => IssRadiation.parse({...bad, 'instruments': impossible}), throwsFormatException);
    });
  });

  group('BloodPanel (real Inspiration4 asset)', () {
    late BloodPanel p;
    setUpAll(() => p = BloodPanel.parse(_json('assets/data/i4_blood.json')));

    test('has both panels, 4 crew and 7 timepoints', () {
      expect(p.markers.map((m) => m.panel).toSet().length, 2);
      expect(p.timepoints, ['L-92', 'L-44', 'L-3', 'R+1', 'R+45', 'R+82', 'R+194']);
      for (final m in p.markers) {
        expect(m.values.length, 4, reason: m.id);
      }
    });
    test('landing change is computed from real values', () {
      final hb = p.markers.firstWhere((m) => m.id == 'hemoglobin');
      expect(hb.changeAtLandingPct(p.timepoints), isNotNull);
    });
    test('range check', () {
      final m = BloodMarker(id: 'x', label: 'x', panel: 'p', unit: 'u', refMin: 1, refMax: 2, values: {'C1': [0.5, 1.5, null]});
      expect(m.outOfRangeCount, 1);
    });
    test('wrong value count is rejected', () {
      final bad = _json('assets/data/i4_blood.json') as Map<String, Object?>;
      expect(() => BloodPanel.parse({...bad, 'timepoints': ['L-3']}), throwsFormatException);
    });
  });
}
