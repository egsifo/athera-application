import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../domain/models.dart';

enum AiMode { fixture, model, gateway }

AiMode _defaultAiMode() => switch (AppConfig.defaultAiMode) {
      'gateway' => AiMode.gateway,
      'model' => AiMode.model,
      _ => AiMode.fixture,
    };

class AppSettings {
  AppSettings({
    this.onboardingDone = false,
    this.demoMode = AppConfig.defaultDemoMode,
    AiMode? aiMode,
    String? aiBaseUrl,
    this.selectedAstronautId = 'demo-astronaut-01',
    this.role = UserRole.commander,
    this.fahrenheit = false,
    this.notifyEarlyWarning = true,
    this.notifyCritical = true,
    this.notifySensor = true,
    this.notifySos = true,
    this.demoSeed = 42,
    this.demoNoise = 1.0,
    this.demoDropout = 0.01,
    this.demoScenarios = const {},
    this.missionEnvironment = 'iss',
  })  : aiMode = aiMode ?? _defaultAiMode(),
        aiBaseUrl = aiBaseUrl ?? AppConfig.defaultAiBaseUrl;

  bool onboardingDone;
  bool demoMode;
  AiMode aiMode;
  String aiBaseUrl;
  String selectedAstronautId;
  UserRole role;
  bool fahrenheit;
  bool notifyEarlyWarning;
  bool notifyCritical;
  bool notifySensor;
  bool notifySos;
  int demoSeed;
  double demoNoise;
  double demoDropout;

  /// astronautId -> scenario name (see DemoScenario).
  Map<String, String> demoScenarios;

  /// MissionEnvironment name (see wellness/mission_env.dart).
  String missionEnvironment;
}

class SettingsStore {
  SettingsStore(this._prefs, [FlutterSecureStorage? secure])
      : _secure = secure ?? const FlutterSecureStorage();
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  static const _apiKeyName = 'athera_ai_api_key';

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  AppSettings load() {
    Map<String, String> scenarios = {};
    try {
      final raw = _prefs.getString('demoScenarios');
      if (raw != null) scenarios = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    return AppSettings(
      onboardingDone: _prefs.getBool('onboardingDone') ?? false,
      demoMode: _prefs.getBool('demoMode') ?? AppConfig.defaultDemoMode,
      aiMode: AiMode.values.firstWhere(
        (m) => m.name == _prefs.getString('aiMode'),
        orElse: _defaultAiMode,
      ),
      aiBaseUrl: _prefs.getString('aiBaseUrl') ?? AppConfig.defaultAiBaseUrl,
      selectedAstronautId: _prefs.getString('selectedAstronautId') ?? 'demo-astronaut-01',
      role: UserRole.values.firstWhere((r) => r.name == _prefs.getString('role'), orElse: () => UserRole.commander),
      fahrenheit: _prefs.getBool('fahrenheit') ?? false,
      notifyEarlyWarning: _prefs.getBool('notifyEarlyWarning') ?? true,
      notifyCritical: _prefs.getBool('notifyCritical') ?? true,
      notifySensor: _prefs.getBool('notifySensor') ?? true,
      notifySos: _prefs.getBool('notifySos') ?? true,
      demoSeed: _prefs.getInt('demoSeed') ?? 42,
      demoNoise: _prefs.getDouble('demoNoise') ?? 1.0,
      demoDropout: _prefs.getDouble('demoDropout') ?? 0.01,
      demoScenarios: scenarios,
      missionEnvironment: _prefs.getString('missionEnvironment') ?? 'iss',
    );
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setBool('onboardingDone', s.onboardingDone);
    await _prefs.setBool('demoMode', s.demoMode);
    await _prefs.setString('aiMode', s.aiMode.name);
    await _prefs.setString('aiBaseUrl', s.aiBaseUrl);
    await _prefs.setString('selectedAstronautId', s.selectedAstronautId);
    await _prefs.setString('role', s.role.name);
    await _prefs.setBool('fahrenheit', s.fahrenheit);
    await _prefs.setBool('notifyEarlyWarning', s.notifyEarlyWarning);
    await _prefs.setBool('notifyCritical', s.notifyCritical);
    await _prefs.setBool('notifySensor', s.notifySensor);
    await _prefs.setBool('notifySos', s.notifySos);
    await _prefs.setInt('demoSeed', s.demoSeed);
    await _prefs.setDouble('demoNoise', s.demoNoise);
    await _prefs.setDouble('demoDropout', s.demoDropout);
    await _prefs.setString('demoScenarios', jsonEncode(s.demoScenarios));
    await _prefs.setString('missionEnvironment', s.missionEnvironment);
  }

  // The API key lives only in platform secure storage (Keychain / Keystore).
  Future<String?> readApiKey() async {
    try {
      return await _secure.read(key: _apiKeyName);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeApiKey(String? key) async {
    if (key == null || key.isEmpty) {
      await _secure.delete(key: _apiKeyName);
    } else {
      await _secure.write(key: _apiKeyName, value: key);
    }
  }
}
