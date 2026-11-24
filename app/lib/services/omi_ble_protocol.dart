import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Standard Omi wearable BLE GATT service & characteristic UUIDs
/// (aligned with upstream `omi` DevKit & CV1 firmware).
class OmiUuids {
  static const String audioService = '19b10000-e8f2-537e-4f6c-d104768a1214';
  static const String audioDataStream = '19b10001-e8f2-537e-4f6c-d104768a1214';
  static const String audioCodec = '19b10002-e8f2-537e-4f6c-d104768a1214';

  static const String buttonService = '23ba7924-0000-1000-7450-346eac492e92';
  static const String buttonTrigger = '23ba7925-0000-1000-7450-346eac492e92';

  static const String hapticService = 'cab1ab95-2ea5-4f4d-bb56-874b72cfc984';
  static const String hapticTrigger = 'cab1ab96-2ea5-4f4d-bb56-874b72cfc984';

  static const String batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
  static const String batteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
}

const int omiPacketHeaderBytes = 3;

/// Strips the 3-byte Omi BLE audio packet header (`[seqLSB, seqMSB, flags]`).
List<int> stripOmiPacketHeader(List<int> packet) {
  if (packet.length <= omiPacketHeaderBytes) {
    return const <int>[];
  }
  return packet.sublist(omiPacketHeaderBytes);
}

/// Discovered BLE wearable metadata returned during scanning.
class ScannedBleDevice {
  const ScannedBleDevice({
    required this.id,
    required this.name,
    this.rssi = 0,
  });

  final String id;
  final String name;
  final int rssi;
}

/// Self-contained Omi BLE GATT transport built directly on `flutter_blue_plus`.
class OmiBleTransport {
  BluetoothDevice? _device;
  List<BluetoothService> _services = const [];
  StreamSubscription<List<int>>? _audioSub;
  final StreamController<List<int>> _audioController = StreamController<List<int>>.broadcast();

  static String _norm(String uuid) => uuid.toLowerCase();

  /// Returns true when a BLE advertisement name or service UUID matches Omi wearables.
  static bool isLikelyOmiDevice(String name, List<Guid> serviceUuids) {
    final n = name.trim().toLowerCase();
    if (n.contains('omi') ||
        n.contains('friend') ||
        n.contains('devkit') ||
        n.contains('cv1') ||
        n.contains('bee') ||
        n.contains('compass') ||
        n.contains('fieldy') ||
        n.contains('plaud') ||
        n.contains('limitless')) {
      return true;
    }
    final target = _norm(OmiUuids.audioService);
    for (final u in serviceUuids) {
      if (_norm(u.str128) == target || _norm(u.str) == target) {
        return true;
      }
    }
    return false;
  }

  BluetoothCharacteristic? _findChar(String serviceUuid, String charUuid) {
    final sTarget = _norm(serviceUuid);
    final cTarget = _norm(charUuid);
    for (final s in _services) {
      if (_norm(s.uuid.str128) != sTarget && _norm(s.uuid.str) != sTarget) continue;
      for (final c in s.characteristics) {
        if (_norm(c.uuid.str128) == cTarget || _norm(c.uuid.str) == cTarget) {
          return c;
        }
      }
    }
    // Fallback: search all services by characteristic UUID only.
    for (final s in _services) {
      for (final c in s.characteristics) {
        if (_norm(c.uuid.str128) == cTarget || _norm(c.uuid.str) == cTarget) {
          return c;
        }
      }
    }
    return null;
  }

  Stream<List<ScannedBleDevice>> scanStream({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.isSupported.then((supported) {
      if (!supported) return;
      FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: const [],
        androidUsesFineLocation: false,
      );
    });

    return FlutterBluePlus.scanResults.map((results) {
      final seen = <String, ScannedBleDevice>{};
      for (final r in results) {
        final id = r.device.remoteId.str;
        var name = r.advertisementData.advName.trim();
        if (name.isEmpty) {
          name = r.device.platformName.trim();
        }

        final isOmi = isLikelyOmiDevice(name, r.advertisementData.serviceUuids);
        if (name.isNotEmpty || isOmi) {
          final displayName = name.isNotEmpty ? name : (isOmi ? 'Omi Wearable' : 'BLE Device ($id)');
          final prev = seen[id];
          if (prev == null || r.rssi > prev.rssi || prev.name != displayName) {
            seen[id] = ScannedBleDevice(id: id, name: displayName, rssi: r.rssi);
          }
        }
      }

      final list = seen.values.toList()
        ..sort((a, b) {
          final aOmi = isLikelyOmiDevice(a.name, const []);
          final bOmi = isLikelyOmiDevice(b.name, const []);
          if (aOmi && !bOmi) return -1;
          if (!aOmi && bOmi) return 1;
          return b.rssi.compareTo(a.rssi);
        });
      return list;
    });
  }

  Future<List<ScannedBleDevice>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    if (await FlutterBluePlus.isSupported == false) {
      throw UnsupportedError('Bluetooth not supported on this platform');
    }

    final seen = <String, ScannedBleDevice>{};
    try {
      final system = await FlutterBluePlus.systemDevices([Guid(OmiUuids.audioService)]);
      for (final d in system) {
        final id = d.remoteId.str;
        final name = d.platformName.isNotEmpty ? d.platformName : 'Omi Wearable';
        seen[id] = ScannedBleDevice(id: id, name: name, rssi: -50);
      }
    } catch (_) {}

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        var name = r.advertisementData.advName.trim();
        if (name.isEmpty) {
          name = r.device.platformName.trim();
        }
        final isOmi = isLikelyOmiDevice(name, r.advertisementData.serviceUuids);
        if (name.isNotEmpty || isOmi) {
          final displayName = name.isNotEmpty ? name : (isOmi ? 'Omi Wearable' : 'BLE Device ($id)');
          final prev = seen[id];
          if (prev == null || r.rssi > prev.rssi) {
            seen[id] = ScannedBleDevice(id: id, name: displayName, rssi: r.rssi);
          }
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: const [],
        androidUsesFineLocation: false,
      );
      await Future<void>.delayed(timeout);
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    }

    final list = seen.values.toList()
      ..sort((a, b) {
        final aOmi = isLikelyOmiDevice(a.name, const []);
        final bOmi = isLikelyOmiDevice(b.name, const []);
        if (aOmi && !bOmi) return -1;
        if (!aOmi && bOmi) return 1;
        return b.rssi.compareTo(a.rssi);
      });
    return list;
  }

  Future<void> connect(String deviceId) async {
    await disconnect();
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(license: License.nonprofit, autoConnect: false, mtu: 512);
    _services = await device.discoverServices();
    _device = device;
  }

  Future<void> disconnect() async {
    await _audioSub?.cancel();
    _audioSub = null;
    final d = _device;
    _device = null;
    _services = const [];
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  Stream<List<int>> audioPackets() {
    final device = _device;
    if (device == null) {
      return Stream.error(StateError('not connected'));
    }
    final char = _findChar(OmiUuids.audioService, OmiUuids.audioDataStream);
    if (char == null) {
      return Stream.error(StateError('audio characteristic not found'));
    }

    if (_audioSub == null) {
      scheduleMicrotask(() async {
        try {
          await char.setNotifyValue(true);
          _audioSub = char.onValueReceived.listen((value) {
            if (!_audioController.isClosed) {
              _audioController.add(List<int>.from(value));
            }
          });
          device.cancelWhenDisconnected(_audioSub!);
        } catch (e, st) {
          if (!_audioController.isClosed) {
            _audioController.addError(e, st);
          }
        }
      });
    }
    return _audioController.stream;
  }

  Stream<List<int>> audioPayloads() =>
      audioPackets().map(stripOmiPacketHeader).where((p) => p.isNotEmpty);

  Future<int> readCodec() async {
    final char = _findChar(OmiUuids.audioService, OmiUuids.audioCodec);
    if (char == null) return -1;
    final data = await char.read();
    if (data.isEmpty) return -1;
    return data[0];
  }

  Future<int> readBatteryLevel() async {
    final char = _findChar(OmiUuids.batteryService, OmiUuids.batteryLevel);
    if (char == null) return -1;
    final data = await char.read();
    if (data.isEmpty) return -1;
    return data[0];
  }
}
