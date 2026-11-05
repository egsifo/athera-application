import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../export_helper.dart';
import '../widgets/common.dart';

/// Persistent alert and event history with filters. Reads from the repository,
/// so history survives restarts.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertCategory? _category;
  AlertSeverity? _severity;
  String? _astronautId; // null = all crew
  Duration? _within = const Duration(hours: 24);
  bool _openOnly = false;

  Future<List<AlertEvent>>? _future;
  String _key = '';

  static const _times = <String, Duration?>{
    '1 h': Duration(hours: 1),
    '24 h': Duration(hours: 24),
    '7 d': Duration(days: 7),
    'All': null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final key = '${c.alertRevision}|${_category?.name}|${_severity?.name}|$_astronautId|${_within?.inMinutes}';
    if (key != _key) {
      _key = key;
      _future = c.queryAlerts(astronautId: _astronautId, category: _category, severity: _severity, within: _within);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        _filters(c),
        const SizedBox(height: Sp.m),
        FutureBuilder<List<AlertEvent>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(Sp.xl), child: LoadingBox(label: 'Loading history…'));
            }
            if (snap.hasError) {
              return InfoBanner('Could not read the stored history: ${snap.error}', icon: Icons.storage_rounded, color: AC.red);
            }
            var items = snap.data ?? const <AlertEvent>[];
            if (_openOnly) items = items.where((a) => a.isOpen).toList();
            if (items.isEmpty) {
              return const AtCard(
                child: EmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: 'No events match these filters',
                  message: 'Alerts, warnings, sensor and SOS events appear here and stay stored on this device.',
                ),
              );
            }
            return Column(children: [
              for (final a in items)
                Padding(padding: const EdgeInsets.only(bottom: Sp.s), child: _AlertTile(c: c, a: a)),
            ]);
          },
        ),
      ],
    );
  }

  Widget _filters(AppController c) {
    return AtCard(
      padding: const EdgeInsets.all(Sp.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _drop<AlertCategory?>(
              label: 'Category',
              value: _category,
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                for (final k in AlertCategory.values) DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          const SizedBox(width: Sp.s),
          Expanded(
            child: _drop<AlertSeverity?>(
              label: 'Severity',
              value: _severity,
              items: [
                const DropdownMenuItem(value: null, child: Text('Any severity')),
                for (final k in AlertSeverity.values) DropdownMenuItem(value: k, child: Text(k.name)),
              ],
              onChanged: (v) => setState(() => _severity = v),
            ),
          ),
        ]),
        const SizedBox(height: Sp.s),
        if (c.crew.length > 1 && c.accessPolicy.canViewOtherAstronauts(c.settings.role))
          _drop<String?>(
            label: 'Crew member',
            value: _astronautId,
            items: [
              const DropdownMenuItem(value: null, child: Text('All crew')),
              for (final a in c.crew) DropdownMenuItem(value: a.id, child: Text('${a.callsign} · ${a.name}')),
            ],
            onChanged: (v) => setState(() => _astronautId = v),
          ),
        const SizedBox(height: Sp.s),
        Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final e in _times.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: Sp.s),
                    child: ChoiceChip(
                      label: Text(e.key),
                      selected: _within == e.value,
                      onSelected: (_) => setState(() => _within = e.value),
                    ),
                  ),
                FilterChip(
                  label: const Text('Open only'),
                  selected: _openOnly,
                  onSelected: (v) => setState(() => _openOnly = v),
                ),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              final csv = await c.alertsCsvAll();
              if (mounted) await shareCsv(context, 'athera_alerts.csv', csv);
            },
          ),
        ]),
      ]),
    );
  }

  Widget _drop<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AC.surface2,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.c, required this.a});
  final AppController c;
  final AlertEvent a;

  String _who() {
    if (a.astronautId == null) return 'System';
    for (final m in c.crew) {
      if (m.id == a.astronautId) return m.callsign;
    }
    return a.astronautId!;
  }

  @override
  Widget build(BuildContext context) {
    final color = severityColor(a.severity);
    final statusColor = switch (a.status) {
      AlertStatus.active => AC.amber,
      AlertStatus.acknowledged => AC.blue,
      AlertStatus.resolved => AC.green,
    };
    return AtCard(
      padding: EdgeInsets.zero,
      borderColor: a.isOpen ? tint(color, 0.45) : AC.border,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(Sp.m, 0, Sp.m, Sp.m),
          leading: Icon(categoryIcon(a.category), color: a.isOpen ? color : AC.textDim),
          title: Text(a.title, style: TextStyle(fontWeight: FontWeight.w600, color: a.isOpen ? AC.text : AC.textDim)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${a.category.label} · ${_who()} · ${fmtAgo(a.createdAt)}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
              Pill(a.status.name, color: statusColor, dense: true),
              if (a.isDemo) const DemoBadge(label: 'DEMO', dense: true),
            ]),
          ),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(a.detail, style: const TextStyle(height: 1.4, fontSize: 13))),
            const SizedBox(height: Sp.s),
            KeyValueRow('Source', a.source),
            KeyValueRow('Severity', a.severity.name, valueColor: color),
            KeyValueRow('Created', fmtDateTime(a.createdAt)),
            KeyValueRow('Updated', fmtDateTime(a.updatedAt)),
            for (final e in a.data.entries) KeyValueRow(e.key, '${e.value}'),
            if (a.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: Sp.s),
                child: Wrap(spacing: Sp.s, children: [
                  if (a.status == AlertStatus.active)
                    OutlinedButton(onPressed: () => c.acknowledgeAlert(a), child: const Text('Acknowledge')),
                  OutlinedButton(onPressed: () => c.resolveAlert(a), child: const Text('Resolve')),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
