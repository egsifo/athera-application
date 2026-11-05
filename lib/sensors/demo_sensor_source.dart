import 'dart:async';

import '../domain/models.dart';
import 'demo_generator.dart';
import 'sensor_source.dart';

/// Simulated wearable stream. Everything it emits is source = demo.
class DemoSensorSource implements SensorSource {
  DemoSensorSource(this.generator, {List<Astronaut>? crew}) : crew = crew ?? DemoGenerator.crew;

  final DemoGenerator generator;
  final List<Astronaut> crew;
  final StreamController<List<Observation>> _ctrl = StreamController.broadcast();
  final Map<String, DateTime> _lastBp = {};
  Timer? _timer;
  SensorLinkState _state = SensorLinkState.stopped;

  @override
  String get id => 'demo';
  @override
  String get displayName => 'Simulated sensors (DEMO)';
  @override
  bool get isSimulated => true;
  @override
  SensorLinkState get state => _state;
  @override
  String? get stateDetail => _state == SensorLinkState.streaming
      ? 'Simulated stream every ${generator.config.liveTickSeconds}s'
      : 'Stopped';
  @override
  Stream<List<Observation>> get observations => _ctrl.stream;

  @override
  Future<void> start() async {
    _timer?.cancel();
    _state = SensorLinkState.streaming;
    _timer = Timer.periodic(Duration(seconds: generator.config.liveTickSeconds), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now().toUtc();
    final batch = <Observation>[];
    for (final a in crew) {
      final last = _lastBp[a.id];
      final includeBp = last == null || now.difference(last) >= const Duration(minutes: 5);
      final obs = generator.liveSample(a, now, includeBp: includeBp);
      if (obs.isNotEmpty && includeBp) _lastBp[a.id] = now;
      batch.addAll(obs);
    }
    if (batch.isNotEmpty && !_ctrl.isClosed) _ctrl.add(batch);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _state = SensorLinkState.stopped;
  }

  @override
  Future<List<Observation>> backfill(String astronautId, DateTime from, DateTime to) async {
    final a = crew.firstWhere((x) => x.id == astronautId, orElse: () => crew.first);
    return generator
        .history(a, to)
        .where((o) => !o.measuredAt.isBefore(from.toUtc()) && !o.measuredAt.isAfter(to.toUtc()))
        .toList();
  }

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }
}
