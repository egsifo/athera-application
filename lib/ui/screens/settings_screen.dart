import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/settings_store.dart';
import '../../domain/models.dart';
import '../../sensors/demo_generator.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.xxl),
        children: [
          _ProfileSection(c: c),
          _DataSourceSection(c: c),
          _AiSection(c: c),
          _StatusSection(c: c),
          _PrefsSection(c: c),
          _AboutSection(c: c),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children) : subtitle = null;
  const _Group.sub(this.title, this.subtitle, this.children);
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title, subtitle: subtitle),
      AtCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
    ]);
  }
}

// ---------------------------------------------------------------------------
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    return _Group('Astronaut & role', [
      InputDecorator(
        decoration: const InputDecoration(labelText: 'Selected astronaut / device', isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: c.crew.any((a) => a.id == c.selected.id) ? c.selected.id : null,
            isExpanded: true,
            dropdownColor: AC.surface2,
            items: [
              for (final a in c.crew)
                DropdownMenuItem(
                  value: a.id,
                  child: Text('${a.callsign} · ${a.name}${c.devices.any((d) => d.astronautId == a.id) ? ' · ${c.devices.firstWhere((d) => d.astronautId == a.id).name}' : ''}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) c.selectAstronaut(v);
            },
          ),
        ),
      ),
      const SizedBox(height: Sp.m),
      InputDecorator(
        decoration: const InputDecoration(labelText: 'Viewing as (prototype role)', isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<UserRole>(
            value: c.settings.role,
            isExpanded: true,
            dropdownColor: AC.surface2,
            items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (v) {
              if (v != null) c.setRole(v);
            },
          ),
        ),
      ),
      const SizedBox(height: Sp.s),
      const Text(
        'The role only changes which screens are shown. There is no authentication in this prototype, so this is not a security control.',
        style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
class _DataSourceSection extends StatefulWidget {
  const _DataSourceSection({required this.c});
  final AppController c;

  @override
  State<_DataSourceSection> createState() => _DataSourceSectionState();
}

class _DataSourceSectionState extends State<_DataSourceSection> {
  late double _noise = widget.c.settings.demoNoise;
  late double _dropout = widget.c.settings.demoDropout;
  late final TextEditingController _seed = TextEditingController(text: '${widget.c.settings.demoSeed}');

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return _Group.sub('Data source', 'Demo mode needs no hardware or account', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Demo mode'),
        subtitle: const Text('Generates clearly labelled DEMO DATA. Turn off to use real sensors only.'),
        value: c.demoMode,
        onChanged: (v) async {
          await c.setDemoMode(v);
        },
      ),
      if (c.demoMode) ...[
        const Divider(height: Sp.xl),
        const Text('Demo data generator', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: Sp.s),
        for (final a in c.crew)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s),
            child: InputDecorator(
              decoration: InputDecoration(labelText: '${a.callsign} scenario', isDense: true),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DemoScenario>(
                  value: c.scenarioOf(a.id),
                  isExpanded: true,
                  dropdownColor: AC.surface2,
                  items: [for (final s in DemoScenario.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: (v) {
                    if (v != null) c.updateDemoConfig(astronautId: a.id, scenario: v);
                  },
                ),
              ),
            ),
          ),
        Text('Noise ×${_noise.toStringAsFixed(1)}', style: const TextStyle(color: AC.textDim, fontSize: 12)),
        Slider(
          value: _noise,
          min: 0,
          max: 3,
          divisions: 30,
          onChanged: (v) => setState(() => _noise = v),
          onChangeEnd: (v) => c.updateDemoConfig(noise: v),
        ),
        Text('Missing readings ${(_dropout * 100).toStringAsFixed(0)}%', style: const TextStyle(color: AC.textDim, fontSize: 12)),
        Slider(
          value: _dropout,
          min: 0,
          max: 0.3,
          divisions: 30,
          onChanged: (v) => setState(() => _dropout = v),
          onChangeEnd: (v) => c.updateDemoConfig(dropout: v),
        ),
        TextField(
          controller: _seed,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Random seed (same seed = same data)', isDense: true),
          onSubmitted: (v) {
            final n = int.tryParse(v.trim());
            if (n != null) c.updateDemoConfig(seed: n);
          },
        ),
        const SizedBox(height: Sp.m),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AC.amber),
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset demo data…'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AC.surface,
                title: const Text('Reset demo data?'),
                content: const Text(
                  'Deletes simulated measurements, AI fixtures, alerts and SOS history, then regenerates them. Real (non-simulated) data is not touched.',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                ],
              ),
            );
            if (ok == true) {
              await c.resetDemoData();
              if (context.mounted) showSnack(context, 'Demo data reset.');
            }
          },
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------
class _AiSection extends StatefulWidget {
  const _AiSection({required this.c});
  final AppController c;

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  late final TextEditingController _url = TextEditingController(text: widget.c.settings.aiBaseUrl);
  final TextEditingController _key = TextEditingController();
  bool _testing = false;
  String? _result;
  bool _resultOk = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  String? _urlProblem(String v) {
    final u = Uri.tryParse(v.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      return 'Enter a full URL, e.g. https://ai.example.org';
    }
    return null;
  }

  bool _cleartextRisk(String v) {
    final u = Uri.tryParse(v.trim());
    if (u == null || u.scheme != 'http') return false;
    final h = u.host;
    return !(h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2' || h.startsWith('192.168.') || h.startsWith('10.'));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final gateway = c.settings.aiMode != AiMode.fixture;
    final problem = gateway ? _urlProblem(_url.text) : null;
    return _Group.sub('AI service', 'Your externally hosted LSTM / XGBoost services', [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<AiMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: AiMode.fixture, label: Text('Fixtures')),
            ButtonSegment(value: AiMode.model, label: Text('ATHERA model')),
            ButtonSegment(value: AiMode.gateway, label: Text('Gateway')),
          ],
          selected: {c.settings.aiMode},
          onSelectionChanged: (s) => c.setAiMode(s.first),
        ),
      ),
      const SizedBox(height: Sp.s),
      if (!gateway)
        Text(
          c.demoMode
              ? 'Built-in ILLUSTRATIVE fixtures. No network, no model. Results are labelled and are not medical predictions.'
              : 'Fixtures only work in demo mode. Choose "ATHERA model" to connect your model server.',
          style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
        )
      else ...[
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'AI base URL', isDense: true, errorText: problem),
        ),
        if (problem == null && _cleartextRisk(_url.text))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('This URL is not encrypted (http) and not on a local network. Use https for anything beyond local testing.',
                style: TextStyle(color: AC.amber, fontSize: 12, height: 1.3)),
          ),
        const SizedBox(height: Sp.m),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API key (optional)',
            helperText: 'Stored in the device keystore. Leave empty to keep the saved key.',
            isDense: true,
          ),
        ),
        const SizedBox(height: Sp.m),
        Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
          FilledButton(
            onPressed: problem != null
                ? null
                : () async {
                    await c.saveAiConfig(baseUrl: _url.text, apiKey: _key.text);
                    _key.clear();
                    if (context.mounted) showSnack(context, 'AI settings saved.');
                  },
            child: const Text('Save'),
          ),
          OutlinedButton(
            onPressed: _testing || problem != null
                ? null
                : () async {
                    setState(() {
                      _testing = true;
                      _result = null;
                    });
                    await c.saveAiConfig(baseUrl: _url.text, apiKey: _key.text);
                    _key.clear();
                    final r = await c.testAiConnection();
                    if (!mounted) return;
                    setState(() {
                      _testing = false;
                      _result = r;
                      _resultOk = r.startsWith('Connected');
                    });
                  },
            child: Text(_testing ? 'Testing…' : 'Test connection'),
          ),
          TextButton(
            onPressed: () async {
              await c.saveAiConfig(baseUrl: _url.text, clearKey: true);
              if (context.mounted) showSnack(context, 'Saved API key removed.');
            },
            child: const Text('Remove key'),
          ),
        ]),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s),
            child: Text(_result!, style: TextStyle(color: _resultOk ? AC.green : AC.red, fontSize: 13, height: 1.35)),
          ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------
class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final conn = c.connectionOf(c.selected.id);
    final (connLabel, connColor) = switch (conn) {
      Connection.connected => ('Receiving data', AC.green),
      Connection.disconnected => ('Data stopped', AC.red),
      Connection.unknown => ('No data yet', AC.textDim),
    };
    final ai = c.modelStatus;
    final aiErr = c.modelStatusError;
    return _Group('System status', [
      KeyValueRow('AI service', aiErr != null ? 'Unavailable' : (ai != null ? 'Connected (${ai.status})' : 'Not checked yet'),
          valueColor: aiErr != null ? AC.red : (ai != null ? AC.green : AC.textDim)),
      KeyValueRow('Model service version', ai?.serviceVersion ?? 'not provided'),
      KeyValueRow('Sensor source', c.sensor.isSimulated ? 'Simulated (demo)' : 'No sensor connected', valueColor: c.sensor.isSimulated ? AC.blue : AC.textDim),
      KeyValueRow('Sensor data', connLabel, valueColor: connColor),
      KeyValueRow('Last reading ingested', c.lastIngestAt == null ? 'never' : '${fmtTime(c.lastIngestAt!)} · ${c.lastIngestNote ?? ''}'),
      KeyValueRow('Duplicates dropped', '${c.duplicatesDropped}'),
      KeyValueRow('Invalid readings', '${c.invalidReadings}'),
      KeyValueRow('Local storage', c.repo.backendName),
      KeyValueRow('Pending sync', '${c.pendingSync} observations'),
      KeyValueRow('Last sync', c.lastSyncAt == null ? 'never' : fmtAgo(c.lastSyncAt)),
      if (c.syncMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(c.syncMessage!, style: const TextStyle(color: AC.textDim, fontSize: 12, height: 1.35)),
        ),
      const SizedBox(height: Sp.s),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () async {
            await c.syncNow();
          },
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: const Text('Sync now'),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
class _PrefsSection extends StatelessWidget {
  const _PrefsSection({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    Widget sw(String title, bool v, ValueChanged<bool> f) =>
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(title), value: v, onChanged: f);
    return _Group('Units & notifications', [
      sw('Show temperature in °F', s.fahrenheit, (v) => c.updatePrefs(fahrenheit: v)),
      const Divider(),
      sw('Early warnings', s.notifyEarlyWarning, (v) => c.updatePrefs(early: v)),
      sw('Critical alerts', s.notifyCritical, (v) => c.updatePrefs(critical: v)),
      sw('Sensor and data-quality events', s.notifySensor, (v) => c.updatePrefs(sensor: v)),
      sw('SOS events', s.notifySos, (v) => c.updatePrefs(sosN: v)),
      const Text(
        'Notifications are in-app banners. Alerts are always stored in the history regardless of these switches.',
        style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.35),
      ),
    ]);
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    return _Group('About', [
      const KeyValueRow('ATHERA version', AppConfig.appVersion),
      KeyValueRow('Mode', c.demoMode ? 'Demo' : 'Live sensors'),
      const SizedBox(height: Sp.s),
      const Text(AppConfig.disclaimer, style: TextStyle(color: AC.textDim, fontSize: 12, height: 1.4)),
    ]);
  }
}
