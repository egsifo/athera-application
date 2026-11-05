import '../core/config.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'sample_store.dart';
import 'stats.dart';

enum MonitoringStatus { nominal, attention, critical, noData }

extension MonitoringStatusX on MonitoringStatus {
  String get label => switch (this) {
        MonitoringStatus.nominal => 'Nominal',
        MonitoringStatus.attention => 'Attention',
        MonitoringStatus.critical => 'Critical',
        MonitoringStatus.noData => 'No data',
      };
}

/// A condition detected by the app's own threshold rules. These are
/// configurable screening thresholds, not a diagnosis. A "critical" finding
/// means a reading is far outside the configured range, not that an
/// emergency is confirmed.
class RuleFinding {
  const RuleFinding({
    required this.key,
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
    required this.astronautId,
    this.data = const {},
  });
  final String key;
  final AlertCategory category;
  final AlertSeverity severity;
  final String title;
  final String detail;
  final String astronautId;
  final Map<String, Object?> data;
}

class RuleEngine {
  const RuleEngine({this.sustainedWindow = const Duration(minutes: 5), this.sustainedFraction = 0.7});

  /// A threshold must be exceeded by this fraction of readings in this window.
  final Duration sustainedWindow;
  final double sustainedFraction;

  List<RuleFinding> evaluate(SampleStore store, String astronautId, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toUtc();
    final out = <RuleFinding>[];

    final lastSeen = store.lastSeen(astronautId);
    final disconnected = lastSeen != null && n.difference(lastSeen) > AppConfig.sensorStaleAfter;
    if (disconnected) {
      out.add(RuleFinding(
        key: 'sensor:$astronautId',
        category: AlertCategory.sensorDisconnection,
        severity: AlertSeverity.warning,
        astronautId: astronautId,
        title: 'Sensor data stopped',
        detail: 'No readings received for ${fmtDuration(n.difference(lastSeen))} (last: ${fmtTime(lastSeen)}).',
        data: {'last_seen': lastSeen.toIso8601String()},
      ));
      return out; // thresholds on stale data would be misleading
    }

    for (final t in VitalType.values) {
      final isBp = t == VitalType.systolic || t == VitalType.diastolic;
      final window = isBp ? const Duration(minutes: 15) : sustainedWindow;
      final recent = store.series(astronautId, t, within: window, now: n);
      final minN = isBp ? 1 : 3;
      if (recent.length >= minN) {
        double frac(bool Function(double) test) => recent.where((s) => test(s.v)).length / recent.length;
        final critHigh = frac((v) => v > t.critHigh);
        final critLow = frac((v) => v < t.critLow);
        final high = frac((v) => v > t.alertHigh);
        final low = frac((v) => v < t.alertLow);
        final m = mean(recent)!;
        AlertSeverity? sev;
        String? dir;
        if (critHigh >= sustainedFraction) {
          sev = AlertSeverity.critical;
          dir = 'high';
        } else if (critLow >= sustainedFraction) {
          sev = AlertSeverity.critical;
          dir = 'low';
        } else if (high >= sustainedFraction) {
          sev = AlertSeverity.warning;
          dir = 'high';
        } else if (low >= sustainedFraction) {
          sev = AlertSeverity.warning;
          dir = 'low';
        }
        if (sev != null && dir != null) {
          final bound = dir == 'high'
              ? (sev == AlertSeverity.critical ? t.critHigh : t.alertHigh)
              : (sev == AlertSeverity.critical ? t.critLow : t.alertLow);
          out.add(RuleFinding(
            key: 'vital:$astronautId:${t.name}',
            category: sev == AlertSeverity.critical ? AlertCategory.criticalAlert : AlertCategory.earlyWarning,
            severity: sev,
            astronautId: astronautId,
            title: '${t.label} ${dir == 'high' ? 'above' : 'below'} threshold',
            detail: 'Mean ${fmtNum(m, t == VitalType.temperature ? 1 : 0)} ${t.unit} over the last ${fmtDuration(window)} '
                '(${recent.length} readings) vs ${dir == 'high' ? 'upper' : 'lower'} limit ${bound} ${t.unit}. '
                'Rule-based screening threshold, not a diagnosis.',
            data: {'metric': t.name, 'mean': m, 'limit': bound, 'readings': recent.length},
          ));
        }
      }

      final q = assessQuality(store, astronautId, t, const Duration(minutes: 15), now: n);
      if (q.invalidCount >= 3) {
        out.add(RuleFinding(
          key: 'quality:$astronautId:${t.name}',
          category: AlertCategory.poorDataQuality,
          severity: AlertSeverity.info,
          astronautId: astronautId,
          title: '${t.label}: repeated invalid readings',
          detail: '${q.invalidCount} readings outside the plausible sensor range in the last 15 min. They are excluded from analytics.',
          data: {'metric': t.name, 'invalid': q.invalidCount},
        ));
      }
    }
    return out;
  }

  MonitoringStatus statusFrom(SampleStore store, String astronautId, Iterable<AlertEvent> open) {
    if (!store.hasAny(astronautId)) return MonitoringStatus.noData;
    final mine = open.where((a) => a.astronautId == astronautId && a.isOpen);
    if (mine.any((a) => a.severity == AlertSeverity.critical)) return MonitoringStatus.critical;
    if (mine.any((a) => a.severity == AlertSeverity.warning)) return MonitoringStatus.attention;
    return MonitoringStatus.nominal;
  }
}
