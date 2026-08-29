enum DeviceCodec {
  pcm16(0, 'PCM 16-bit', 16000),
  pcm8(1, 'PCM 8-bit', 8000),
  opusDevKit(20, 'Opus (10ms / 100fps)', 16000),
  opusCV1(21, 'Opus FS320 (20ms / 50fps)', 16000),
  unknown(-1, 'Unknown', 16000);

  final int id;
  final String label;
  final int sampleRate;
  const DeviceCodec(this.id, this.label, this.sampleRate);

  static DeviceCodec fromId(int id) {
    for (var c in DeviceCodec.values) {
      if (c.id == id) return c;
    }
    return DeviceCodec.unknown;
  }

  bool get isOpus => this == opusDevKit || this == opusCV1;
}

class OmiDeviceInfo {
  final String id;
  final String name;
  final int rssi;
  final int batteryLevel;
  final DeviceCodec codec;
  final bool isConnected;

  OmiDeviceInfo({
    required this.id,
    required this.name,
    this.rssi = 0,
    this.batteryLevel = -1,
    this.codec = DeviceCodec.opusDevKit,
    this.isConnected = false,
  });

  OmiDeviceInfo copyWith({
    int? rssi,
    int? batteryLevel,
    DeviceCodec? codec,
    bool? isConnected,
  }) {
    return OmiDeviceInfo(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      codec: codec ?? this.codec,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}
