import '../domain/models.dart';

class LinkCapabilities {
  const LinkCapabilities({this.supportsScan = false, this.reportsSignalQuality = false, this.reportsDistance = false});
  final bool supportsScan;
  final bool reportsSignalQuality;
  final bool reportsDistance;
}

class LinkUnavailable implements Exception {
  LinkUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Discovers crew devices and reports how each one is linked.
///
/// Real implementations (later) need: native Bluetooth permissions, compatible
/// radios/firmware, and a defined protocol. Nothing may be shown as
/// "discovered" unless a scan actually found it.
abstract class LinkService {
  String get name;
  bool get isSimulated;
  LinkCapabilities get capabilities;

  /// Performs a scan and returns the topology found. Throws [LinkUnavailable]
  /// when this build cannot scan.
  Future<List<CrewLink>> scan();
}

/// Scripted topology for demo mode. Link quality values are fixtures and the
/// UI labels them as simulated. Whether a member is CONNECTED is not decided
/// here: the controller derives it from how fresh that member's data is.
class DemoLinkService implements LinkService {
  @override
  String get name => 'Simulated links (DEMO)';
  @override
  bool get isSimulated => true;
  @override
  LinkCapabilities get capabilities =>
      const LinkCapabilities(supportsScan: true, reportsSignalQuality: true, reportsDistance: false);

  @override
  Future<List<CrewLink>> scan() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return const [
      CrewLink(astronautId: 'demo-astronaut-01', transport: LinkTransport.baseStation, viaId: 'base', linkQuality: 0.92, simulated: true),
      CrewLink(astronautId: 'demo-astronaut-02', transport: LinkTransport.bluetooth, viaId: 'demo-astronaut-01', linkQuality: 0.74, simulated: true),
      CrewLink(astronautId: 'demo-astronaut-03', transport: LinkTransport.meshRelay, viaId: 'demo-astronaut-02', linkQuality: 0.58, simulated: true),
      CrewLink(astronautId: 'demo-astronaut-04', transport: LinkTransport.localNetwork, viaId: 'demo-astronaut-01', linkQuality: 0.66, simulated: true),
    ];
  }
}

/// Default when demo mode is off: this build has no radio implementation.
class UnavailableLinkService implements LinkService {
  @override
  String get name => 'No link service';
  @override
  bool get isSimulated => false;
  @override
  LinkCapabilities get capabilities => const LinkCapabilities();

  @override
  Future<List<CrewLink>> scan() async {
    throw LinkUnavailable(
      'Scanning is not available in this build. It needs a Bluetooth/LoRa/mesh implementation, '
      'native permissions and compatible hardware (see docs/HARDWARE.md).',
    );
  }
}
