import 'package:athera/sensors/demo_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final anchor = DateTime.utc(2026, 10, 19, 12);

  test('same seed gives identical data; every reading is marked simulated', () {
    final a = DemoGenerator(config: const DemoConfig(seed: 7), anchor: anchor).history(DemoGenerator.crew.first, anchor);
    final b = DemoGenerator(config: const DemoConfig(seed: 7), anchor: anchor).history(DemoGenerator.crew.first, anchor);
    expect(a, isNotEmpty);
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].id, b[i].id);
      expect(a[i].value, b[i].value);
    }
    expect(a.every((o) => o.isSimulated), isTrue);
  });

  test('a different seed gives different data', () {
    final a = DemoGenerator(config: const DemoConfig(seed: 1), anchor: anchor).history(DemoGenerator.crew.first, anchor);
    final b = DemoGenerator(config: const DemoConfig(seed: 2), anchor: anchor).history(DemoGenerator.crew.first, anchor);
    final same = [for (var i = 0; i < a.length && i < b.length; i++) a[i].value == b[i].value].where((x) => x).length;
    expect(same, lessThan(a.length));
  });

  test('ECG waveform is only synthetic and non-empty', () {
    final g = DemoGenerator(config: const DemoConfig(), anchor: anchor);
    expect(g.ecgWaveform(70), isNotEmpty);
  });
}
