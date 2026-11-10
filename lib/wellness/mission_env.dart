/// Where the crew is. Changes the Earth-communication delay and the autonomy
/// the app assumes. Delays are one-way light-time ranges, not link measurements.
enum MissionEnvironment { iss, lunar, marsTransit, marsSurface }

extension MissionEnvironmentX on MissionEnvironment {
  String get label => switch (this) {
        MissionEnvironment.iss => 'Space station (low Earth orbit)',
        MissionEnvironment.lunar => 'Moon (surface or orbit)',
        MissionEnvironment.marsTransit => 'Mars transit',
        MissionEnvironment.marsSurface => 'Mars surface',
      };

  String get shortLabel => switch (this) {
        MissionEnvironment.iss => 'LEO station',
        MissionEnvironment.lunar => 'Moon',
        MissionEnvironment.marsTransit => 'Mars transit',
        MissionEnvironment.marsSurface => 'Mars surface',
      };

  /// One-way signal delay to Earth, in seconds: (minimum, maximum).
  (int, int) get oneWayDelaySeconds => switch (this) {
        MissionEnvironment.iss => (0, 1),
        MissionEnvironment.lunar => (1, 2),
        // Mars is about 3 to 22 light-minutes away depending on orbital positions.
        MissionEnvironment.marsTransit => (180, 1320),
        MissionEnvironment.marsSurface => (180, 1320),
      };

  /// True when waiting for the ground is not a realistic first response.
  bool get autonomous => oneWayDelaySeconds.$2 >= 60;

  String get delayText => switch (this) {
        MissionEnvironment.iss => 'about 1 s',
        MissionEnvironment.lunar => 'about 1.3 s',
        MissionEnvironment.marsTransit => '3 to 22 min',
        MissionEnvironment.marsSurface => '3 to 22 min',
      };

  String get autonomyNote => autonomous
      ? 'A conversation with the ground takes minutes each way, so act on your onboard procedures first and send the brief in parallel.'
      : 'Near real-time contact with the ground is available.';

  /// Earliest and latest time a reply to a message sent at [sent] could arrive
  /// (two one-way trips, ignoring ground processing time).
  (DateTime, DateTime) replyWindow(DateTime sent) {
    final (lo, hi) = oneWayDelaySeconds;
    return (sent.add(Duration(seconds: lo * 2)), sent.add(Duration(seconds: hi * 2)));
  }
}

/// Parses a stored name; unknown or missing values fall back to the station.
MissionEnvironment missionEnvironmentFromName(String? name) {
  for (final e in MissionEnvironment.values) {
    if (e.name == name) return e;
  }
  return MissionEnvironment.iss;
}
