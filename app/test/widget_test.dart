import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi_pixel/models/device.dart';
import 'package:omi_pixel/models/segment.dart';
import 'package:omi_pixel/models/session.dart';
import 'package:omi_pixel/services/audio_decoder.dart';
import 'package:omi_pixel/services/settings_service.dart';
import 'package:omi_pixel/ui/session_detail_screen.dart';

void main() {
  group('Models & Codec Tests', () {
    test('DeviceCodec fromId maps correctly', () {
      expect(DeviceCodec.fromId(20), DeviceCodec.opusDevKit);
      expect(DeviceCodec.fromId(21), DeviceCodec.opusCV1);
      expect(DeviceCodec.fromId(0), DeviceCodec.pcm16);
      expect(DeviceCodec.fromId(1), DeviceCodec.pcm8);
      expect(DeviceCodec.fromId(99), DeviceCodec.unknown);

      expect(DeviceCodec.opusDevKit.isOpus, isTrue);
      expect(DeviceCodec.opusCV1.isOpus, isTrue);
      expect(DeviceCodec.pcm16.isOpus, isFalse);
    });

    test('Segment and Session serialization', () {
      final seg = Segment(
        speaker: 'Speaker 1',
        speakerId: 0,
        text: 'Testing live streaming transcript with Gemini 3.5.',
        start: 0.0,
        end: 4.5,
      );

      final segJson = seg.toJson();
      expect(segJson['speaker'], 'Speaker 1');
      expect(segJson['speaker_id'], 0);
      expect(segJson['start'], 0.0);
      expect(segJson['end'], 4.5);

      final parsedSeg = Segment.fromJson(segJson);
      expect(parsedSeg.text, seg.text);
      expect(parsedSeg.speaker, seg.speaker);

      final session = Session(
        id: 'sess_test_1',
        deviceId: 'omi_devkit_01',
        title: 'Project Sync',
        summary: 'Discussion about Gemini 3.5 Transcribe Live integration.',
        status: SessionStatus.completed,
        language: 'en',
        durationSeconds: 120.0,
        startedAt: DateTime.utc(2026, 8, 29, 10, 0),
        createdAt: DateTime.utc(2026, 8, 29, 10, 0),
        segments: [seg],
      );

      final sessionJson = session.toJson();
      expect(sessionJson['id'], 'sess_test_1');
      expect(sessionJson['status'], 'completed');
      expect((sessionJson['segments'] as List).length, 1);

      final parsedSession = Session.fromJson(sessionJson);
      expect(parsedSession.id, session.id);
      expect(parsedSession.status, SessionStatus.completed);
      expect(parsedSession.segments.first.speaker, 'Speaker 1');
    });
  });

  group('AudioDecoder Tests', () {
    test('createWav generates valid 44-byte RIFF header', () {
      final fakePcm = Uint8List(32000); // 1 second of 16kHz 16-bit mono
      final wav = AudioDecoder.createWav(fakePcm, sampleRate: 16000, channels: 1, bitsPerSample: 16);

      expect(wav.length, 44 + 32000);
      // "RIFF"
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // "WAVE"
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      // "fmt "
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      // "data"
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });
  });

  group('UI Widget Tests', () {
    testWidgets('SessionDetailScreen renders speaker turns and summary', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();

      final session = Session(
        id: 'sess_123',
        deviceId: 'omi_dev',
        title: 'Architecture Review',
        summary: 'Reviewed Cloud Run Go backend and Pixel 11 Flutter client.',
        status: SessionStatus.completed,
        durationSeconds: 15.0,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
        segments: [
          Segment(
            speaker: 'Speaker 1',
            speakerId: 0,
            text: 'Let us deploy the Go service on Cloud Run.',
            start: 0.0,
            end: 5.0,
          ),
          Segment(
            speaker: 'Speaker 2',
            speakerId: 1,
            text: 'And connect the Omi hardware over BLE.',
            start: 5.2,
            end: 10.0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SessionDetailScreen(session: session),
        ),
      );

      expect(find.text('Architecture Review'), findsWidgets);
      expect(find.text('Reviewed Cloud Run Go backend and Pixel 11 Flutter client.'), findsOneWidget);
      expect(find.text('Speaker 1'), findsOneWidget);
      expect(find.text('Speaker 2'), findsOneWidget);
      expect(find.text('Let us deploy the Go service on Cloud Run.'), findsOneWidget);
      expect(find.text('And connect the Omi hardware over BLE.'), findsOneWidget);
    });
  });
}
