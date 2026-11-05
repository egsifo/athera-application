import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../state/app_controller.dart';

/// Display-unit helpers. Storage and analytics stay in SI/°C; only the UI converts.
bool usesFahrenheit(AppController c, VitalType t) => t == VitalType.temperature && c.settings.fahrenheit;

double toDisplay(AppController c, VitalType t, double v) => usesFahrenheit(c, t) ? cToF(v) : v;

String unitOf(AppController c, VitalType t) => usesFahrenheit(c, t) ? '°F' : t.unit;

String valueText(AppController c, VitalType t, double? v) => v == null ? '—' : fmtNum(toDisplay(c, t, v), t.decimals);

enum Level { normal, attention, critical }

/// Position of a reading relative to the app's configurable screening limits.
/// This is a UI hint, never a diagnosis.
Level levelOf(VitalType t, double v) {
  if (v > t.critHigh || v < t.critLow) return Level.critical;
  if (v > t.alertHigh || v < t.alertLow) return Level.attention;
  return Level.normal;
}

Color levelColor(Level l) => switch (l) {
      Level.critical => AC.red,
      Level.attention => AC.amber,
      Level.normal => AC.text,
    };

/// A reading is "fresh" if it arrived recently relative to how often that
/// vital is sampled.
Duration freshWindow(VitalType t) =>
    t.nominalIntervalSec > 60 ? const Duration(minutes: 15) : const Duration(minutes: 2);

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
