import '../domain/models.dart';

class Sample {
  const Sample(this.t, this.v, this.quality, this.receivedAt);
  final DateTime t;
  final double v;
  final DataQuality quality;
  final DateTime receivedAt;
  bool get usable => quality != DataQuality.invalid;
}

/// In-memory, time-sorted cache of recent observations per astronaut/vital.
/// SQLite is the source of truth; this makes charts and analytics instant.
class SampleStore {
  final Map<String, Map<VitalType, List<Sample>>> _d = {};

  /// True when any simulated observation was added (drives DEMO DATA labels).
  final Set<String> simulatedAstronauts = {};

  void add(Observation o) {
    final list = _d.putIfAbsent(o.astronautId, () => {}).putIfAbsent(o.type, () => []);
    final s = Sample(o.measuredAt.toUtc(), o.value, o.quality, o.receivedAt.toUtc());
    if (o.isSimulated) simulatedAstronauts.add(o.astronautId);
    if (list.isEmpty || s.t.isAfter(list.last.t)) {
      list.add(s);
      return;
    }
    // Out-of-order (delayed) arrival: insert sorted, ignore exact duplicates.
    var i = list.length - 1;
    while (i >= 0 && list[i].t.isAfter(s.t)) {
      i--;
    }
    if (i >= 0 && list[i].t == s.t) return;
    list.insert(i + 1, s);
  }

  void addAll(Iterable<Observation> items) {
    for (final o in items) {
      add(o);
    }
  }

  /// Samples within [within] before [now] (all samples if [within] is null).
  List<Sample> series(
    String astronautId,
    VitalType type, {
    Duration? within,
    DateTime? now,
    bool usableOnly = true,
  }) {
    final list = _d[astronautId]?[type];
    if (list == null) return const [];
    final end = (now ?? DateTime.now()).toUtc();
    final start = within == null ? null : end.subtract(within);
    return [
      for (final s in list)
        if ((start == null || !s.t.isBefore(start)) && !s.t.isAfter(end) && (!usableOnly || s.usable)) s,
    ];
  }

  /// Samples in an explicit [from, to) window.
  List<Sample> between(String astronautId, VitalType type, DateTime from, DateTime to, {bool usableOnly = true}) {
    final list = _d[astronautId]?[type];
    if (list == null) return const [];
    final f = from.toUtc();
    final t = to.toUtc();
    return [
      for (final s in list)
        if (!s.t.isBefore(f) && s.t.isBefore(t) && (!usableOnly || s.usable)) s,
    ];
  }

  Sample? latest(String astronautId, VitalType type, {bool usableOnly = true}) {
    final list = _d[astronautId]?[type];
    if (list == null) return null;
    for (var i = list.length - 1; i >= 0; i--) {
      if (!usableOnly || list[i].usable) return list[i];
    }
    return null;
  }

  /// Most recent sample of any vital.
  DateTime? lastSeen(String astronautId) {
    DateTime? best;
    final m = _d[astronautId];
    if (m == null) return null;
    for (final list in m.values) {
      if (list.isEmpty) continue;
      final t = list.last.t;
      if (best == null || t.isAfter(best)) best = t;
    }
    return best;
  }

  /// Oldest sample of any vital (to know how much history exists).
  DateTime? firstSeen(String astronautId) {
    DateTime? best;
    final m = _d[astronautId];
    if (m == null) return null;
    for (final list in m.values) {
      if (list.isEmpty) continue;
      final t = list.first.t;
      if (best == null || t.isBefore(best)) best = t;
    }
    return best;
  }

  int invalidCount(String astronautId, VitalType type, Duration within, {DateTime? now}) {
    final list = _d[astronautId]?[type];
    if (list == null) return 0;
    final end = (now ?? DateTime.now()).toUtc();
    final start = end.subtract(within);
    return list.where((s) => !s.usable && !s.t.isBefore(start)).length;
  }

  int delayedCount(String astronautId, VitalType type, Duration within, Duration threshold, {DateTime? now}) {
    final list = _d[astronautId]?[type];
    if (list == null) return 0;
    final end = (now ?? DateTime.now()).toUtc();
    final start = end.subtract(within);
    return list.where((s) => !s.t.isBefore(start) && s.receivedAt.difference(s.t) > threshold).length;
  }

  void trim(DateTime before) {
    final b = before.toUtc();
    for (final m in _d.values) {
      for (final list in m.values) {
        list.removeWhere((s) => s.t.isBefore(b));
      }
    }
  }

  bool hasAny(String astronautId) => (_d[astronautId]?.values.any((l) => l.isNotEmpty)) ?? false;

  void clear() {
    _d.clear();
    simulatedAstronauts.clear();
  }
}
