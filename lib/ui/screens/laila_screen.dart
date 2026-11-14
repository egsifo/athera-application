import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../mind/laila.dart';
import '../../state/wellness_state.dart';

class _Msg {
  const _Msg(this.text, this.fromUser, {this.urgent = false});
  final String text;
  final bool fromUser;
  final bool urgent;
}

/// Offline chat with Laila. No network, no external AI.
class LailaScreen extends StatefulWidget {
  const LailaScreen({super.key, this.replyDelay = const Duration(milliseconds: 900)});
  final Duration replyDelay;

  @override
  State<LailaScreen> createState() => _LailaScreenState();
}

class _LailaScreenState extends State<LailaScreen> {
  late final LailaEngine _engine = LailaEngine();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  LailaLang _lang = LailaLang.en;
  bool _typing = false;
  bool _urgent = false;
  bool _offerBreathing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _engine.scenario = context.read<WellnessState>().lailaScenario;
    _msgs.add(_Msg(LailaEngine.welcome(_lang), false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty || _typing) return;
    _ctrl.clear();
    final reply = _engine.respond(t);
    setState(() {
      _msgs.add(_Msg(t, true));
      _typing = true;
    });
    _toEnd();
    _timer = Timer(widget.replyDelay, () {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _msgs.add(_Msg(reply.text, false, urgent: reply.urgent));
        if (reply.urgent) _urgent = true;
        _offerBreathing = reply.offerBreathing && !reply.urgent;
      });
      if (reply.urgent) context.read<WellnessState>().requestHumanSupport();
      _toEnd();
    });
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void _setLang(LailaLang l) {
    if (l == _lang) return;
    setState(() {
      _lang = l;
      _msgs.add(_Msg(LailaEngine.welcome(l), false));
    });
    _toEnd();
  }

  static const _starters = {
    LailaLang.en: ["I'm feeling lonely", "I'm stressed", "I can't sleep", "I'm exhausted", 'I feel sad', 'I feel better today'],
    LailaLang.ar: ['أشعر بالوحدة', 'أنا متوتر', 'لا أستطيع النوم', 'أنا مرهق', 'أشعر بالحزن', 'أشعر بتحسن اليوم'],
  };

  @override
  Widget build(BuildContext context) {
    final ar = _lang == LailaLang.ar;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(radius: 14, backgroundColor: AC.surface2, child: Icon(Icons.favorite_rounded, size: 16, color: AC.cyan)),
          SizedBox(width: Sp.s),
          Text('Laila'),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Sp.s),
            child: SegmentedButton<LailaLang>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [ButtonSegment(value: LailaLang.en, label: Text('EN')), ButtonSegment(value: LailaLang.ar, label: Text('عربي'))],
              selected: {_lang},
              onSelectionChanged: (s) => _setLang(s.first),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (_urgent) _UrgentBanner(onClear: () {
          context.read<WellnessState>().clearHumanSupport();
          _engine.reset();
          setState(() => _urgent = false);
        }),
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.all(Sp.l), children: [
            for (final m in _msgs) _Bubble(m: m),
            if (_typing) const _Typing(),
            if (_offerBreathing && !_typing)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => _breathing(context, ar),
                  icon: const Icon(Icons.air_rounded, size: 18),
                  label: Text(ar ? 'تمرين تنفس' : 'Breathing exercise'),
                ),
              ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Sp.l), children: [
            for (final s in _starters[_lang]!)
              Padding(padding: const EdgeInsets.only(right: Sp.s), child: ActionChip(label: Text(s), onPressed: () => _send(s))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.s),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(hintText: ar ? 'اكتب هنا…' : 'Write here…'),
              ),
            ),
            const SizedBox(width: Sp.s),
            IconButton.filled(onPressed: () => _send(_ctrl.text), icon: const Icon(Icons.send_rounded), tooltip: ar ? 'إرسال' : 'Send'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.s),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(LailaEngine.disclaimer[_lang]!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AC.textDim))),
            TextButton(
              onPressed: () {
                context.read<WellnessState>().requestHumanSupport();
                setState(() => _urgent = true);
              },
              child: Text(ar ? 'أحتاج دعماً بشرياً' : 'I need a person now', style: const TextStyle(color: AC.red, fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }

  void _breathing(BuildContext context, bool ar) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AC.surface,
        builder: (_) => _Breathing(ar: ar),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});
  final _Msg m;

  @override
  Widget build(BuildContext context) {
    final rtl = LailaEngine.detectLang(m.text) == LailaLang.ar;
    final color = m.urgent ? tint(AC.red, 0.25) : (m.fromUser ? tint(AC.cyan, 0.2) : AC.surface2);
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.s),
        padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: AC.border)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Text(m.text, style: const TextStyle(height: 1.4)),
        ),
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: Sp.s),
          padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 12),
          decoration: BoxDecoration(color: AC.surface2, borderRadius: BorderRadius.circular(14)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: tint(AC.textDim, 0.4 + 0.6 * ((_c.value * 3 - i) % 3 < 1 ? 1 : 0)), shape: BoxShape.circle),
                ),
            ]),
          ),
        ),
      );
}

class _UrgentBanner extends StatelessWidget {
  const _UrgentBanner({required this.onClear});
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: tint(AC.red, 0.2),
        padding: const EdgeInsets.all(Sp.m),
        child: Row(children: [
          const Icon(Icons.priority_high_rounded, color: AC.red),
          const SizedBox(width: Sp.s),
          const Expanded(
            child: Text('URGENT HUMAN SUPPORT: contact the mission medical officer or mission control now, or tell a crewmate. Laila cannot replace a person.',
                style: TextStyle(fontSize: 13, height: 1.3)),
          ),
          TextButton(onPressed: onClear, child: const Text('I\'m okay now')),
        ]),
      );
}

class _Breathing extends StatefulWidget {
  const _Breathing({required this.ar});
  final bool ar;
  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  // 4 s in, 4 s hold, 6 s out = 14 s cycle.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (double, String) _phase(double v) {
    final s = v * 14;
    final ar = widget.ar;
    if (s < 4) return (s / 4, ar ? 'شهيق' : 'Breathe in');
    if (s < 8) return (1, ar ? 'احبس' : 'Hold');
    return (1 - (s - 8) / 6, ar ? 'زفير' : 'Breathe out');
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 320,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final (size, label) = _phase(_c.value);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80 + 100 * size,
                  height: 80 + 100 * size,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: tint(AC.cyan, 0.15 + 0.25 * size), border: Border.all(color: AC.cyan)),
                ),
                const SizedBox(height: Sp.l),
                Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ]);
            },
          ),
        ),
      );
}
