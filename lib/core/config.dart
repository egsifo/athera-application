/// Build-time defaults. Override with --dart-define, e.g.
///   flutter run --dart-define=ATHERA_AI_BASE_URL=http://192.168.1.20:8000
///
/// These are only DEFAULTS: the user can change mode / URL in Settings.
/// API keys are never compiled in: they are typed in Settings and kept in
/// platform secure storage.
class AppConfig {
  AppConfig._();

  static const appVersion = '0.1.0';
  static const disclaimer =
      'Research prototype. Not a medical device. Not for diagnosis or treatment decisions.';

  /// 10.0.2.2 is the Android emulator's alias for the host machine.
  static const defaultAiBaseUrl =
      String.fromEnvironment('ATHERA_AI_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  static const defaultDemoMode = bool.fromEnvironment('ATHERA_DEMO_MODE', defaultValue: true);

  /// 'fixture' = built-in illustrative fixtures (no network), 'gateway' = HTTP.
  static const defaultAiMode = String.fromEnvironment('ATHERA_AI_MODE', defaultValue: 'fixture');

  static const aiTimeout = Duration(seconds: 8);
  static const aiAutoRefresh = Duration(seconds: 60);
  static const aiStaleAfter = Duration(minutes: 15);
  static const sensorStaleAfter = Duration(minutes: 2);
  static const localRetentionDays = 7;
}
