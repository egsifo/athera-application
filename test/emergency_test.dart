import 'package:athera/emergency/detector.dart';
import 'package:athera/emergency/knowledge_base.dart';
import 'package:athera/sim/emergency_sim.dart';
import 'package:flutter_test/flutter_test.dart';

SimEngine run(SimScenario s, {int? until}) {
  final e = SimEngine(s);
  final n = until ?? s.durationSeconds;
  while (e.history.length < n && e.step()) {}
  return e;
}

void main() {
  group('knowledge base', () {
    test('covers all 11 conditions exactly once', () {
      expect(kProtocols.map((p) => p.kind).toSet(), EmergencyKind.values.toSet());
      expect(kProtocols.length, EmergencyKind.values.length);
    });

    test('every guide has steps, avoid, escalation and both languages', () {
      for (final p in kProtocols) {
        for (final r in Role.values) {
          final g = p.guide(r);
          expect(g.steps.length, greaterThanOrEqualTo(2), reason: '${p.kind} $r');
          for (final s in [...g.steps, g.title]) {
            expect(s.en.trim(), isNotEmpty);
            expect(s.ar.trim(), isNotEmpty);
          }
        }
        expect(p.avoid, isNotEmpty, reason: p.kind.name);
        expect(p.escalate, isNotEmpty, reason: p.kind.name);
        expect(p.criteria, isNotEmpty, reason: p.kind.name);
        expect(p.place.keys.toSet(), Place.values.toSet(), reason: p.kind.name);
      }
    });

    test('TEST 6: every guide carries verifiable sources', () {
      for (final p in kProtocols) {
        expect(p.sources, isNotEmpty, reason: p.kind.name);
        for (final s in p.sources) {
          expect(s.url.startsWith('https://'), isTrue);
          expect(s.org.trim(), isNotEmpty);
          expect(s.doc.trim(), isNotEmpty);
          expect(s.checked.trim(), isNotEmpty);
        }
        expect(p.reviewStatus, 'Not clinically reviewed');
      }
    });

    test('TEST 8: no doses or prescriptions are ever generated', () {
      final bad = RegExp(r'\b\d+\s?(mg|mcg|ml|mL|tablet|tablets|pill|pills)\b|aspirin|epinephrine dose', caseSensitive: false);
      for (final p in kProtocols) {
        final all = [for (final r in Role.values) ...p.guide(r).steps, ...p.place.values, ...p.avoid, ...p.escalate];
        for (final t in all) {
          expect(bad.hasMatch(t.en), isFalse, reason: t.en);
        }
      }
    });

    test('medicine steps are always gated on the medical officer or an approved protocol', () {
      for (final p in kProtocols) {
        for (final r in Role.values) {
          for (final s in p.guide(r).steps) {
            if (RegExp(r'\bmedicine\b|\breliever\b', caseSensitive: false).hasMatch(s.en)) {
              expect(RegExp(r'medical officer|approved|protocol|allows', caseSensitive: false).hasMatch(s.en), isTrue, reason: s.en);
            }
          }
        }
      }
    });

    test('TEST 7: ground, cabin and EVA advice differ and EVA never tells anyone to move', () {
      for (final p in kProtocols) {
        expect(p.place[Place.cabin]!.en, isNot(p.place[Place.ground]!.en));
        expect(p.place[Place.eva]!.en, isNot(p.place[Place.cabin]!.en));
        final eva = p.place[Place.eva]!.en.toLowerCase();
        expect(eva.contains('move to'), isFalse, reason: p.kind.name);
        expect(eva.contains('go to'), isFalse, reason: p.kind.name);
        expect(p.space.en.trim(), isNotEmpty);
      }
      expect(protocolFor(EmergencyKind.syncope).place[Place.cabin]!.en, contains('microgravity'));
      expect(kSpaceFallback.en, contains('No verified spaceflight-specific procedure'));
    });

    test('disclaimer never claims official approval', () {
      expect(kDisclaimer.en, contains('not an official NASA'));
      expect(kDisclaimer.en, contains('not been clinically reviewed'));
    });

    test('syncope has separate guides for self and helper, with the breathing check', () {
      final p = protocolFor(EmergencyKind.syncope);
      expect(p.self.steps.join(' '), contains('tell a crewmate'));
      final h = p.helper.steps.join(' ');
      expect(h, contains('responsiveness'));
      expect(h, contains('breathing'));
      expect(h, contains('CPR'));
    });
  });

  group('detector', () {
    test('TEST 4: abnormal heart rate is a reading, not a diagnosis', () {
      final d = detectEmergency(hr: 150);
      final c = d.candidates.firstWhere((x) => x.kind == EmergencyKind.arrhythmia);
      expect(c.reason, contains('not a confirmed arrhythmia'));
      expect(protocolFor(EmergencyKind.arrhythmia).possibility.en, contains('not a confirmed arrhythmia'));
    });

    test('normal vitals raise nothing', () {
      expect(detectEmergency(hr: 70, spo2: 97, rr: 15, temp: 36.8, activity: 0.3).candidates, isEmpty);
    });

    test('low SpO2 is hypoxia only as a possibility with a cause warning', () {
      final c = detectEmergency(spo2: 82).candidates.first;
      expect(c.kind, EmergencyKind.hypoxia);
      expect(c.severity, 3);
      expect(c.reason, contains('not known from SpO₂ alone'));
    });

    test('unreliable data is flagged', () {
      expect(detectEmergency(spo2: 91, dataReliable: false).uncertainty, isNotNull);
      expect(detectEmergency(spo2: 91).uncertainty, isNull);
    });

    test('reported symptoms open chest pain, stroke, allergy and psychological guides', () {
      for (final k in [EmergencyKind.chestPain, EmergencyKind.stroke, EmergencyKind.allergy, EmergencyKind.psychological]) {
        expect(detectEmergency(reported: {k}).candidates.first.kind, k);
      }
    });
  });

  group('simulated demos open the right guide', () {
    test('every guide scenario raises a serious event and maps to a protocol', () {
      for (final s in SimScenario.values.where((v) => v.guide != null)) {
        final e = run(s);
        expect(e.events.any((x) => x.severity >= 2), isTrue, reason: s.name);
        expect(protocolFor(s.guide!).kind, s.guide);
        expect(e.report().lines.join(' '), contains('Guide opened'));
        expect(e.report().lines.join(' '), contains('SIMULATED'));
      }
    });

    test('TEST 1: fainting opens the syncope guide', () {
      expect(SimScenario.fainting.guide, EmergencyKind.syncope);
      expect(SimScenario.nearFaint.guide, EmergencyKind.syncope);
      final e = run(SimScenario.fainting);
      final h = e.history.last;
      expect(detectEmergency(hr: 46, activity: 0, unresponsive: true).top!.kind, EmergencyKind.syncope);
      expect(h.t, greaterThan(0));
    });

    test('near-faint does not claim loss of consciousness', () {
      final e = run(SimScenario.nearFaint);
      expect(e.events.any((x) => x.title.contains('Suspected loss of consciousness')), isFalse);
    });

    test('TEST 2: falling SpO2 opens the hypoxia guide', () {
      final e = run(SimScenario.hypoxia);
      final s = e.history.last;
      expect(detectEmergency(spo2: s.spo2).top!.kind, EmergencyKind.hypoxia);
      expect(SimScenario.hypoxia.guide, EmergencyKind.hypoxia);
    });

    test('TEST 3: chest pain demo shows the report and urgent first step', () {
      final e = run(SimScenario.chestPain);
      expect(e.events.any((x) => x.title.contains('chest pressure')), isTrue);
      expect(protocolFor(EmergencyKind.chestPain).self.steps.map((t) => t.en).join(' '), contains('Call a crewmate and mission medical support now'));
    });

    test('TEST 5: psychological demo reaches severity 3 and offers human support', () {
      final e = run(SimScenario.psych);
      expect(e.events.any((x) => x.title.contains('self-harm') && x.severity == 3), isTrue);
      final p = protocolFor(EmergencyKind.psychological);
      expect(p.avoid.map((t) => t.en).join(' '), contains('Laila'));
      expect(p.self.steps.map((t) => t.en).join(' '), contains('I need a person now'));
    });

    test('arrhythmia demo reports an abnormal reading, never a named diagnosis', () {
      final e = run(SimScenario.arrhythmia);
      final all = e.events.map((x) => '${x.title} ${x.detail}'.toLowerCase()).join(' ');
      expect(all.contains('fibrillation'), isFalse);
      expect(all.contains('tachycardia'), isFalse);
    });

    test('all demos are deterministic', () {
      for (final s in [SimScenario.stroke, SimScenario.allergy, SimScenario.heat, SimScenario.respiratory]) {
        final a = run(s), b = run(s);
        expect(a.events.map((x) => x.title).toList(), b.events.map((x) => x.title).toList());
      }
    });
  });
}
