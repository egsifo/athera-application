import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../ai/ai_input_builder.dart';
import '../ai/ai_service.dart';
import '../ai/athera_model_service.dart';
import '../ai/fixture_ai_service.dart';
import '../ai/http_ai_service.dart';
import '../analytics/export.dart';
import '../analytics/rules.dart';
import '../analytics/sample_store.dart';
import '../connectivity/link_service.dart';
import '../core/config.dart';
import '../data/memory_repository.dart';
import '../data/repository.dart';
import '../data/settings_store.dart';
import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../emergency/sos_service.dart';
import '../emergency/transport.dart';
import '../sensors/demo_generator.dart';
import '../sensors/demo_sensor_source.dart';
import '../sensors/ingest.dart';
import '../sensors/sensor_source.dart';
import '../wellness/mission_env.dart';
import 'access_policy.dart';

enum TimeRange { m15, h1, h6, h24 }

extension TimeRangeX on TimeRange {
  Duration get duration => switch (this) {
        TimeRange.m15 => const Duration(minutes: 15),
        TimeRange.h1 => const Duration(hours: 1),
        TimeRange.h6 => const Duration(hours: 6),
        TimeRange.h24 => const Duration(hours: 24),
      };
  String get label => switch (this) {
        TimeRange.m15 => '15 min',
        TimeRange.h1 => '1 h',
        TimeRange.h6 => '6 h',
        TimeRange.h24 => '24 h',
      };
}

enum Connection { connected, disconnected, unknown }

/// What the AI layer last produced (or failed to produce) for one astronaut.
class AiSnapshot {
  const AiSnapshot({this.forecast, this.risk, this.error, this.requestedAt, this.loading = false});
  final ForecastResult? forecast;
  final RiskResult? risk;
  final AiException? error;
  final DateTime? requestedAt;
  final bool loading;

  bool get hasResult => risk != null || forecast != null;

  DateTime? get resultAt => risk?.receivedAt ?? forecast?.receivedAt;

  bool isStale(DateTime now) {
    final t = resultAt;
    return t == null || now.difference(t) > AppConfig.aiStaleAfter;
  }

  AiSnapshot copyWith({bool? loading, AiException? error, bool clearError = false, DateTime? requestedAt}) => AiSnapshot(
        forecast: forecast,
        risk: risk,
        error: clearError ? null : (error ?? this.error),
        requestedAt: requestedAt ?? this.requestedAt,
        loading: loading ?? this.loading,
      );
}

/// Owns app state and wires the layers together. Screens read from it and call
/// its methods; they contain no data-access, analytics or AI logic.
class AppController extends ChangeNotifier {
  AppController({
    required this.repo,
    required this.settingsStore,
    required this.settings,
    this.persistenceWarning,
    this.accessPolicy = const PrototypeAccessPolicy(),
  });

  AtheraRepository repo;
  final SettingsStore settingsStore;
  final AppSettings settings;
  final AccessPolicy accessPolicy;
  String? persistenceWarning;

  final SampleStore samples = SampleStore();
  final IngestPipeline _ingest = IngestPipeline();
  final RuleEngine rules = const RuleEngine();
  final AiInputBuilder _builder = const AiInputBuilder();
  final Uuid _uuid = const Uuid();

  // ---- state exposed to the UI -------------------------------------------
  bool bootstrapping = true;
  String? bootMessage;
  List<Astronaut> crew = [];
  List<Device> devices = [];
  Map<String, CrewLink> links = {};
  String? linkMessage;
  bool scanning = false;
  DateTime? lastScanAt;
  final Map<String, AiSnapshot> ai = {};
  ModelStatusInfo? modelStatus;
  AiException? modelStatusError;
  int aiHorizonSec = 600;
  TimeRange range = TimeRange.h1;
  List<AlertEvent> openAlerts = [];
  int alertRevision = 0;
  int pendingSync = 0;
  DateTime? lastSyncAt;
  String? syncMessage;
  List<double>? demoEcg;
  DateTime? lastIngestAt;
  String? lastIngestNote;
  int duplicatesDropped = 0;
  int invalidReadings = 0;

  late SensorSource sensor;
  late AiService aiService;
  late LinkService linkService;
  late SosService sos;
  DemoGenerator? _generator;

  /// Supplies self-reported sleep (hours) for the model's Sleep_Hours input.
  /// Set by the wellness state; null result = no check-in available.
  double? Function(String astronautId, DateTime at)? sleepHoursProvider;

  MissionEnvironment get missionEnvironment => missionEnvironmentFromName(settings.missionEnvironment);

  void setMissionEnvironment(MissionEnvironment e) {
    settings.missionEnvironment = e.name;
    _saveSettings();
    _notify();
  }

  final StreamController<AlertEvent> _newAlerts = StreamController.broadcast();
  Stream<AlertEvent> get newAlerts => _newAlerts.stream;

  StreamSubscription<List<Observation>>? _sensorSub;
  Timer? _rulesTimer;
  Timer? _aiTimer;
  Timer? _syncTimer;
  bool _disposed = false;

  // ---- derived -------------------------------------------------------------
  Astronaut get selected =>
      crew.firstWhere((a) => a.id == settings.selectedAstronautId, orElse: () => crew.isNotEmpty ? crew.first : _placeholder);
  static const _placeholder = Astronaut(id: 'local-astronaut', name: 'Unassigned', callsign: 'LOCAL', role: UserRole.astronaut);

  bool get demoMode => settings.demoMode;
  bool get isSimulated => sensor.isSimulated;
  bool get canViewMissionControl => accessPolicy.canViewMissionControl(settings.role);

  DemoScenario scenarioOf(String id) {
    final name = settings.demoScenarios[id];
    for (final s in DemoScenario.values) {
      if (s.name == name) return s;
    }
    return DemoGenerator.defaultScenarios[id] ?? DemoScenario.nominal;
  }

  Connection connectionOf(String id, {DateTime? now}) {
    final seen = samples.lastSeen(id);
    if (seen == null) return Connection.unknown;
    return (now ?? DateTime.now()).toUtc().difference(seen) <= AppConfig.sensorStaleAfter
        ? Connection.connected
        : Connection.disconnected;
  }

  MonitoringStatus monitoringStatus(String id) => rules.statusFrom(samples, id, openAlerts);

  AiSnapshot aiOf(String id) => ai[id] ?? const AiSnapshot();

  RiskClass? riskClassOf(String id) => ai[id]?.risk?.riskClass;

  List<AlertEvent> openAlertsFor(String id) => openAlerts.where((a) => a.astronautId == id && a.isOpen).toList();

  List<Recipient> get sosRecipients => [
        for (final a in crew)
          if (a.id != selected.id) Recipient(a.id, a.name),
        const Recipient('base', 'Base station'),
      ];

  // ---- lifecycle -------------------------------------------------------------
  Future<void> start() async {
    await _boot();
  }

  Future<void> _boot() async {
    bootstrapping = true;
    bootMessage = 'Opening local database…';
    _notify();
    try {
      await repo.pruneObservations(DateTime.now().subtract(const Duration(days: AppConfig.localRetentionDays)));
    } catch (e) {
      persistenceWarning = 'Local storage problem: $e';
    }

    _configureServices();

    // Crew
    if (settings.demoMode) {
      await repo.saveAstronauts(DemoGenerator.crew);
      await repo.saveDevices([for (final a in DemoGenerator.crew) ...DemoGenerator.devicesFor(a)]);
      crew = List.of(DemoGenerator.crew);
    } else {
      crew = (await repo.astronauts()).where((a) => !a.isDemo).toList();
      if (crew.isEmpty) {
        const local = Astronaut(id: 'local-astronaut', name: 'Unassigned astronaut', callsign: 'LOCAL', role: UserRole.astronaut);
        await repo.saveAstronauts([local]);
        crew = [local];
      }
    }
    devices = (await repo.devices()).where((d) => crew.any((a) => a.id == d.astronautId)).toList();
    if (!crew.any((a) => a.id == settings.selectedAstronautId)) {
      settings.selectedAstronautId = crew.first.id;
      await settingsStore.save(settings);
    }

    // Data
    samples.clear();
    _ingest.reset();
    ai.clear();
    if (settings.demoMode) {
      bootMessage = 'Generating simulated demo data (clearly marked DEMO DATA)…';
      _notify();
      try {
        await repo.deleteDemoData();
      } catch (_) {}
      final gen = _generator!;
      for (final a in crew) {
        final res = _ingest.process(gen.history(a, gen.anchor), now: gen.anchor.add(const Duration(minutes: 10)));
        samples.addAll(res.accepted);
        try {
          await repo.insertObservations(res.accepted);
        } catch (e) {
          persistenceWarning = 'Could not store demo data: $e';
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));
      for (final a in crew) {
        final stored = await repo.observations(a.id, since: since, excludeSimulated: settings.demoMode);
        _ingest.remember(stored);
        samples.addAll(stored);
        final f = await repo.latestForecast(a.id);
        final h = await repo.riskHistory(a.id, limit: 1);
        if (f != null || h.isNotEmpty) {
          ai[a.id] = AiSnapshot(forecast: f, risk: h.isEmpty ? null : h.last);
        }
      }
    } catch (e) {
      persistenceWarning = 'Could not load stored data: $e';
    }
    if (settings.demoMode) {
      final hr = samples.latest(selected.id, VitalType.heartRate);
      demoEcg = hr == null ? null : _generator!.ecgWaveform(hr.v);
    } else {
      demoEcg = null;
    }

    // Alerts + SOS
    try {
      openAlerts = await repo.alerts(openOnly: true);
    } catch (_) {
      openAlerts = [];
    }
    sos.onChanged = _notify;
    await sos.load();

    // Streams and timers
    _sensorSub = sensor.observations.listen(_onBatch);
    await sensor.start();
    _rulesTimer = Timer.periodic(const Duration(seconds: 15), (_) => evaluateRules());
    _aiTimer = Timer.periodic(AppConfig.aiAutoRefresh, (_) => refreshAllAi());
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshSyncCount());

    bootstrapping = false;
    bootMessage = null;
    _notify();

    await evaluateRules();
    await _refreshSyncCount();
    unawaited(scanLinks());
    unawaited(refreshAllAi());
  }

  void _configureServices() {
    if (settings.demoMode) {
      final scenarios = {for (final a in DemoGenerator.crew) a.id: scenarioOf(a.id)};
      final cfg = DemoConfig(
        seed: settings.demoSeed,
        noise: settings.demoNoise,
        dropoutRate: settings.demoDropout,
        scenarios: scenarios,
      );
      _generator = DemoGenerator(config: cfg);
      sensor = DemoSensorSource(_generator!);
      linkService = DemoLinkService();
    } else {
      _generator = null;
      sensor = NoSensorSource();
      linkService = UnavailableLinkService();
    }
    _configureAi();
    final transport = settings.demoMode ? DemoTransport() : UnavailableTransport();
    sos = SosService(repo: repo, transport: transport, onAlert: _onSosAlert);
  }

  void _configureAi() {
    if (settings.aiMode == AiMode.model) {
      aiService = AtheraModelService(baseUrl: settings.aiBaseUrl, apiKey: settingsStore.readApiKey);
    } else if (settings.aiMode == AiMode.gateway) {
      aiService = HttpAiService(baseUrl: settings.aiBaseUrl, apiKey: settingsStore.readApiKey);
    } else if (settings.demoMode) {
      aiService = FixtureAiService(scenarioOf);
    } else {
      aiService = UnconfiguredAiService();
    }
    modelStatus = null;
    modelStatusError = null;
  }

  Future<void> _teardown() async {
    _rulesTimer?.cancel();
    _aiTimer?.cancel();
    _syncTimer?.cancel();
    await _sensorSub?.cancel();
    await sensor.stop();
    if (sensor is DemoSensorSource) (sensor as DemoSensorSource).dispose();
    sos.dispose();
  }

  Future<void> _restart() async {
    await _teardown();
    await _boot();
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    _newAlerts.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- sensor ingestion ------------------------------------------------------
  Future<void> _onBatch(List<Observation> batch) async {
    final res = _ingest.process(batch);
    duplicatesDropped += res.duplicates;
    invalidReadings += res.invalid;
    if (res.accepted.isEmpty) return;
    samples.addAll(res.accepted);
    samples.trim(DateTime.now().toUtc().subtract(const Duration(hours: 24)));
    lastIngestAt = DateTime.now();
    lastIngestNote = '${res.accepted.length} readings (${res.invalid} invalid, ${res.duplicates} duplicate)';
    if (settings.demoMode && _generator != null) {
      final hr = samples.latest(selected.id, VitalType.heartRate);
      if (hr != null) demoEcg = _generator!.ecgWaveform(hr.v);
    }
    try {
      await repo.insertObservations(res.accepted);
    } catch (e) {
      persistenceWarning = 'Could not store readings: $e';
    }
    _notify();
  }

  // ---- rules and alerts ------------------------------------------------------
  Future<void> evaluateRules() async {
    if (_disposed || bootstrapping) return;
    final now = DateTime.now().toUtc();
    final findings = <RuleFinding>[];
    for (final a in crew) {
      findings.addAll(rules.evaluate(samples, a.id, now: now));
    }
    await _reconcile(
      owns: (a) => a.source == 'ATHERA rules',
      keys: {for (final f in findings) f.key: f},
    );
    _notify();
  }

  /// Opens alerts for new findings, resolves alerts whose condition cleared.
  Future<void> _reconcile({
    required bool Function(AlertEvent) owns,
    required Map<String, RuleFinding> keys,
    String source = 'ATHERA rules',
  }) async {
    final mine = openAlerts.where((a) => owns(a) && a.dedupeKey != null).toList();
    for (final a in mine) {
      final f = keys[a.dedupeKey];
      if (f == null || f.severity != a.severity) {
        a.status = AlertStatus.resolved;
        a.updatedAt = DateTime.now().toUtc();
        await _save(a);
      }
    }
    openAlerts.removeWhere((a) => a.status == AlertStatus.resolved);
    for (final f in keys.values) {
      final exists = openAlerts.any((a) => a.dedupeKey == f.key);
      if (exists) continue;
      await _raise(AlertEvent(
        id: _uuid.v4(),
        category: f.category,
        severity: f.severity,
        title: f.title,
        detail: f.detail,
        source: source,
        createdAt: DateTime.now().toUtc(),
        astronautId: f.astronautId,
        dedupeKey: f.key,
        data: f.data,
        isDemo: _isDemoAstronaut(f.astronautId),
      ));
    }
  }

  bool _isDemoAstronaut(String? id) => id != null && (settings.demoMode && crew.any((a) => a.id == id && a.isDemo));

  Future<void> _raise(AlertEvent a) async {
    openAlerts.insert(0, a);
    await _save(a);
    if (_shouldNotify(a.category)) _newAlerts.add(a);
  }

  bool _shouldNotify(AlertCategory c) => switch (c) {
        AlertCategory.earlyWarning => settings.notifyEarlyWarning,
        AlertCategory.criticalAlert => settings.notifyCritical,
        AlertCategory.sensorDisconnection ||
        AlertCategory.poorDataQuality ||
        AlertCategory.aiServiceUnavailable =>
          settings.notifySensor,
        _ => settings.notifySos,
      };

  Future<void> _save(AlertEvent a) async {
    alertRevision++;
    try {
      await repo.upsertAlert(a);
    } catch (e) {
      persistenceWarning = 'Could not store alert: $e';
    }
  }

  Future<void> acknowledgeAlert(AlertEvent a) async {
    a.status = AlertStatus.acknowledged;
    a.updatedAt = DateTime.now().toUtc();
    await _save(a);
    _notify();
  }

  Future<void> resolveAlert(AlertEvent a) async {
    a.status = AlertStatus.resolved;
    a.updatedAt = DateTime.now().toUtc();
    openAlerts.removeWhere((x) => x.id == a.id);
    await _save(a);
    _notify();
  }

  Future<List<AlertEvent>> queryAlerts({
    String? astronautId,
    AlertCategory? category,
    AlertSeverity? severity,
    Duration? within,
  }) =>
      repo.alerts(
        astronautId: astronautId,
        category: category,
        severity: severity,
        since: within == null ? null : DateTime.now().toUtc().subtract(within),
      );

  // ---- AI --------------------------------------------------------------------
  Future<void> refreshAllAi() async {
    if (_disposed || bootstrapping) return;
    for (final a in crew) {
      if (_disposed) return;
      await refreshAi(a.id);
    }
  }

  Future<void> setHorizon(int seconds) async {
    aiHorizonSec = seconds;
    _notify();
    await refreshAi(selected.id);
  }

  Future<void> refreshAi(String id) async {
    final prev = ai[id];
    ai[id] = (prev ?? const AiSnapshot()).copyWith(loading: true, clearError: true);
    _notify();
    final now = DateTime.now().toUtc();
    try {
      final status = await aiService.getModelStatus();
      modelStatus = status;
      modelStatusError = null;
      if (!aiService.supportsForecast) {
        await _refreshModelRisk(id, now);
        _notify();
        return;
      }
      final minW = status.minWindowSize ?? 2;
      final maxW = status.maxWindowSize ?? 100000;
      final windowSize = (60).clamp(minW, maxW).toInt();
      if (status.supportedHorizonsSeconds.isNotEmpty && !status.supportedHorizonsSeconds.contains(aiHorizonSec)) {
        aiHorizonSec = status.supportedHorizonsSeconds.first;
      }
      const interval = 60;
      final window = _builder.window(samples, id, now, windowSize, interval);
      final comp = _builder.completeness(window);
      if (comp < 0.5) {
        throw AiException(
          AiErrorKind.validation,
          'Not enough recent sensor data for a forecast window (${(comp * 100).round()}% filled, at least 50% needed).',
        );
      }
      final forecast = await aiService.getForecast(ForecastRequest(
        astronautId: id,
        windowSize: windowSize,
        samplingIntervalSeconds: interval,
        predictionHorizonSeconds: aiHorizonSec,
        measurements: window,
      ));
      final risk = await aiService.getRiskAssessment(RiskRequest(
        astronautId: id,
        assessedAt: now,
        current: _builder.current(samples, id, now),
        features: _builder.features(samples, id, now),
        forecast: ForecastSummaryDto.fromResult(forecast),
      ));
      try {
        await repo.saveForecast(forecast);
        await repo.saveRisk(risk);
      } catch (e) {
        persistenceWarning = 'Could not store AI result: $e';
      }
      ai[id] = AiSnapshot(forecast: forecast, risk: risk, requestedAt: now);
      await _syncAiAlerts(id, risk);
      await _resolveByKey('ai-down');
    } on AiException catch (e) {
      final base = prev ?? const AiSnapshot();
      ai[id] = base.copyWith(loading: false, error: e, requestedAt: now);
      if (e.kind != AiErrorKind.validation) {
        modelStatusError = e;
        await _raiseOnce(
          key: 'ai-down',
          category: AlertCategory.aiServiceUnavailable,
          severity: AlertSeverity.warning,
          title: e.headline,
          detail: '${e.message}. Rule-based monitoring continues; no AI predictions are being updated.',
          astronautId: null,
        );
      }
    } catch (e) {
      ai[id] = (prev ?? const AiSnapshot()).copyWith(
        loading: false,
        error: AiException(AiErrorKind.badResponse, 'Unexpected error while processing AI data: $e'),
        requestedAt: now,
      );
    }
    _notify();
  }

  /// Single-call risk model (no forecast): 13 readings, 15 minutes apart.
  Future<void> _refreshModelRisk(String id, DateTime now) async {
    final rows = _modelRows(id, now);
    final risk = await aiService.getRiskAssessment(RiskRequest(
      astronautId: id,
      assessedAt: now,
      current: _builder.current(samples, id, now),
      features: const {},
      modelHistory: rows,
      inputSimulated: samples.simulatedAstronauts.contains(id),
    ));
    try {
      await repo.saveRisk(risk);
    } catch (e) {
      persistenceWarning = 'Could not store AI result: $e';
    }
    ai[id] = AiSnapshot(risk: risk, requestedAt: now);
    await _syncAiAlerts(id, risk);
    await _resolveByKey('ai-down');
  }

  /// Builds the model input from stored measurements. Nothing is filled in or
  /// interpolated: any missing value stops the request with a clear message.
  List<ModelRow> _modelRows(String id, DateTime now) {
    final window = _builder.window(samples, id, now, kModelMinReadings, kModelIntervalSeconds);
    final gen = _generator;
    final missing = <String>{};
    final rows = <ModelRow>[];
    for (final m in window) {
      final v = <String, double>{};
      void put(String key, double? x) {
        if (x == null) {
          missing.add(key);
        } else {
          v[key] = x;
        }
      }

      put('Heart_Rate', m.values[VitalType.heartRate]);
      put('SBP', m.values[VitalType.systolic]);
      put('DBP', m.values[VitalType.diastolic]);
      put('SpO2', m.values[VitalType.spo2]);
      put('Body_Temp', m.values[VitalType.temperature]);
      final ctx = settings.demoMode && gen != null ? gen.modelContext(id, m.timestamp) : null;
      for (final k in const ['HRV_Stress_Index', 'Radiation_Level', 'Sleep_Hours', 'Physical_Activity_Load']) {
        // Sleep comes from the user's own check-in whenever there is one.
        final fromCheckIn = k == 'Sleep_Hours' ? sleepHoursProvider?.call(id, m.timestamp) : null;
        put(k, fromCheckIn ?? ctx?[k]);
      }
      rows.add(ModelRow(m.timestamp, v));
    }
    if (missing.isNotEmpty) {
      final noSource = missing.where((k) => !const ['Heart_Rate', 'SBP', 'DBP', 'SpO2', 'Body_Temp'].contains(k)).toList();
      throw AiException(
        AiErrorKind.validation,
        noSource.isNotEmpty && !settings.demoMode
            ? 'The model needs inputs this app has no sensor for yet: ${noSource.join(', ')}. No values were invented.'
            : 'Not enough recent data for the model (needs $kModelMinReadings readings, 15 minutes apart).',
        details: ['missing: ${missing.join(', ')}'],
      );
    }
    return rows;
  }

  Future<void> _syncAiAlerts(String id, RiskResult risk) async {
    final key = 'ai-risk:$id';
    final cls = risk.riskClass;
    final wantSev = cls == RiskClass.critical
        ? AlertSeverity.critical
        : (cls == RiskClass.earlyWarning ? AlertSeverity.warning : null);
    for (final a in openAlerts.where((x) => x.dedupeKey == key).toList()) {
      if (wantSev == null || a.severity != wantSev) {
        a.status = AlertStatus.resolved;
        a.updatedAt = DateTime.now().toUtc();
        openAlerts.remove(a);
        await _save(a);
      }
    }
    if (wantSev == null) return;
    await _raiseOnce(
      key: key,
      category: cls == RiskClass.critical ? AlertCategory.criticalAlert : AlertCategory.earlyWarning,
      severity: wantSev,
      title: 'AI risk class: ${cls.label}',
      detail: '${risk.isMock ? 'ILLUSTRATIVE fixture result. ' : ''}'
          'Reported by ${risk.modelName} ${risk.modelVersion}. '
          '${risk.warnings.where((w) => w.code != 'DEMO_FIXTURE').map((w) => w.message).join(' ')} '
          'A model classification is not a confirmed medical event.',
      astronautId: id,
      source: 'AI service',
      data: {'risk_class': cls.wire, 'risk_score': risk.riskScore, 'model': risk.modelName, 'status': risk.status.name},
    );
  }

  Future<void> _raiseOnce({
    required String key,
    required AlertCategory category,
    required AlertSeverity severity,
    required String title,
    required String detail,
    required String? astronautId,
    String source = 'AI service',
    Map<String, Object?> data = const {},
  }) async {
    if (openAlerts.any((a) => a.dedupeKey == key)) return;
    await _raise(AlertEvent(
      id: _uuid.v4(),
      category: category,
      severity: severity,
      title: title,
      detail: detail,
      source: source,
      createdAt: DateTime.now().toUtc(),
      astronautId: astronautId,
      dedupeKey: key,
      data: data,
      isDemo: aiService.isIllustrative || _isDemoAstronaut(astronautId),
    ));
  }

  Future<void> _resolveByKey(String key) async {
    for (final a in openAlerts.where((x) => x.dedupeKey == key).toList()) {
      a.status = AlertStatus.resolved;
      a.updatedAt = DateTime.now().toUtc();
      openAlerts.remove(a);
      await _save(a);
    }
  }

  Future<List<RiskResult>> riskHistory(String id) => repo.riskHistory(id);

  /// Used by Settings: checks the configured AI service without building a window.
  Future<String> testAiConnection() async {
    try {
      final s = await aiService.getModelStatus();
      modelStatus = s;
      modelStatusError = null;
      _notify();
      return 'Connected: ${s.mode}, status ${s.status}${s.supportedHorizonsSeconds.isEmpty ? '' : ', predicts ${s.supportedHorizonsSeconds.first ~/ 60} min ahead'}';
    } on AiException catch (e) {
      modelStatusError = e;
      _notify();
      return '${e.headline}: ${e.message}';
    }
  }

  // ---- connectivity ----------------------------------------------------------
  Future<void> scanLinks() async {
    scanning = true;
    _notify();
    try {
      final found = await linkService.scan();
      links = {for (final l in found) l.astronautId: l};
      linkMessage = null;
      lastScanAt = DateTime.now();
    } on LinkUnavailable catch (e) {
      links = {};
      linkMessage = e.reason;
    }
    scanning = false;
    _notify();
  }

  // ---- SOS -------------------------------------------------------------------
  Future<EmergencyEvent> triggerSos(EmergencySeverity severity, {bool manual = true}) {
    final a = selected;
    final snapshot = <String, Object?>{};
    for (final t in VitalType.values) {
      final s = samples.latest(a.id, t);
      if (s != null && DateTime.now().toUtc().difference(s.t) < const Duration(minutes: 30)) {
        snapshot[t.name] = {'value': s.v, 'unit': t.unit, 'at': s.t.toIso8601String()};
      }
    }
    final dev = devices.where((d) => d.astronautId == a.id).toList();
    return sos.trigger(
      origin: a,
      deviceId: dev.isEmpty ? 'unknown-device' : dev.first.id,
      recipients: sosRecipients,
      severity: severity,
      manual: manual,
      snapshot: snapshot,
      heartRate: samples.latest(a.id, VitalType.heartRate)?.v,
      spo2: samples.latest(a.id, VitalType.spo2)?.v,
    );
  }

  void _onSosAlert(AlertCategory c, AlertSeverity s, EmergencyEvent e, String detail) {
    final a = AlertEvent(
      id: _uuid.v4(),
      category: c,
      severity: s,
      title: c.label,
      detail: detail,
      source: 'SOS service',
      createdAt: DateTime.now().toUtc(),
      astronautId: e.astronautId,
      status: c == AlertCategory.sosInitiated ? AlertStatus.active : AlertStatus.resolved,
      data: {'event_id': e.id, 'transport': e.transportName, 'simulated': e.simulated},
      isDemo: e.simulated,
    );
    if (a.isOpen) openAlerts.insert(0, a);
    _save(a);
    if (_shouldNotify(c)) _newAlerts.add(a);
    _notify();
  }

  Future<void> closeSos(EmergencyEvent e) async {
    await sos.close(e.id);
    for (final a in openAlerts.where((x) => x.data['event_id'] == e.id).toList()) {
      a.status = AlertStatus.resolved;
      a.updatedAt = DateTime.now().toUtc();
      openAlerts.remove(a);
      await _save(a);
    }
    _notify();
  }

  // ---- settings ---------------------------------------------------------------
  Future<void> _saveSettings() => settingsStore.save(settings);

  void selectAstronaut(String id) {
    settings.selectedAstronautId = id;
    final hr = samples.latest(id, VitalType.heartRate);
    if (settings.demoMode && _generator != null && hr != null) demoEcg = _generator!.ecgWaveform(hr.v);
    _saveSettings();
    _notify();
  }

  void setRange(TimeRange r) {
    range = r;
    _notify();
  }

  Future<void> completeOnboarding() async {
    settings.onboardingDone = true;
    await _saveSettings();
    _notify();
  }

  Future<void> setDemoMode(bool on) async {
    if (settings.demoMode == on) return;
    settings.demoMode = on;
    await _saveSettings();
    await _restart();
  }

  Future<void> setAiMode(AiMode mode) async {
    settings.aiMode = mode;
    await _saveSettings();
    _configureAi();
    _notify();
    unawaited(refreshAllAi());
  }

  Future<void> saveAiConfig({required String baseUrl, String? apiKey, bool clearKey = false}) async {
    settings.aiBaseUrl = baseUrl.trim();
    await _saveSettings();
    if (clearKey) {
      await settingsStore.writeApiKey(null);
    } else if (apiKey != null && apiKey.isNotEmpty) {
      await settingsStore.writeApiKey(apiKey);
    }
    _configureAi();
    _notify();
  }

  Future<void> setRole(UserRole r) async {
    settings.role = r;
    await _saveSettings();
    _notify();
  }

  Future<void> updatePrefs({bool? fahrenheit, bool? early, bool? critical, bool? sensor, bool? sosN}) async {
    if (fahrenheit != null) settings.fahrenheit = fahrenheit;
    if (early != null) settings.notifyEarlyWarning = early;
    if (critical != null) settings.notifyCritical = critical;
    if (sensor != null) settings.notifySensor = sensor;
    if (sosN != null) settings.notifySos = sosN;
    await _saveSettings();
    _notify();
  }

  Future<void> updateDemoConfig({int? seed, double? noise, double? dropout, String? astronautId, DemoScenario? scenario}) async {
    if (seed != null) settings.demoSeed = seed;
    if (noise != null) settings.demoNoise = noise;
    if (dropout != null) settings.demoDropout = dropout;
    if (astronautId != null && scenario != null) {
      settings.demoScenarios = {...settings.demoScenarios, astronautId: scenario.name};
    }
    await _saveSettings();
    if (settings.demoMode) await _restart();
  }

  /// Deletes ONLY simulated data (observations, AI results, alerts, SOS history)
  /// and regenerates it if demo mode is on.
  Future<void> resetDemoData() async {
    await _teardown();
    try {
      await repo.deleteDemoData();
    } catch (e) {
      persistenceWarning = 'Reset failed: $e';
    }
    await _boot();
  }

  // ---- sync (extension point) ----------------------------------------------
  Future<void> _refreshSyncCount() async {
    try {
      pendingSync = await repo.pendingSyncCount();
      _notify();
    } catch (_) {}
  }

  /// There is no sync backend yet. This records an honest "skipped" entry
  /// instead of pretending to upload. Plug a real SyncTarget in here.
  Future<void> syncNow() async {
    await _refreshSyncCount();
    syncMessage = 'No backend configured. $pendingSync observations are stored only on this device.';
    try {
      await repo.addSyncRecord(SyncRecord(
        id: _uuid.v4(),
        kind: 'observations',
        startedAt: DateTime.now().toUtc(),
        count: 0,
        status: 'skipped',
        note: 'No sync backend configured',
      ));
    } catch (_) {}
    _notify();
  }

  // ---- export -----------------------------------------------------------------
  Future<String> observationsCsvFor(String id, Duration within) async {
    final since = DateTime.now().toUtc().subtract(within);
    return observationsCsv(await repo.observations(id, since: since));
  }

  Future<String> alertsCsvAll() async => alertsCsv(await repo.alerts());
  Future<String> emergenciesCsvAll() async => emergenciesCsv(await repo.emergencies());

  /// Swap to an in-memory repository (used if SQLite fails after startup).
  void useMemoryFallback(String why) {
    repo = MemoryRepository();
    persistenceWarning = why;
  }
}
