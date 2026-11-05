import '../domain/models.dart';

class IngestResult {
  IngestResult({required this.accepted, required this.duplicates, required this.invalid, required this.delayed});
  final List<Observation> accepted;
  final int duplicates;
  final int invalid;
  final int delayed;
}

/// Common gate for every sensor source: range validation, quality flagging,
/// duplicate detection and delay accounting.
class IngestPipeline {
  IngestPipeline({this.maxRemembered = 100000, this.delayThreshold = const Duration(minutes: 2)});

  final int maxRemembered;
  final Duration delayThreshold;
  final Set<String> _seen = {};
  final List<String> _order = [];

  void remember(Iterable<Observation> existing) {
    for (final o in existing) {
      _add(o.id);
    }
  }

  void reset() {
    _seen.clear();
    _order.clear();
  }

  void _add(String id) {
    if (_seen.add(id)) {
      _order.add(id);
      if (_order.length > maxRemembered) {
        _seen.remove(_order.removeAt(0));
      }
    }
  }

  IngestResult process(List<Observation> batch, {DateTime? now}) {
    final accepted = <Observation>[];
    var dup = 0, invalid = 0, delayed = 0;
    final nowUtc = (now ?? DateTime.now()).toUtc();
    for (final raw in batch) {
      if (_seen.contains(raw.id)) {
        dup++;
        continue;
      }
      var o = raw;
      final v = o.value;
      final outOfRange = !v.isFinite || v < o.type.validMin || v > o.type.validMax;
      final future = o.measuredAt.toUtc().isAfter(nowUtc.add(const Duration(minutes: 1)));
      if (outOfRange || future) {
        o = o.withQuality(DataQuality.invalid);
        invalid++;
      } else if (o.delay > delayThreshold && o.quality == DataQuality.good) {
        o = o.withQuality(DataQuality.fair);
      }
      if (o.delay > delayThreshold) delayed++;
      _add(o.id);
      accepted.add(o);
    }
    return IngestResult(accepted: accepted, duplicates: dup, invalid: invalid, delayed: delayed);
  }
}
