import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../../state/wellness_state.dart';
import '../export_helper.dart';
import '../widgets/common.dart';

/// Flight-surgeon brief: a plain-text summary the crew member can read, copy,
/// share or queue for the ground. Delay-aware: shows the earliest possible reply.
class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key});

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _QueuedBrief {
  _QueuedBrief(this.sentAt, this.earliest, this.latest, this.simulated);
  final DateTime sentAt;
  final DateTime earliest;
  final DateTime latest;
  final bool simulated;
}

class _BriefScreenState extends State<BriefScreen> {
  final List<_QueuedBrief> _queue = [];
  Timer? _tick;
  late String _text;
  late DateTime _builtAt;

  @override
  void initState() {
    super.initState();
    _build();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _queue.isNotEmpty) setState(() {});
    });
  }

  void _build() {
    _builtAt = DateTime.now();
    _text = context.read<WellnessState>().buildBrief();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _remaining(Duration d) {
    final s = d.inSeconds.clamp(0, 1 << 30);
    return '${two(s ~/ 60)}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WellnessState>();
    final c = context.read<AppController>();
    final env = w.environment;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Flight-surgeon brief')),
      body: ListView(padding: const EdgeInsets.all(Sp.l), children: [
        AtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.public_rounded, color: AC.cyan, size: 20),
              const SizedBox(width: Sp.s),
              Expanded(child: Text(env.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: Sp.s),
            KeyValueRow('One-way delay to Earth', env.delayText),
            if (env.autonomous) ...[
              KeyValueRow('Earliest reply (if sent now)', fmtTime(env.replyWindow(now).$1, seconds: false)),
              KeyValueRow('Latest reply (if sent now)', fmtTime(env.replyWindow(now).$2, seconds: false)),
            ],
            const SizedBox(height: Sp.s),
            Text(env.autonomyNote, style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.3)),
          ]),
        ),
        if (c.isSimulated) ...[
          const SizedBox(height: Sp.m),
          const InfoBanner('This brief is built from SIMULATED demo data.', icon: Icons.science_outlined, color: AC.amber),
        ],
        SectionHeader('Brief', subtitle: 'Prepared ${fmtTime(_builtAt, seconds: false)}'),
        AtCard(child: SelectableText(_text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45))),
        const SizedBox(height: Sp.m),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(_build),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ),
          const SizedBox(width: Sp.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _text));
                if (context.mounted) showSnack(context, 'Brief copied.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          ),
          const SizedBox(width: Sp.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => shareText(context, 'ATHERA health brief', _text),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Share'),
            ),
          ),
        ]),
        const SizedBox(height: Sp.m),
        FilledButton.icon(
          onPressed: () {
            final sentAt = DateTime.now();
            final (lo, hi) = env.replyWindow(sentAt);
            setState(() => _queue.insert(0, _QueuedBrief(sentAt, lo, hi, c.isSimulated)));
            showSnack(context, 'Brief queued for the ground (simulated link).');
          },
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Queue for the ground')),
        ),
        const SizedBox(height: Sp.s),
        const Text(
          'No ground station is connected in this prototype, so queuing only simulates the delay. It never claims a message was received.',
          style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.3),
        ),
        if (_queue.isNotEmpty) ...[
          const SectionHeader('Queued briefs'),
          for (final q in _queue)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s),
              child: AtCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Queued ${fmtTime(q.sentAt, seconds: false)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    const Pill('SIMULATED LINK', color: AC.blue, dense: true),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    now.isBefore(q.earliest)
                        ? 'Earliest possible reply in ${_remaining(q.earliest.difference(now))}'
                        : 'Reply window is open. No ground station is connected, so no reply can arrive here.',
                    style: const TextStyle(color: AC.textDim, fontSize: 12),
                  ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
