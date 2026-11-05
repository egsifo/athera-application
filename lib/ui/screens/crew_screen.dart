import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/rules.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'member_detail_screen.dart';

enum CrewFilter { all, connected, disconnected, alerts }

extension CrewFilterX on CrewFilter {
  String get label => switch (this) {
        CrewFilter.all => 'All',
        CrewFilter.connected => 'Connected',
        CrewFilter.disconnected => 'Disconnected',
        CrewFilter.alerts => 'Active alerts',
      };
}

/// Shared colour/label for a member's data-link state. "Connected" means data
/// arrived recently; it is derived from data freshness, never assumed.
(String, Color, IconData) connectionStyle(Connection c) => switch (c) {
      Connection.connected => ('Connected', AC.green, Icons.sensors_rounded),
      Connection.disconnected => ('Disconnected', AC.red, Icons.sensors_off_rounded),
      Connection.unknown => ('No data', AC.textDim, Icons.help_outline_rounded),
    };

class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key});

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  CrewFilter _filter = CrewFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final canSeeOthers = c.accessPolicy.canViewOtherAstronauts(c.settings.role);
    final visible = canSeeOthers ? c.crew : c.crew.where((a) => a.id == c.selected.id).toList();
    final filtered = visible.where((a) {
      final conn = c.connectionOf(a.id);
      return switch (_filter) {
        CrewFilter.all => true,
        CrewFilter.connected => conn == Connection.connected,
        CrewFilter.disconnected => conn != Connection.connected,
        CrewFilter.alerts => c.openAlertsFor(a.id).isNotEmpty,
      };
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              c.lastScanAt == null ? 'Not scanned yet' : 'Last scan ${fmtTime(c.lastScanAt!)}',
              style: const TextStyle(color: AC.textDim, fontSize: 12),
            ),
          ),
          if (c.linkService.isSimulated) const DemoBadge(label: 'SIMULATED LINKS', dense: true),
          const SizedBox(width: Sp.s),
          FilledButton.tonalIcon(
            onPressed: c.scanning ? null : c.scanLinks,
            icon: c.scanning
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar_rounded, size: 18),
            label: Text(c.scanning ? 'Scanning…' : 'Scan'),
          ),
        ]),
        const SizedBox(height: Sp.m),
        if (c.linkMessage != null)
          InfoBanner(c.linkMessage!, icon: Icons.bluetooth_disabled_rounded, color: AC.amber)
        else if (c.links.isNotEmpty) ...[
          AtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Network', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              const Text(
                'Cyan = receiving data · red = data stopped. Tap a node for details.',
                style: TextStyle(color: AC.textDim, fontSize: 12),
              ),
              const SizedBox(height: Sp.s),
              TopologyView(
                crew: visible,
                links: c.links,
                connected: (id) => c.connectionOf(id) == Connection.connected,
                onTapMember: (id) => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => MemberDetailScreen(astronautId: id))),
              ),
              const SizedBox(height: Sp.s),
              const Wrap(spacing: Sp.l, runSpacing: 4, children: [
                _LegendItem('Solid thick', 'Base station'),
                _LegendItem('Solid thin', 'Bluetooth'),
                _LegendItem('Dotted', 'Local network'),
                _LegendItem('Dashed', 'Mesh relay'),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: Sp.m),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in CrewFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: Sp.s),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        const SizedBox(height: Sp.m),
        if (filtered.isEmpty)
          const AtCard(
            child: EmptyState(icon: Icons.group_off_outlined, title: 'No crew match this filter'),
          )
        else
          for (final a in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.m),
              child: _CrewCard(c: c, a: a),
            ),
        const Padding(
          padding: EdgeInsets.only(top: Sp.s),
          child: Text(
            'Link quality is shown only when a link service reports it. Distance is shown only with real positioning data.',
            style: TextStyle(color: AC.textDim, fontSize: 11, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.style, this.label);
  final String style;
  final String label;
  @override
  Widget build(BuildContext context) => Text('$style = $label', style: const TextStyle(color: AC.textDim, fontSize: 11));
}

class _CrewCard extends StatelessWidget {
  const _CrewCard({required this.c, required this.a});
  final AppController c;
  final Astronaut a;

  @override
  Widget build(BuildContext context) {
    final conn = c.connectionOf(a.id);
    final (cLabel, cColor, cIcon) = connectionStyle(conn);
    final seen = c.samples.lastSeen(a.id);
    final status = c.monitoringStatus(a.id);
    final risk = c.riskClassOf(a.id);
    final link = c.links[a.id];
    final devs = c.devices.where((d) => d.astronautId == a.id).toList();
    final alerts = c.openAlertsFor(a.id).length;
    final devState = switch (conn) {
      Connection.connected => 'online',
      Connection.disconnected => 'offline (no recent data)',
      Connection.unknown => 'unknown',
    };

    return AtCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberDetailScreen(astronautId: a.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tint(AC.cyan, 0.15),
            child: Text(a.callsign.isEmpty ? '?' : a.callsign.substring(0, 1), style: const TextStyle(color: AC.cyan)),
          ),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.callsign, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text('${a.name} · ${a.role.label}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
            ]),
          ),
          Pill(cLabel, color: cColor, icon: cIcon),
        ]),
        const SizedBox(height: Sp.m),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(status.label, color: statusColor(status), icon: statusIcon(status), dense: true),
          if (risk != null) Pill('AI: ${risk.label}', color: riskColor(risk), dense: true),
          if (alerts > 0) Pill('$alerts active alert${alerts == 1 ? '' : 's'}', color: AC.amber, dense: true),
          if (a.isDemo) const DemoBadge(dense: true),
        ]),
        const SizedBox(height: Sp.s),
        KeyValueRow('Device', devs.isEmpty ? 'none registered' : '${devs.map((d) => d.name).join(', ')} · $devState'),
        KeyValueRow('Latest data', seen == null ? 'never' : '${fmtTime(seen)} · ${fmtAgo(seen)}'),
        if (link != null) ...[
          KeyValueRow('Link', '${link.transport.label}${link.viaId == null || link.viaId == 'base' ? '' : ' via ${_name(link.viaId!)}'}'),
          if (link.linkQuality != null)
            KeyValueRow('Link quality', '${(link.linkQuality! * 100).round()}%${link.simulated ? ' (simulated)' : ''}'),
          if (link.distanceMeters != null) KeyValueRow('Distance', '${link.distanceMeters!.round()} m'),
          KeyValueRow('Last sync', link.lastSyncAt == null ? 'not reported' : fmtAgo(link.lastSyncAt)),
        ] else
          const KeyValueRow('Link', 'not discovered'),
      ]),
    );
  }

  String _name(String id) {
    for (final m in c.crew) {
      if (m.id == id) return m.callsign;
    }
    return id;
  }
}
