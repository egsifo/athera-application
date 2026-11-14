import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../../state/wellness_state.dart';
import '../../wellness/body_systems.dart';
import '../../wellness/hazards.dart';
import '../../wellness/mission_env.dart';
import '../../wellness/routine.dart';
import '../../wellness/vital_status.dart';
import '../vital_format.dart';
import '../widgets/body_map.dart';
import '../widgets/common.dart' hide statusColor;
import '../widgets/guidance_card.dart';
import 'blood_screen.dart';
import 'brief_screen.dart';
import 'check_in_screen.dart';
import 'hazards_screen.dart';
import 'insights_screen.dart';
import 'laila_screen.dart';
import 'mind_screen.dart';
import 'radiation_screen.dart';
import 'sim_screen.dart';

/// Self-assessment hub: guidance, body map, daily routine, check-in, hazards.
class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final w = context.watch<WellnessState>();
    final g = w.guidance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xl),
      children: [
        Row(children: [
          const Expanded(child: Text('My health', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          _EnvChip(c: c),
        ]),
        const SizedBox(height: Sp.m),
        GuidanceCard(
          guidance: g,
          onBrief: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BriefScreen())),
        ),
        const SectionHeader('Explore', subtitle: 'Insights from your data and real NASA measurements'),
        _NavTile(
          icon: Icons.emergency_rounded,
          title: 'Emergency simulator',
          subtitle: 'Fainting, hypoxia, radiation, lost astronaut (simulated)',
          builder: (_) => const SimScreen(),
        ),
        _NavTile(
          icon: Icons.psychology_alt_rounded,
          title: 'Astro Mind',
          subtitle: 'Well-being, support alerts, simulations',
          builder: (_) => const MindScreen(),
        ),
        _NavTile(
          icon: Icons.favorite_rounded,
          title: 'Laila, your companion',
          subtitle: 'Offline emotional support, English and Arabic',
          builder: (_) => const LailaScreen(),
        ),
        _NavTile(
          icon: Icons.insights_rounded,
          title: 'Personal insights',
          subtitle: 'Data quality, your baseline, unusual patterns, trends',
          builder: (_) => const InsightsScreen(),
        ),
        _NavTile(
          icon: Icons.radar_rounded,
          title: 'ISS radiation (real data)',
          subtitle: 'NASA RadLab dose rates 2019-2024',
          builder: (_) => const RadiationScreen(),
        ),
        _NavTile(
          icon: Icons.bloodtype_outlined,
          title: 'Crew blood tests (real data)',
          subtitle: 'Inspiration4, before and after flight',
          builder: (_) => const BloodScreen(),
        ),
        const SectionHeader('Body map', subtitle: 'Tap a system to learn what it does and how to check it'),
        AtCard(
          child: Column(children: [
            SizedBox(
              height: 340,
              child: BodyMap(
                statusOf: (s) => _systemStatus(c, w, s),
                onSelect: (s) => _showSystem(context, c, w, s),
              ),
            ),
            const SizedBox(height: Sp.s),
            const Wrap(spacing: Sp.m, runSpacing: 4, alignment: WrapAlignment.center, children: [
              _Legend('In range', AC.green),
              _Legend('Watch', AC.amber),
              _Legend('Check now', AC.red),
              _Legend('No data', AC.textDim),
            ]),
          ]),
        ),
        const SectionHeader('Today\'s routine', subtitle: 'Mission habits protect your health'),
        _RoutineCard(w: w),
        const SectionHeader('Daily check-in'),
        _CheckInCard(w: w),
        const SectionHeader('Spaceflight hazards', subtitle: 'The five risks NASA tracks, and how ATHERA helps'),
        for (final h in kHazards) _HazardTile(h: h, c: c),
        const SizedBox(height: Sp.l),
        const Text(
          'Guidance is decision support from simple rules. It is not a diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AC.textDim, fontSize: 11),
        ),
      ],
    );
  }
}

VStatus _vitalsStatus(AppController c, Iterable<VitalType> types) {
  final now = DateTime.now().toUtc();
  return worst([
    for (final t in types)
      () {
        final s = c.samples.latest(c.selected.id, t);
        if (s == null || now.difference(s.t) > const Duration(minutes: 30)) return VStatus.none;
        return vitalStatus(t, s.v);
      }(),
  ]);
}

VStatus _systemStatus(AppController c, WellnessState w, BodySystem s) {
  switch (s.id) {
    case 'mind':
      final ci = w.todayCheckIn;
      if (ci == null) return VStatus.none;
      return (ci.sleepHours < 5 || ci.mood <= 2 || ci.stress >= 4) ? VStatus.watch : VStatus.ok;
    case 'muscle':
      if (w.routine.isEmpty) return VStatus.none;
      return w.exerciseAdherence() >= 0.5 ? VStatus.ok : VStatus.watch;
    default:
      return _vitalsStatus(c, s.vitals);
  }
}

void _showSystem(BuildContext context, AppController c, WellnessState w, BodySystem s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AC.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scroll) => _SystemSheet(c: c, w: w, s: s, controller: scroll),
    ),
  );
}

class _SystemSheet extends StatelessWidget {
  const _SystemSheet({required this.c, required this.w, required this.s, required this.controller});
  final AppController c;
  final WellnessState w;
  final BodySystem s;
  final ScrollController controller;

  Widget _block(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final status = _systemStatus(c, w, s);
    final color = statusColor(status);
    return ListView(controller: controller, padding: const EdgeInsets.all(Sp.l), children: [
      Row(children: [
        Icon(systemIcon(s.id), color: color),
        const SizedBox(width: Sp.m),
        Expanded(child: Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
        Pill(statusWord(status), color: color),
      ]),
      const SizedBox(height: Sp.l),
      _block('What it does', s.does),
      _block('In space', s.spaceEffect),
      if (s.vitals.isNotEmpty) ...[
        const Text('YOUR READINGS',
            style: TextStyle(color: AC.textDim, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final t in s.vitals) _ReadingRow(c: c, t: t),
        const SizedBox(height: Sp.m),
      ],
      if (s.id == 'mind')
        _block(
          'Today',
          w.todayCheckIn == null
              ? 'No check-in yet today.'
              : 'Sleep ${w.todayCheckIn!.sleepHours.toStringAsFixed(1)} h, mood ${w.todayCheckIn!.mood}/5, '
                  'fatigue ${w.todayCheckIn!.fatigue}/5, stress ${w.todayCheckIn!.stress}/5.',
        ),
      if (s.id == 'muscle')
        _block('Exercise this week', '${(w.exerciseAdherence() * 7).round()} of 7 sessions completed.'),
      _block('How to measure', s.howToMeasure),
      _block('Ask for help if', s.seeDoctorIf),
      Wrap(spacing: Sp.s, children: [
        for (final id in s.hazards)
          Pill(kHazards.firstWhere((h) => h.id == id).name, color: AC.blue, dense: true),
      ]),
      const SizedBox(height: Sp.m),
      if (s.id == 'mind' || s.id == 'muscle')
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (s.id == 'mind') {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CheckInScreen()));
            }
          },
          child: Text(s.id == 'mind' ? 'Do today\'s check-in' : 'Close'),
        ),
    ]);
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.c, required this.t});
  final AppController c;
  final VitalType t;

  @override
  Widget build(BuildContext context) {
    final s = c.samples.latest(c.selected.id, t);
    final now = DateTime.now().toUtc();
    final fresh = s != null && now.difference(s.t) <= const Duration(minutes: 30);
    final st = fresh ? vitalStatus(t, s.v) : VStatus.none;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(t.label, style: const TextStyle(color: AC.textDim))),
        Text(
          fresh ? '${valueText(c, t, s.v)} ${unitOf(c, t)}' : 'No recent reading',
          style: TextStyle(fontWeight: FontWeight.w600, color: fresh ? statusColor(st) : AC.textDim),
        ),
        const SizedBox(width: Sp.s),
        Pill(statusWord(st), color: statusColor(st), dense: true),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AC.textDim, fontSize: 11)),
      ]);
}

class _EnvChip extends StatelessWidget {
  const _EnvChip({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final env = c.missionEnvironment;
    return ActionChip(
      avatar: const Icon(Icons.public_rounded, size: 16, color: AC.cyan),
      label: Text('${env.shortLabel} · ${env.delayText}'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AC.surface,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Sp.l, Sp.l, Sp.l, Sp.s),
              child: Text('Where is the crew?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final e in MissionEnvironment.values)
              ListTile(
                leading: Icon(e == env ? Icons.radio_button_checked : Icons.radio_button_off, color: AC.cyan),
                title: Text(e.label),
                subtitle: Text('One-way delay to Earth: ${e.delayText}'),
                onTap: () {
                  c.setMissionEnvironment(e);
                  Navigator.of(ctx).pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
              child: Text(env.autonomyNote, style: const TextStyle(color: AC.textDim, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.w});
  final WellnessState w;

  @override
  Widget build(BuildContext context) {
    final done = w.doneToday;
    final now = DateTime.now();
    final pts = w.pointsToday;
    final total = RoutineProgress.totalPoints;
    return AtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$pts / $total readiness points', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : pts / total,
                  minHeight: 6,
                  backgroundColor: AC.border,
                  color: AC.cyan,
                ),
              ),
            ]),
          ),
          const SizedBox(width: Sp.l),
          Column(children: [
            Text('${w.streak}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AC.cyan)),
            const Text('day streak', style: TextStyle(color: AC.textDim, fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: Sp.s),
        for (final t in kRoutine) _TaskRow(t: t, state: RoutineProgress.stateOf(t, now, done), onToggle: () => w.toggleTask(t.id)),
        if (w.error != null) Text(w.error!, style: const TextStyle(color: AC.red, fontSize: 12)),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.t, required this.state, required this.onToggle});
  final RoutineTask t;
  final TaskState state;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final done = state == TaskState.done;
    final (word, color) = switch (state) {
      TaskState.done => ('Done', AC.green),
      TaskState.due => ('Due now', AC.cyan),
      TaskState.overdue => ('Overdue', AC.amber),
      TaskState.upcoming => ('At ${two(t.dueHour)}:00', AC.textDim),
    };
    return Semantics(
      label: '${t.title}. $word. Double tap to ${done ? 'mark as not done' : 'mark as done'}.',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ExcludeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? AC.green : color, size: 22),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title,
                      style: TextStyle(
                          fontSize: 14, decoration: done ? TextDecoration.lineThrough : null, color: done ? AC.textDim : AC.text)),
                  if (!done) Text(t.detail, style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.3)),
                ]),
              ),
              const SizedBox(width: Sp.s),
              Pill(word, color: color, dense: true),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.w});
  final WellnessState w;

  @override
  Widget build(BuildContext context) {
    final ci = w.todayCheckIn;
    final last7 = w.checkIns.take(7).toList().reversed.toList();
    return AtCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CheckInScreen())),
      semanticsLabel: ci == null ? 'Daily check-in not done. Open.' : 'Daily check-in done. Open to edit.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ci == null ? Icons.edit_note_rounded : Icons.check_circle_outline_rounded, color: ci == null ? AC.cyan : AC.green),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Text(
              ci == null ? 'Not done yet today. Takes under a minute.' : 'Done today. Tap to edit.',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AC.textDim),
        ]),
        if (last7.length >= 2) ...[
          const SizedBox(height: Sp.m),
          _MiniBars(label: 'Sleep (h)', values: [for (final x in last7) x.sleepHours], max: 10, color: AC.blue),
          const SizedBox(height: Sp.s),
          _MiniBars(label: 'Mood (1-5)', values: [for (final x in last7) x.mood.toDouble()], max: 5, color: AC.cyan),
        ],
      ]),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.label, required this.values, required this.max, required this.color});
  final String label;
  final List<double> values;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 78, child: Text(label, style: const TextStyle(color: AC.textDim, fontSize: 11))),
      Expanded(
        child: SizedBox(
          height: 26,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final v in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    height: 4 + 22 * (v / max).clamp(0.0, 1.0),
                    decoration: BoxDecoration(color: tint(color, 0.7), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _HazardTile extends StatelessWidget {
  const _HazardTile({required this.h, required this.c});
  final SpaceHazard h;
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final st = h.vitals.isEmpty ? VStatus.none : _vitalsStatus(c, h.vitals);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s),
      child: AtCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HazardsScreen(initialId: h.id))),
        semanticsLabel: '${h.name}. Open details.',
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(h.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AC.textDim, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: Sp.s),
          if (h.vitals.isNotEmpty) Pill(statusWord(st), color: statusColor(st), dense: true),
          const Icon(Icons.chevron_right_rounded, color: AC.textDim),
        ]),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.subtitle, required this.builder});
  final IconData icon;
  final String title, subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.s),
        child: AtCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
          child: Row(children: [
            Icon(icon, color: AC.cyan),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: AC.textDim, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AC.textDim),
          ]),
        ),
      );
}
