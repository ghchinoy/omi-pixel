import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omi_device/omi_device.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/device.dart';
import 'audio_decoder.dart';

class BleService {
  static final BleService instance = BleService._();
  BleService._();

  final OmiBleClient _bleClient = createOmiBleClient();

  OmiDeviceInfo? _currentDevice;
  OmiDeviceInfo? get currentDevice => _currentDevice;

  final _deviceController = StreamController<OmiDeviceInfo?>.broadcast();
  Stream<OmiDeviceInfo?> get deviceStream => _deviceController.stream;

  Stream<bool> get scanningStream => FlutterBluePlus.isScanning;
  bool get isScanning => FlutterBluePlus.isScanningNow;

  StreamSubscription? _audioSub;

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

  Stream<List<OmiDeviceInfo>> scanDevicesStream({Duration timeout = const Duration(seconds: 8)}) {
    requestPermissions();

    return _bleClient.scanStream(timeout: timeout).map((devices) {
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
      return true;
    } catch (e) {
      _currentDevice = null;
      _deviceController.add(null);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _bleClient.disconnect();
    } catch (_) {}
    _currentDevice = null;
    _deviceController.add(null);
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
}
