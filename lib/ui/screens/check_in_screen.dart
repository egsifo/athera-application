import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/wellness_state.dart';
import '../widgets/common.dart';

/// One-minute daily check-in: sleep, mood, fatigue, stress, optional glucose.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late double _sleep;
  late int _mood, _fatigue, _stress;
  final _glucose = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = context.read<WellnessState>().todayCheckIn;
    _sleep = t?.sleepHours ?? 7;
    _mood = t?.mood ?? 3;
    _fatigue = t?.fatigue ?? 2;
    _stress = t?.stress ?? 2;
    if (t?.glucoseMgDl != null) _glucose.text = t!.glucoseMgDl!.toStringAsFixed(0);
    _note.text = t?.note ?? '';
  }

  @override
  void dispose() {
    _glucose.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final g = _glucose.text.trim();
    double? glucose;
    if (g.isNotEmpty) {
      glucose = double.tryParse(g.replaceAll(',', '.'));
      if (glucose == null) {
        setState(() => _error = 'Blood glucose must be a number, for example 95.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await context.read<WellnessState>().submitCheckIn(
          sleepHours: _sleep,
          mood: _mood,
          fatigue: _fatigue,
          stress: _stress,
          glucoseMgDl: glucose,
          note: _note.text,
        );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    showSnack(context, 'Check-in saved.');
    Navigator.of(context).pop();
  }

  static const _moodWords = ['Very low', 'Low', 'Okay', 'Good', 'Very good'];
  static const _tiredWords = ['Not tired', 'A little tired', 'Tired', 'Very tired', 'Exhausted'];
  static const _stressWords = ['Calm', 'Slightly tense', 'Tense', 'Stressed', 'Very stressed'];

  Widget _scale(String title, int value, List<String> words, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(words[value - 1], style: const TextStyle(color: AC.cyan, fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          label: words[value - 1],
          onChanged: (v) => onChanged(v.round()),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily check-in')),
      body: ListView(padding: const EdgeInsets.all(Sp.l), children: [
        const Text('How are you today?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Your answers stay on this device. They help ATHERA spot trends that sensors cannot see.',
            style: TextStyle(color: AC.textDim, fontSize: 13)),
        const SizedBox(height: Sp.l),
        Row(children: [
          const Expanded(child: Text('Hours of sleep', style: TextStyle(fontWeight: FontWeight.w600))),
          Text('${_sleep.toStringAsFixed(1)} h', style: const TextStyle(color: AC.cyan, fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: _sleep,
          min: 0,
          max: 12,
          divisions: 24,
          label: '${_sleep.toStringAsFixed(1)} h',
          onChanged: (v) => setState(() => _sleep = v),
        ),
        const SizedBox(height: Sp.s),
        _scale('Mood', _mood, _moodWords, (v) => setState(() => _mood = v)),
        _scale('Fatigue', _fatigue, _tiredWords, (v) => setState(() => _fatigue = v)),
        _scale('Stress', _stress, _stressWords, (v) => setState(() => _stress = v)),
        TextField(
          controller: _glucose,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Blood glucose (optional)',
            suffixText: 'mg/dL',
            helperText: 'Only if you measured it today.',
          ),
        ),
        const SizedBox(height: Sp.m),
        TextField(
          controller: _note,
          maxLines: 2,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Note (optional)', helperText: 'Anything the doctors should know.'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Text(_error!, style: const TextStyle(color: AC.red)),
          ),
        const SizedBox(height: Sp.l),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_saving ? 'Saving…' : 'Save check-in'),
          ),
        ),
      ]),
    );
  }
}
