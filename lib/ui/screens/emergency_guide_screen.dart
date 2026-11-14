import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../emergency/knowledge_base.dart';
import '../../state/wellness_state.dart';
import 'laila_screen.dart';

Color severityColor(int s) => switch (s) {
      3 => const Color(0xFFE5484D),
      2 => const Color(0xFFF76B15),
      _ => const Color(0xFFFFB224),
    };

String severityLabel(int s, bool ar) => switch (s) {
      3 => ar ? 'حرج' : 'Critical',
      2 => ar ? 'خطير' : 'Serious',
      _ => ar ? 'انتباه' : 'Attention',
    };

/// Standalone library: pick any condition and read its guide.
class EmergencyGuideScreen extends StatefulWidget {
  const EmergencyGuideScreen({super.key});
  @override
  State<EmergencyGuideScreen> createState() => _EmergencyGuideScreenState();
}

class _EmergencyGuideScreenState extends State<EmergencyGuideScreen> {
  EmergencyKind _kind = EmergencyKind.syncope;

  @override
  Widget build(BuildContext context) {
    final p = protocolFor(_kind);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency guidance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<EmergencyKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Condition', border: OutlineInputBorder()),
            items: [for (final k in EmergencyKind.values) DropdownMenuItem(value: k, child: Text(protocolFor(k).title.en, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          EmergencyGuideView(key: ValueKey(_kind), protocol: p, severity: p.severity),
        ],
      ),
    );
  }
}

/// The guidance panel. Instructions are shown in full, one tap away from nothing:
/// no menus hide a step. Steps double as the response checklist.
class EmergencyGuideView extends StatefulWidget {
  const EmergencyGuideView({
    super.key,
    required this.protocol,
    required this.severity,
    this.indicators = const {},
    this.reported = const [],
    this.uncertainty,
    this.simulated = false,
    this.initialRole = Role.self,
    this.initialPlace = Place.cabin,
  });
  final Protocol protocol;
  final int severity;
  final Map<String, String> indicators;
  final List<String> reported;
  final String? uncertainty;
  final bool simulated;
  final Role initialRole;
  final Place initialPlace;

  @override
  State<EmergencyGuideView> createState() => _EmergencyGuideViewState();
}

class _EmergencyGuideViewState extends State<EmergencyGuideView> {
  late Role _role = widget.initialRole;
  late Place _place = widget.initialPlace;
  bool _ar = false;
  final Set<int> _done = {};
  final List<String> _log = [];
  bool _notified = false;

  String _now() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  @override
  void initState() {
    super.initState();
    _log.add('${_now()}  Guide opened: ${widget.protocol.title.en}');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.protocol;
    final g = p.guide(_role);
    final steps = <Tx>[p.place[_place]!, ...g.steps];
    final color = severityColor(widget.severity);
    final theme = Theme.of(context);
    final ar = _ar;

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: color.withValues(alpha: 0.14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? 'حالة طوارئ محتملة' : 'CURRENT EMERGENCY (POSSIBLE)', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(p.title.of(ar), style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(p.possibility.of(ar)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Chip(label: Text('${ar ? 'الخطورة' : 'Severity'}: ${severityLabel(widget.severity, ar)}'), backgroundColor: color.withValues(alpha: 0.3)),
                  if (widget.simulated) Chip(label: Text(ar ? 'محاكاة' : 'SIMULATED')),
                ]),
                if (widget.uncertainty != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(widget.uncertainty!)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('EN')), ButtonSegment(value: true, label: Text('عربي'))],
              selected: {_ar},
              onSelectionChanged: (v) => setState(() => _ar = v.first),
            ),
            SegmentedButton<Place>(
              segments: [
                ButtonSegment(value: Place.cabin, label: Text(ar ? 'داخل المركبة' : 'In cabin')),
                ButtonSegment(value: Place.eva, label: Text(ar ? 'مهمة خارجية' : 'EVA')),
                ButtonSegment(value: Place.ground, label: Text(ar ? 'أرض' : 'Ground')),
              ],
              selected: {_place},
              onSelectionChanged: (v) => setState(() {
                _place = v.first;
                _done.clear();
              }),
            ),
            SegmentedButton<Role>(
              segments: [
                ButtonSegment(value: Role.self, label: Text(ar ? 'أنا المصاب' : 'It is me')),
                ButtonSegment(value: Role.helper, label: Text(ar ? 'أساعد زميلًا' : 'I am helping')),
              ],
              selected: {_role},
              onSelectionChanged: (v) => setState(() {
                _role = v.first;
                _done.clear();
              }),
            ),
          ]),
          if (widget.indicators.isNotEmpty || widget.reported.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(ar ? 'المؤشرات المرصودة' : 'Detected indicators', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in widget.indicators.entries) Chip(label: Text('${e.key}  ${e.value}')),
              for (final r in widget.reported) Chip(label: Text(r)),
            ]),
          ],
          const SizedBox(height: 12),
          Text(ar ? 'ماذا تفعل الآن' : 'WHAT TO DO NOW', style: theme.textTheme.titleMedium),
          Text(g.title.of(ar), style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++)
            Card(
              child: CheckboxListTile(
                value: _done.contains(i),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${ar ? 'الخطوة' : 'Step'} ${i + 1}${i == 0 ? (ar ? '  (حسب مكانك)' : '  (where you are)') : ''}', style: theme.textTheme.labelMedium),
                subtitle: Text(steps[i].of(ar), style: theme.textTheme.bodyMedium),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _done.add(i);
                    _log.add('${_now()}  Step ${i + 1} done');
                  } else {
                    _done.remove(i);
                  }
                }),
              ),
            ),
          Text('${_done.length}/${steps.length} ${ar ? 'خطوات مكتملة. القائمة لا تغني عن التقييم الطبي الفعلي.' : 'steps done. This checklist never replaces a real clinical assessment.'}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D), minimumSize: const Size.fromHeight(48)),
            onPressed: _notified
                ? null
                : () => setState(() {
                      _notified = true;
                      _log.add('${_now()}  Mission control notified (simulated)');
                    }),
            icon: const Icon(Icons.phone_in_talk_rounded),
            label: Text(_notified ? (ar ? 'تم إبلاغ مركز التحكم (محاكاة)' : 'Mission control notified (simulated)') : (ar ? 'تواصل مع الدعم الطبي (محاكاة)' : 'Contact mission medical support (simulated)')),
          ),
          if (p.kind == EmergencyKind.psychological) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () {
                  context.read<WellnessState>().requestHumanSupport();
                  setState(() => _log.add('${_now()}  Human support requested'));
                },
                icon: const Icon(Icons.support_agent_rounded),
                label: Text(ar ? 'أحتاج شخصًا الآن' : 'I need a person now'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LailaScreen())),
                icon: const Icon(Icons.favorite_rounded),
                label: Text(ar ? 'تحدث مع ليلى' : 'Talk to Laila'),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _block(context, ar ? 'تجنّب' : 'AVOID', p.avoid.map((e) => e.of(ar)).toList(), const Color(0xFFE5484D)),
          _block(context, ar ? 'متى تصعّد الأمر' : 'WHEN TO ESCALATE', p.escalate.map((e) => e.of(ar)).toList(), const Color(0xFFF76B15)),
          _block(context, ar ? 'معايير الاشتباه' : 'WHAT POINTS TO THIS', p.criteria.map((e) => e.of(ar)).toList(), null),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? 'الأرض مقابل الفضاء' : 'GROUND VS SPACEFLIGHT', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(p.space.of(ar)),
                const SizedBox(height: 4),
                Text(kSpaceFallback.of(ar), style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
          Text(ar ? 'سجل الحدث' : 'Event timeline', style: theme.textTheme.titleSmall),
          for (final l in _log) Text(l, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(ar ? 'المصادر' : 'Sources', style: theme.textTheme.titleSmall),
          for (final s in p.sources)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.org}: ${s.doc}', style: theme.textTheme.bodyMedium),
                SelectableText(s.url, style: theme.textTheme.bodySmall),
                Text('Published: ${s.published ?? 'not stated on the page'}', style: theme.textTheme.bodySmall),
                Text('Checked: ${s.checked}', style: theme.textTheme.bodySmall),
              ]),
            ),
          const SizedBox(height: 8),
          Text('${ar ? 'حالة المراجعة' : 'Review status'}: ${p.reviewStatus}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(kDisclaimer.of(ar), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, String title, List<String> items, Color? c) {
    return Card(
      color: c?.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final i in items) Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $i')),
        ]),
      ),
    );
  }
}
