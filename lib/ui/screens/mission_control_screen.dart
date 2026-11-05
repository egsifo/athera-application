import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/rules.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/ai_models.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../vital_format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'crew_screen.dart' show connectionStyle;
import 'member_detail_screen.dart';

/// Commander / mission-control overview. Role gating here only shapes the UI:
/// the prototype has no authentication (see PrototypeAccessPolicy).
class MissionControlScreen extends StatefulWidget {
  const MissionControlScreen({super.key});

  @override
  State<MissionControlScreen> createState() => _MissionControlScreenState();
}

class _MissionControlScreenState extends State<MissionControlScreen> {
  int _sortCol = 0;
  bool _asc = true;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (!c.canViewMissionControl) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mission control')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Commander or mission-control role required',
          message: 'Prototype policy only: there is no real authentication yet. Change the role in Settings to preview this screen.',
        ),
      );
    }

    final rows = [for (final a in c.crew) _Row.of(c, a)];
    rows.sort((x, y) {
      final r = switch (_sortCol) {
        0 => x.a.callsign.compareTo(y.a.callsign),
        1 => x.status.index.compareTo(y.status.index),
        2 => x.riskRank.compareTo(y.riskRank),
        3 => (x.hr ?? -1).compareTo(y.hr ?? -1),
        4 => (x.spo2 ?? -1).compareTo(y.spo2 ?? -1),
        5 => (x.rr ?? -1).compareTo(y.rr ?? -1),
        6 => x.alerts.compareTo(y.alerts),
        _ => x.conn.index.compareTo(y.conn.index),
      };
      return _asc ? r : -r;
    });

    final connected = rows.where((r) => r.conn == Connection.connected).length;
    final alertTotal = rows.fold<int>(0, (s, r) => s + r.alerts);
    final critical = rows.where((r) => r.status == MonitoringStatus.critical || r.risk == RiskClass.critical).length;

    DataColumn col(String label, {bool numeric = false}) => DataColumn(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          numeric: numeric,
          onSort: (i, asc) => setState(() {
            _sortCol = i;
            _asc = asc;
          }),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Mission control')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
        children: [
          Row(children: [
            Expanded(child: _Tile('Crew', '${rows.length}', AC.cyan)),
            const SizedBox(width: Sp.s),
            Expanded(child: _Tile('Connected', '$connected/${rows.length}', connected == rows.length ? AC.green : AC.amber)),
            const SizedBox(width: Sp.s),
            Expanded(child: _Tile('Alerts', '$alertTotal', alertTotal == 0 ? AC.green : AC.amber)),
            const SizedBox(width: Sp.s),
            Expanded(child: _Tile('Critical', '$critical', critical == 0 ? AC.green : AC.red)),
          ]),
          const SectionHeader('Crew table', subtitle: 'Tap a column to sort · tap a row for detail'),
          AtCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                sortColumnIndex: _sortCol,
                sortAscending: _asc,
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 52,
                columnSpacing: 18,
                columns: [
                  col('Crew'),
                  col('Status'),
                  col('AI risk'),
                  col('HR', numeric: true),
                  col('SpO₂', numeric: true),
                  col('RR', numeric: true),
                  col('Alerts', numeric: true),
                  col('Link'),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      onSelectChanged: (_) => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => MemberDetailScreen(astronautId: r.a.id))),
                      cells: [
                        DataCell(Text(r.a.callsign, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Pill(r.status.label, color: statusColor(r.status), dense: true)),
                        DataCell(r.risk == null
                            ? const Text('—', style: TextStyle(color: AC.textDim))
                            : Pill(r.risk!.label, color: riskColor(r.risk), dense: true)),
                        DataCell(Text(r.hr == null ? '—' : r.hr!.round().toString())),
                        DataCell(Text(r.spo2 == null ? '—' : r.spo2!.round().toString())),
                        DataCell(Text(r.rr == null ? '—' : r.rr!.round().toString())),
                        DataCell(Text('${r.alerts}')),
                        DataCell(Builder(builder: (_) {
                          final (linkLabel, linkColor, _) = connectionStyle(r.conn);
                          return Text(linkLabel, style: TextStyle(color: linkColor, fontSize: 12));
                        })),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: Sp.s),
            child: Text('Latest valid reading per vital. "—" means no reading has been received.',
                style: TextStyle(color: AC.textDim, fontSize: 11)),
          ),
          const SectionHeader('Local network', subtitle: 'No positions are shown: no positioning data exists'),
          if (c.links.isEmpty)
            InfoBanner(c.linkMessage ?? 'No scan yet. Open the Crew tab and tap Scan.', icon: Icons.hub_outlined, color: AC.amber)
          else
            AtCard(
              child: TopologyView(
                crew: c.crew,
                links: c.links,
                connected: (id) => c.connectionOf(id) == Connection.connected,
                onTapMember: (id) => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => MemberDetailScreen(astronautId: id))),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row {
  _Row({
    required this.a,
    required this.status,
    required this.risk,
    required this.hr,
    required this.spo2,
    required this.rr,
    required this.alerts,
    required this.conn,
  });
  final Astronaut a;
  final MonitoringStatus status;
  final RiskClass? risk;
  final double? hr, spo2, rr;
  final int alerts;
  final Connection conn;
  int get riskRank => risk?.rank ?? -1;

  static _Row of(AppController c, Astronaut a) => _Row(
        a: a,
        status: c.monitoringStatus(a.id),
        risk: c.riskClassOf(a.id),
        hr: c.samples.latest(a.id, VitalType.heartRate)?.v,
        spo2: c.samples.latest(a.id, VitalType.spo2)?.v,
        rr: c.samples.latest(a.id, VitalType.respiratoryRate)?.v,
        alerts: c.openAlertsFor(a.id).length,
        conn: c.connectionOf(a.id),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return AtCard(
      padding: const EdgeInsets.symmetric(vertical: Sp.m, horizontal: Sp.s),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: color, fontFeatures: kTabular)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AC.textDim, fontSize: 11)),
      ]),
    );
  }
}
