import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Emergency screen: one big action, honest delivery state, full history.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _sending = false;

  Future<void> _confirmAndSend(AppController c) async {
    var severity = EmergencySeverity.critical;
    final transport = c.sos.transport;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AC.surface,
          title: const Row(children: [
            Icon(Icons.sos_rounded, color: AC.red),
            SizedBox(width: Sp.s),
            Text('Send emergency SOS?'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('From ${c.selected.callsign} to ${c.sosRecipients.map((r) => r.name).join(', ')}.'),
            const SizedBox(height: Sp.m),
            SegmentedButton<EmergencySeverity>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: EmergencySeverity.high, label: Text('High')),
                ButtonSegment(value: EmergencySeverity.critical, label: Text('Critical')),
              ],
              selected: {severity},
              onSelectionChanged: (s) => setLocal(() => severity = s.first),
            ),
            const SizedBox(height: Sp.m),
            Text(
              transport.isAvailable
                  ? (transport.isSimulated
                      ? 'Transport: ${transport.name}. Delivery and acknowledgement are SIMULATED. Nothing is actually transmitted.'
                      : 'Transport: ${transport.name}.')
                  : 'No working transport in this build. The event will be recorded on this device but NOT delivered.',
              style: TextStyle(color: transport.isAvailable ? AC.textDim : AC.amber, fontSize: 13, height: 1.35),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AC.sosRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send SOS'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      final e = await c.triggerSos(severity);
      if (mounted) {
        showSnack(
          context,
          e.transportAvailable ? 'SOS recorded and handed to the transport.' : 'SOS recorded locally. NOT delivered: no transport.',
          error: !e.transportAvailable,
        );
      }
    } catch (err) {
      if (mounted) showSnack(context, 'Could not record SOS: $err', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final events = c.sos.events;
    final active = c.sos.active;
    final history = events.where((e) => e.id != active?.id).toList();
    final t = c.sos.transport;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: 'Send emergency SOS',
              child: SizedBox(
                width: 168,
                height: 168,
                child: ElevatedButton(
                  onPressed: _sending ? null : () => _confirmAndSend(c),
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: AC.sosRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: tint(AC.sosRed, 0.4),
                    elevation: 0,
                  ),
                  child: _sending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.sos_rounded, size: 52),
                          SizedBox(height: 4),
                          Text('SOS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3)),
                        ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.m),
          const Center(
            child: Text('You will be asked to confirm before anything is sent.', style: TextStyle(color: AC.textDim, fontSize: 12)),
          ),
          const SizedBox(height: Sp.l),
          InfoBanner(
            t.isAvailable
                ? (t.isSimulated
                    ? 'DEMO: transport "${t.name}" simulates delivery, relay and acknowledgement. No real message leaves this device.'
                    : 'Transport: ${t.name}${t.capabilities.supportsAck ? ' · acknowledgements supported' : ' · no acknowledgements'}${t.capabilities.supportsRelay ? ' · relay supported' : ''}.')
                : 'No emergency transport is configured. SOS events are saved locally but cannot reach anyone. See docs/HARDWARE.md for BLE, LoRa or mesh options.',
            icon: t.isAvailable ? Icons.settings_input_antenna_rounded : Icons.signal_wifi_off_rounded,
            color: t.isAvailable ? AC.blue : AC.amber,
          ),
          if (active != null) ...[
            const SectionHeader('Active event'),
            _EventCard(c: c, e: active, initiallyExpanded: true),
          ],
          SectionHeader('History', subtitle: '${events.length} event${events.length == 1 ? '' : 's'} stored on this device'),
          if (history.isEmpty && active == null)
            const AtCard(child: Text('No emergency events yet.', style: TextStyle(color: AC.textDim)))
          else
            for (final e in history) Padding(padding: const EdgeInsets.only(bottom: Sp.s), child: _EventCard(c: c, e: e)),
        ],
      ),
    );
  }
}

Color _statusColor(EmergencyStatus s) => switch (s) {
      EmergencyStatus.acknowledged => AC.green,
      EmergencyStatus.delivered => AC.green,
      EmergencyStatus.partiallyDelivered => AC.amber,
      EmergencyStatus.sending || EmergencyStatus.recorded => AC.blue,
      EmergencyStatus.failed => AC.red,
      EmergencyStatus.closed => AC.textDim,
    };

(String, Color) _deliveryStyle(DeliveryState s) => switch (s) {
      DeliveryState.pending => ('Pending', AC.textDim),
      DeliveryState.sending => ('Sending', AC.blue),
      DeliveryState.delivered => ('Delivered', AC.green),
      DeliveryState.acknowledged => ('Acknowledged', AC.green),
      DeliveryState.failed => ('Failed', AC.red),
    };

class _EventCard extends StatelessWidget {
  const _EventCard({required this.c, required this.e, this.initiallyExpanded = false});
  final AppController c;
  final EmergencyEvent e;
  final bool initiallyExpanded;

  String _who(String id) {
    for (final a in c.crew) {
      if (a.id == id) return '${a.callsign} (${a.name})';
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final status = e.status;
    final color = _statusColor(status);
    final acked = e.deliveries.where((d) => d.state == DeliveryState.acknowledged).toList();
    final maxAttempts = e.deliveries.isEmpty ? 0 : e.deliveries.map((d) => d.attempts).reduce((a, b) => a > b ? a : b);

    return AtCard(
      padding: EdgeInsets.zero,
      borderColor: e.closed ? AC.border : tint(color, 0.5),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
          title: Row(children: [
            Expanded(child: Text(e.severity == EmergencySeverity.critical ? 'Critical SOS' : 'High-priority SOS',
                style: const TextStyle(fontWeight: FontWeight.w600))),
            Pill(status.label, color: color),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${fmtDateTime(e.createdAt)} · ${_who(e.astronautId)}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
              if (e.simulated) const DemoBadge(label: 'SIMULATED', dense: true),
            ]),
          ),
          children: [
            KeyValueRow('Origin', '${_who(e.astronautId)} · device ${e.deviceId}'),
            KeyValueRow('Trigger', e.manual ? 'Manual' : 'Automatic'),
            KeyValueRow('Transport', '${e.transportName}${e.simulated ? ' (simulated)' : ''}'),
            KeyValueRow('Event ID', e.id),
            KeyValueRow('Acknowledgement',
                acked.isEmpty ? 'Not acknowledged' : 'By ${acked.map((d) => d.recipientName).join(', ')}',
                valueColor: acked.isEmpty ? AC.amber : AC.green),
            KeyValueRow('Attempts', maxAttempts == 0 ? 'none' : '$maxAttempts (max ${c.sos.maxAttempts})'),
            const SizedBox(height: Sp.s),
            const Align(alignment: Alignment.centerLeft, child: Text('RECIPIENTS', style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1))),
            const SizedBox(height: 4),
            if (e.deliveries.isEmpty)
              const Text('No recipients.', style: TextStyle(color: AC.textDim))
            else
              for (final d in e.deliveries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.recipientName),
                        Text(
                          [
                            if (d.via != null) 'via ${d.via}',
                            if (d.attempts > 0) '${d.attempts} attempt${d.attempts == 1 ? '' : 's'}',
                            if (d.lastError != null) d.lastError!,
                          ].join(' · '),
                          style: const TextStyle(color: AC.textDim, fontSize: 11),
                        ),
                      ]),
                    ),
                    Builder(builder: (_) {
                      final (l, col) = _deliveryStyle(d.state);
                      return Pill(l, color: col, dense: true);
                    }),
                  ]),
                ),
            if (e.snapshot.isNotEmpty) ...[
              const SizedBox(height: Sp.m),
              const Align(alignment: Alignment.centerLeft, child: Text('RECENT MEASUREMENTS AT SEND TIME', style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1))),
              const SizedBox(height: 4),
              for (final entry in e.snapshot.entries) _snapshotRow(entry.key, entry.value),
            ],
            const SizedBox(height: Sp.m),
            const Align(alignment: Alignment.centerLeft, child: Text('TIMELINE', style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1))),
            const SizedBox(height: 4),
            for (final t in e.timeline)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 64, child: Text(fmtTime(t.at), style: const TextStyle(color: AC.textDim, fontSize: 12, fontFeatures: kTabular))),
                  Expanded(child: Text(t.text, style: const TextStyle(fontSize: 13, height: 1.3))),
                ]),
              ),
            if (!e.closed) ...[
              const SizedBox(height: Sp.m),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await c.closeSos(e);
                    if (context.mounted) showSnack(context, 'Event closed. It stays in history.');
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Close event'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _snapshotRow(String key, Object? v) {
    final type = vitalFromKey(key);
    String text = '$v';
    if (v is Map) {
      final value = v['value'];
      final unit = v['unit'];
      final at = DateTime.tryParse('${v['at']}');
      final shown = value is num ? (type == null ? value.toString() : value.toStringAsFixed(type.decimals)) : '$value';
      text = '$shown $unit${at == null ? '' : ' · ${fmtTime(at)}'}';
    }
    return KeyValueRow(type?.label ?? key, text);
  }
}
