import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_device/omi_device.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import 'audio_decoder.dart';

/// Event types emitted by Omi hardware button GATT characteristic (`23ba7925-...`).
enum OmiButtonEventType {
  singleTap,
  doubleTap,
  longTap,
  press,
  release,
  unknown,
}

/// Decoded button notification emitted by an Omi wearable device.
class OmiButtonEvent {
  final int rawCode;
  final OmiButtonEventType type;
  final List<int> rawBytes;
  final DateTime timestamp;
  final AppLifecycleState? lifecycleState;

  const OmiButtonEvent({
    required this.rawCode,
    required this.type,
    required this.rawBytes,
    required this.timestamp,
    this.lifecycleState,
  });

  String get hexBytes =>
      rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Parses an Omi firmware `int final_button_state[2]` BLE notification payload.
  /// Bytes 0..3 encode the event code as a 32-bit little-endian unsigned integer.
  static OmiButtonEvent? parsePayload(
    List<int> bytes, {
    DateTime? timestamp,
    AppLifecycleState? lifecycleState,
  }) {
    if (bytes.length < 4) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 4)));
    final code = data.getUint32(0, Endian.little);
    final type = switch (code) {
      1 => OmiButtonEventType.singleTap,
      2 => OmiButtonEventType.doubleTap,
      3 => OmiButtonEventType.longTap,
      4 => OmiButtonEventType.press,
      5 => OmiButtonEventType.release,
      _ => OmiButtonEventType.unknown,
    };
    return OmiButtonEvent(
      rawCode: code,
      type: type,
      rawBytes: List<int>.unmodifiable(bytes),
      timestamp: timestamp ?? DateTime.now(),
      lifecycleState: lifecycleState,
    );
  }
}

class BleService {
  static final BleService instance = BleService._();
  BleService._();

  static const String _keyLastDeviceId = 'last_ble_device_id';
  static const String _keyLastDeviceName = 'last_ble_device_name';
  static const String hapticServiceUuid = 'cab1ab95-2ea5-4f4d-bb56-874b72cfc984';
  static const String hapticCharacteristicUuid = 'cab1ab96-2ea5-4f4d-bb56-874b72cfc984';

  final OmiBleClient _bleClient = createOmiBleClient();

  OmiDeviceInfo? _currentDevice;
  OmiDeviceInfo? get currentDevice => _currentDevice;

  final _deviceController = StreamController<OmiDeviceInfo?>.broadcast();
  Stream<OmiDeviceInfo?> get deviceStream => _deviceController.stream;

  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  final _reconnectingController = StreamController<bool>.broadcast();
  Stream<bool> get reconnectingStream => _reconnectingController.stream;

  final _buttonEventController = StreamController<OmiButtonEvent>.broadcast();
  Stream<OmiButtonEvent> get buttonEventStream => _buttonEventController.stream;

  final List<OmiButtonEvent> _recentButtonEvents = [];
  List<OmiButtonEvent> get recentButtonEvents => List.unmodifiable(_recentButtonEvents);

  bool _hasButtonCharacteristic = false;
  bool get hasButtonCharacteristic => _hasButtonCharacteristic;

  BluetoothCharacteristic? _hapticCharacteristic;
  bool get hasHapticCharacteristic => _hapticCharacteristic != null;

  Stream<bool> get scanningStream => FlutterBluePlus.isScanning;
  bool get isScanning => FlutterBluePlus.isScanningNow;

  StreamSubscription? _audioSub;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<int>>? _buttonSub;

  void clearRecentButtonEvents() {
    _recentButtonEvents.clear();
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.notification,
      ].request();

      return (statuses[Permission.bluetoothScan]?.isGranted ?? true) &&
          (statuses[Permission.bluetoothConnect]?.isGranted ?? true);
    } else if (Platform.isIOS || Platform.isMacOS) {
      var status = await Permission.bluetooth.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  Stream<List<OmiDeviceInfo>> scanDevicesStream({Duration timeout = const Duration(seconds: 8)}) async* {
    await requestPermissions();

    yield* _bleClient.scanStream(timeout: timeout).map((devices) {
      return devices.map((d) => OmiDeviceInfo(
        id: d.id,
        name: d.name.isNotEmpty ? d.name : 'Omi Device',
        rssi: d.rssi,
      )).toList();
    });
  }

  Future<List<OmiDeviceInfo>> scanDevices({Duration timeout = const Duration(seconds: 8)}) async {
    await requestPermissions();
    final scanned = await _bleClient.scan(timeout: timeout);
    return scanned.map((d) => OmiDeviceInfo(
      id: d.id,
      name: d.name.isNotEmpty ? d.name : 'Omi Device',
      rssi: d.rssi,
    )).toList();
  }

  Future<bool> connect(OmiDeviceInfo device) async {
    try {
      await _bleClient.connect(device.id);

      int rawCodec = 20;
      try {
        rawCodec = await _bleClient.readCodec();
      } catch (_) {}

      int battery = -1;
      try {
        battery = await _bleClient.readBatteryLevel();
      } catch (_) {}

      final codec = DeviceCodec.fromId(rawCodec);
      _currentDevice = device.copyWith(
        isConnected: true,
        codec: codec,
        batteryLevel: battery,
      );
      _deviceController.add(_currentDevice);

      // Monitor BLE connection drops so active recordings detect disconnects immediately
      await _connectionStateSub?.cancel();
      final fbpDevice = BluetoothDevice.fromId(device.id);
      _connectionStateSub = fbpDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          final current = _currentDevice;
          if (current != null && current.id == device.id && current.isConnected) {
            debugPrint('[BleService] Device ${current.name} (${current.id}) disconnected unexpectedly.');
            _currentDevice = current.copyWith(isConnected: false);
            _deviceController.add(_currentDevice);
          }
        }
      });

      // Attach Omi hardware button listener & haptic characteristic (best-effort)
      await _attachButtonAndHapticCharacteristics(fbpDevice);

      // Persist last connected device
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastDeviceId, device.id);
        await prefs.setString(_keyLastDeviceName, device.name);
      } catch (_) {}

      return true;
    } catch (e) {
      _currentDevice = null;
      _deviceController.add(null);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _buttonSub?.cancel();
    _buttonSub = null;
    _hasButtonCharacteristic = false;
    _hapticCharacteristic = null;
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _bleClient.disconnect();
    } catch (_) {}
    _currentDevice = null;
    _deviceController.add(null);

    // Clear saved device on explicit disconnect
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastDeviceId);
      await prefs.remove(_keyLastDeviceName);
    } catch (_) {}
  }

  Future<OmiDeviceInfo?> getLastConnectedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_keyLastDeviceId);
      final name = prefs.getString(_keyLastDeviceName) ?? 'Omi Device';
      if (id != null && id.isNotEmpty) {
        return OmiDeviceInfo(id: id, name: name);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> tryReconnectLastDevice() async {
    if (_currentDevice != null && _currentDevice!.isConnected) {
      return true;
    }
    final lastDev = await getLastConnectedDevice();
    if (lastDev == null) {
      return false;
    }

    _isReconnecting = true;
    _reconnectingController.add(true);
    try {
      await requestPermissions();
      final ok = await connect(lastDev);
      return ok;
    } catch (_) {
      return false;
    } finally {
      _isReconnecting = false;
      _reconnectingController.add(false);
    }
  }

  /// Returns stream of 16kHz 16-bit mono PCM chunks.
  Stream<List<int>> startPcmAudioStream() {
    final codec = _currentDevice?.codec ?? DeviceCodec.opusDevKit;
    return _bleClient.audioPayloads().map((payload) {
      return AudioDecoder.instance.decodePayload(payload, codec);
    }).where((pcm) => pcm.isNotEmpty);
  }

  Future<int> refreshBattery() async {
    if (_currentDevice == null || !_currentDevice!.isConnected) return -1;
    try {
      final battery = await _bleClient.readBatteryLevel();
      _currentDevice = _currentDevice!.copyWith(batteryLevel: battery);
      _deviceController.add(_currentDevice);
      return battery;
    } catch (_) {
      return -1;
    }
  }

  /// Triggers tactile haptic feedback on Omi hardware (level 1=20ms, 2=50ms, 3=500ms).
  Future<bool> playHaptic({int level = 2}) async {
    final char = _hapticCharacteristic;
    if (char == null) return false;
    try {
      await char.write([level & 0xFF]);
      debugPrint('[BleService] Triggered Omi haptic (level=$level)');
      return true;
    } catch (e) {
      debugPrint('[BleService] Failed triggering Omi haptic: $e');
      return false;
    }
  }

  /// Triggers two short haptic pulses (20ms × 2) to confirm recording stopped.
  Future<bool> playDoubleHaptic() async {
    final first = await playHaptic(level: 1);
    if (!first) return false;
    await Future<void>.delayed(const Duration(milliseconds: 130));
    return playHaptic(level: 1);
  }

  BluetoothCharacteristic? _findCharacteristic(
    List<BluetoothService> services,
    String serviceUuid,
    String charUuid,
  ) {
    final sTarget = serviceUuid.toLowerCase();
    final cTarget = charUuid.toLowerCase();
    for (final s in services) {
      if (s.uuid.str128.toLowerCase() != sTarget && s.uuid.str.toLowerCase() != sTarget) {
        continue;
      }
      for (final c in s.characteristics) {
        if (c.uuid.str128.toLowerCase() == cTarget || c.uuid.str.toLowerCase() == cTarget) {
          return c;
        }
      }
    }
    return null;
  }

  Future<void> _attachButtonAndHapticCharacteristics(BluetoothDevice fbpDevice) async {
    await _buttonSub?.cancel();
    _buttonSub = null;
    _hasButtonCharacteristic = false;
    _hapticCharacteristic = null;

    try {
      var services = fbpDevice.servicesList;
      if (services.isEmpty) {
        services = await fbpDevice.discoverServices();
      }

      _hapticCharacteristic = _findCharacteristic(
        services,
        hapticServiceUuid,
        hapticCharacteristicUuid,
      );
      debugPrint('[BleService] Haptic characteristic present: ${_hapticCharacteristic != null}');

      final btnChar = _findCharacteristic(
        services,
        buttonServiceUuid,
        buttonTriggerCharacteristicUuid,
      );
      if (btnChar == null) {
        debugPrint('[BleService] Button characteristic ($buttonTriggerCharacteristicUuid) not found.');
        return;
      }

      _hasButtonCharacteristic = true;
      await btnChar.setNotifyValue(true);
      _buttonSub = btnChar.onValueReceived.listen((value) {
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        final event = OmiButtonEvent.parsePayload(value, lifecycleState: lifecycle);
        if (event == null) {
          debugPrint('[OmiButtonSpike] Ignored short button payload: $value');
          return;
        }
        debugPrint(
          '[OmiButtonSpike] code=${event.rawCode} (${event.type.name}) '
          'lifecycle=${event.lifecycleState?.name ?? "unknown"} hex=[${event.hexBytes}]',
        );
        _recentButtonEvents.insert(0, event);
        if (_recentButtonEvents.length > 10) {
          _recentButtonEvents.removeLast();
        }
        _buttonEventController.add(event);
      });
      fbpDevice.cancelWhenDisconnected(_buttonSub!);
      debugPrint('[BleService] Subscribed to Omi button characteristic ($buttonTriggerCharacteristicUuid).');
    } catch (e) {
      debugPrint('[BleService] Error attaching button/haptic characteristics: $e');
    }
  }
}
