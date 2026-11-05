# Hardware, firmware and radio requirements

ATHERA is a software prototype. **No sensor, Bluetooth, LoRa or mesh code ships in this build** apart from
simulators. This page lists what a real integration needs. The app side plugs in through three interfaces:

| Interface | File | Real implementation needs |
|---|---|---|
| `SensorSource` | `lib/sensors/sensor_source.dart` | a driver that turns device packets into `Observation`s |
| `LinkService` | `lib/connectivity/link_service.dart` | a real scan that reports only what it found |
| `EmergencyTransport` | `lib/emergency/transport.dart` | a radio/link that reports delivered / acknowledged / failed |

Every observation carries `measuredAt` (sensor clock) and `receivedAt` (phone clock), a device id, a source and a
quality flag. Out-of-range values are stored as `invalid` (never silently dropped, never used in analytics).

## Measurements (no single wearable is assumed to cover all of them)

| Measurement | Typical hardware | Firmware / signal needs | Notes |
|---|---|---|---|
| Heart rate | PPG wrist/ear sensor or ECG chest strap | stream beats or 1 Hz BPM with a quality flag | PPG degrades with motion; flag poor signal as `poor` |
| SpO₂ | Pulse oximeter (red + IR PPG) | calibrated, per-sample quality/perfusion index | Not reliable under motion or poor perfusion; spaceflight suits need validation |
| ECG waveform | Single-lead patch/strap | raw samples at ≥125 Hz with sample rate and lead info; BLE throughput must carry it or buffer in bursts | The demo draws a synthetic wave. It is not a real ECG and not for rhythm analysis |
| Blood pressure | Cuff or cuffless device | explicit measurement events (not continuous); cuffless devices need calibration | Intermittent (about 5 min in the demo). Mark stale after 15 min |
| Respiratory rate | chest-strap/impedance, or derived from PPG/ECG | state whether measured or derived | Derived values should be labelled DERIVED |
| Core temperature | ingestible pill, or validated skin-to-core estimation | calibration and sensor type in metadata | Skin temperature is **not** core temperature; do not label it as such |
| Stress / fatigue | HRV-based or questionnaire | model and definition | Shown only when real data exists. Nothing is invented |

**Integration checklist per device:** stable device id; monotonic clock or time-sync procedure (record the
offset); unit and range documented; quality field per sample; battery and connection state; behaviour on
disconnect (stop sending, do not repeat last value); replay of buffered data on reconnect (the app dedupes by
astronaut + device + type + timestamp).

## Bluetooth Low Energy

* Flutter plugins such as `flutter_blue_plus` provide scanning and GATT. Not included here.
* **Android**: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (API 31+), and for API ≤ 30 `ACCESS_FINE_LOCATION`,
  declared in `AndroidManifest.xml` and requested at runtime. **iOS**: `NSBluetoothAlwaysUsageDescription` in
  `Info.plist`, plus the Bluetooth capability.
* Use the standard GATT services where they exist (Heart Rate `0x180D`, Pulse Oximeter `0x1822`,
  Health Thermometer `0x1809`, Blood Pressure `0x1810`); anything else (raw ECG, RR) needs a custom GATT service
  defined by the sensor firmware.
* BLE is **point-to-point**. It is not a mesh network. Multi-hop delivery needs Bluetooth Mesh (provisioning,
  specific radios/firmware, and no stock mobile OS API) or an application-level relay that you design and test.
* Background operation, reconnect handling and OS power management need device testing; iOS/Android limit
  background BLE.

## LoRa and other long-range links

* LoRa phones do not exist. A separate radio module (SX126x/SX127x or similar) with its own firmware is
  bridged to the phone over BLE or USB, and then implements `EmergencyTransport`.
* Frame size is small (tens to ~250 bytes depending on spreading factor). The SOS wire format
  (`EmergencyMessage.toWire`) is intentionally minimal: id, who, device, severity, timestamp, manual flag,
  optional HR/SpO₂.
* Regional duty-cycle and frequency regulations apply. Acknowledgements and relays are protocol features you
  must provide (the transport reports them through `TransportEvent`); the service never assumes them.
* Alternatives: habitat Wi-Fi/Ethernet to a base station, Wi-Fi Direct, or a space-qualified comms system.

## SOS semantics the transport must honour

1. `send()` returning means *handed to the transport*, not delivered.
2. Report `delivered`, `acknowledged` or `failed` per recipient through `events`.
3. Messages may arrive more than once (retries, relays): receivers drop repeats by `eventId` (UUID v4).
4. If a transport is unavailable the event is still stored locally and shown as **not delivered**.

## Simulation in this build

`DemoSensorSource`, `DemoLinkService` and `DemoTransport` generate **simulated** data and outcomes. Their
output is always labelled DEMO / SIMULATED and carries `is_simulated` in exports. Link quality in the demo is a
fixture; distances and positions are never fabricated (no positioning exists, so none are shown).
