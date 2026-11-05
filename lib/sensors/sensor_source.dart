import '../domain/models.dart';

enum SensorLinkState { notConfigured, connecting, streaming, stopped, error }

/// Anything that can deliver observations: simulated generator, BLE wearables,
/// an external gateway/WebSocket, a historical-sync endpoint.
///
/// Implementations only DELIVER data. Validation, de-duplication and storage
/// happen in IngestPipeline, so every source gets identical treatment.
abstract class SensorSource {
  String get id;
  String get displayName;
  bool get isSimulated;
  SensorLinkState get state;
  String? get stateDetail;

  /// Batches of observations as they arrive (may be late or out of order).
  Stream<List<Observation>> get observations;

  Future<void> start();
  Future<void> stop();

  /// Historical sync after a gap (device buffered data while out of range).
  Future<List<Observation>> backfill(String astronautId, DateTime from, DateTime to);
}

/// Used when demo mode is off and no real source is configured. It never
/// emits anything, so the UI shows honest "no sensor connected" states.
class NoSensorSource implements SensorSource {
  @override
  String get id => 'none';
  @override
  String get displayName => 'No sensor source';
  @override
  bool get isSimulated => false;
  @override
  SensorLinkState get state => SensorLinkState.notConfigured;
  @override
  String? get stateDetail => 'No wearable or gateway configured';
  @override
  Stream<List<Observation>> get observations => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<Observation>> backfill(String astronautId, DateTime from, DateTime to) async => const [];
}

/// Extension point: Bluetooth Low Energy wearables.
///
/// NOT IMPLEMENTED. A real implementation needs:
///  * a BLE plugin (e.g. flutter_reactive_ble) and platform permissions
///    (Android 12+: BLUETOOTH_SCAN / BLUETOOTH_CONNECT; iOS: NSBluetoothAlwaysUsageDescription),
///  * hardware exposing standard GATT services (Heart Rate 0x180D, Pulse Oximeter 0x1822,
///    Health Thermometer 0x1809, Blood Pressure 0x1810) or a documented custom profile,
///  * a decoder that turns GATT notifications into [Observation]s with the sensor's own timestamp.
/// See docs/HARDWARE.md.
class BleSensorSource extends NoSensorSource {
  @override
  String get id => 'ble';
  @override
  String get displayName => 'Bluetooth wearables';
  @override
  String? get stateDetail => 'Not implemented in this prototype (needs BLE plugin + hardware)';
}

/// Extension point: ingestion from an external gateway (HTTP/WebSocket) that
/// already aggregates wearable data. NOT IMPLEMENTED in the prototype.
class GatewaySensorSource extends NoSensorSource {
  @override
  String get id => 'gateway';
  @override
  String get displayName => 'External gateway';
  @override
  String? get stateDetail => 'Not implemented in this prototype (define the ingestion endpoint first)';
}
