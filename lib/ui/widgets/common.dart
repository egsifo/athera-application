import 'package:flutter/material.dart';

import '../../analytics/rules.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';

Color severityColor(AlertSeverity s) => switch (s) {
      AlertSeverity.critical => AC.red,
      AlertSeverity.warning => AC.amber,
      AlertSeverity.info => AC.blue,
    };

IconData severityIcon(AlertSeverity s) => switch (s) {
      AlertSeverity.critical => Icons.error_rounded,
      AlertSeverity.warning => Icons.warning_amber_rounded,
      AlertSeverity.info => Icons.info_outline_rounded,
    };

Color riskColor(RiskClass? c) => switch (c) {
      RiskClass.critical => AC.red,
      RiskClass.earlyWarning => AC.amber,
      RiskClass.normal => AC.green,
      _ => AC.textDim,
    };

IconData riskIcon(RiskClass? c) => switch (c) {
      RiskClass.critical => Icons.error_rounded,
      RiskClass.earlyWarning => Icons.warning_amber_rounded,
      RiskClass.normal => Icons.check_circle_outline_rounded,
      _ => Icons.help_outline_rounded,
    };

Color statusColor(MonitoringStatus s) => switch (s) {
      MonitoringStatus.critical => AC.red,
      MonitoringStatus.attention => AC.amber,
      MonitoringStatus.nominal => AC.green,
      MonitoringStatus.noData => AC.textDim,
    };

IconData statusIcon(MonitoringStatus s) => switch (s) {
      MonitoringStatus.critical => Icons.error_rounded,
      MonitoringStatus.attention => Icons.warning_amber_rounded,
      MonitoringStatus.nominal => Icons.check_circle_outline_rounded,
      MonitoringStatus.noData => Icons.sensors_off_rounded,
    };

IconData categoryIcon(AlertCategory c) => switch (c) {
      AlertCategory.earlyWarning => Icons.trending_up_rounded,
      AlertCategory.criticalAlert => Icons.error_rounded,
      AlertCategory.sensorDisconnection => Icons.sensors_off_rounded,
      AlertCategory.poorDataQuality => Icons.signal_cellular_connected_no_internet_0_bar_rounded,
      AlertCategory.aiServiceUnavailable => Icons.cloud_off_rounded,
      AlertCategory.sosInitiated => Icons.sos_rounded,
      AlertCategory.sosDelivered => Icons.mark_email_read_outlined,
      AlertCategory.sosAcknowledged => Icons.done_all_rounded,
    };

/// Card with a subtle border; the single container style used across the app.
class AtCard extends StatelessWidget {
  const AtCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sp.l),
    this.onTap,
    this.borderColor,
    this.semanticsLabel,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: AC.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor ?? AC.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    if (semanticsLabel == null) return card;
    return Semantics(label: semanticsLabel, button: onTap != null, child: card);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AC.cyan, this.icon, this.dense = false});
  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: tint(color, 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint(color, 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: dense ? 11 : 13, color: color), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: color, fontSize: dense ? 10 : 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ]),
    );
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO DATA', this.dense = false});
  final String label;
  final bool dense;
  @override
  Widget build(BuildContext context) => Pill(label, color: AC.blue, icon: Icons.science_outlined, dense: dense);
}

enum DataKind { measured, derived, predicted }

/// Always-visible provenance label: what the user is looking at.
class KindTag extends StatelessWidget {
  const KindTag(this.kind, {super.key});
  final DataKind kind;
  @override
  Widget build(BuildContext context) => switch (kind) {
        DataKind.measured => const Pill('MEASURED', color: AC.cyan, dense: true),
        DataKind.derived => const Pill('DERIVED', color: AC.blue, dense: true),
        DataKind.predicted => const Pill('PREDICTED', color: AC.predicted, dense: true),
      };
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, Sp.l, 2, Sp.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(),
                style: const TextStyle(color: AC.textDim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: const TextStyle(color: AC.textDim, fontSize: 12)),
              ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.icon = Icons.info_outline_rounded, this.color = AC.blue, this.action});
  final String text;
  final IconData icon;
  final Color color;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.m),
      decoration: BoxDecoration(
        color: tint(color, 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint(color, 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: Sp.m),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        if (action != null) ...[const SizedBox(width: Sp.s), action!],
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.color = AC.textDim});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: Sp.m),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: Sp.s),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AC.textDim, height: 1.4)),
          ],
          if (action != null) ...[const SizedBox(height: Sp.l), action!],
        ]),
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
        if (label != null) ...[
          const SizedBox(height: Sp.m),
          Text(label!, style: const TextStyle(color: AC.textDim)),
        ],
      ]),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.k, this.v, {super.key, this.valueColor});
  final String k;
  final String v;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(k, style: const TextStyle(color: AC.textDim, fontSize: 13))),
        Expanded(flex: 6, child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontSize: 13, color: valueColor ?? AC.text))),
      ]),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? const Color(0xFF4A1D1D) : AC.surface2,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}
