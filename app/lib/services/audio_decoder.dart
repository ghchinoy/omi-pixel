import 'dart:typed_data';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

import '../models/device.dart';

class AudioDecoder {
  static final AudioDecoder instance = AudioDecoder._();
  AudioDecoder._();

  SimpleOpusDecoder? _opusDecoder;
  bool _opusLoaded = false;

  Future<void> init() async {
    if (_opusLoaded) return;
    try {
      initOpus(await opus_flutter.load());
      _opusDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);
      _opusLoaded = true;
    } catch (e) {
      // ignore or log
    }
  }

  /// Decodes raw payload bytes (after stripPacketHeader) to 16kHz 16-bit mono PCM bytes.
  Uint8List decodePayload(List<int> payload, DeviceCodec codec) {
    if (payload.isEmpty) return Uint8List(0);

    final payloadUint8 = Uint8List.fromList(payload);

    if (codec.isOpus) {
      if (_opusDecoder == null) {
        // Fallback: return raw payload if opus not initialized
        return payloadUint8;
      }
      try {
        final Int16List pcmSamples = _opusDecoder!.decode(input: payloadUint8);
        final byteData = ByteData(pcmSamples.length * 2);
        for (int i = 0; i < pcmSamples.length; i++) {
          byteData.setInt16(i * 2, pcmSamples[i], Endian.little);
        }
        return byteData.buffer.asUint8List();
      } catch (e) {
        return Uint8List(0);
      }
    } else if (codec == DeviceCodec.pcm16) {
      return payloadUint8;
    } else if (codec == DeviceCodec.pcm8) {
      // Upsample 8kHz 8-bit to 16kHz 16-bit
      final pcm16 = Uint8List(payload.length * 4);
      final byteData = ByteData.view(pcm16.buffer);
      int outIdx = 0;
      for (int i = 0; i < payload.length; i++) {
        // 8-bit unsigned to 16-bit signed
        int sample16 = (payload[i] - 128) << 8;
        // Duplicate sample for 8kHz -> 16kHz interpolation
        byteData.setInt16(outIdx, sample16, Endian.little);
        outIdx += 2;
        byteData.setInt16(outIdx, sample16, Endian.little);
        outIdx += 2;
      }
      return pcm16;
    }

    return payloadUint8;
  }

  /// Builds a complete 44-byte RIFF WAV byte array from raw 16-bit 16kHz mono PCM data.
  static Uint8List createWav(Uint8List pcmData, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);

    // "RIFF" chunk descriptor
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // "fmt " sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 for PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // "data" sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmData);
    return wav;
  }
}
