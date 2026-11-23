import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi_pixel/models/device.dart';
import 'package:omi_pixel/models/segment.dart';
import 'package:omi_pixel/models/session.dart';
import 'package:omi_pixel/services/audio_decoder.dart';
import 'package:omi_pixel/services/session_manager.dart';
import 'package:omi_pixel/services/settings_service.dart';
import 'package:omi_pixel/ui/live_screen.dart';
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
      expect(parsedSession.startedAt.isUtc, isFalse);
      expect(parsedSession.createdAt.isUtc, isFalse);
      expect(parsedSession.startedAt, DateTime.utc(2026, 8, 29, 10, 0).toLocal());
      expect(
        DateFormat('MMM dd, HH:mm').format(parsedSession.startedAt),
        DateFormat('MMM dd, HH:mm').format(DateTime.utc(2026, 8, 29, 10, 0).toLocal()),
      );
    });

    test('SettingsService liveTranscriptionMode defaults and saves', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();

      expect(SettingsService.instance.liveTranscriptionMode, 'verbatim');
      SettingsService.instance.liveTranscriptionMode = 'smart';
      expect(SettingsService.instance.liveTranscriptionMode, 'smart');
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

  group('Background Foreground Service Tests', () {
    test('AndroidManifest registers ForegroundService with connectedDevice|microphone', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest,
        contains('android:name="com.pravera.flutter_foreground_task.service.ForegroundService"'),
      );
      expect(
        manifest,
        contains('android:foregroundServiceType="connectedDevice|microphone"'),
      );
      expect(manifest, contains('android:exported="false"'));
    });

    test('startForegroundRecordingService succeeds and clears previous error', () async {
      final ok = await SessionManager.instance.startForegroundRecordingService(
        checkNotificationPermission: () async => NotificationPermission.granted,
        isRunningService: () async => false,
        startService: () async => const ServiceRequestSuccess(),
      );

      expect(ok, isTrue);
      expect(SessionManager.instance.lastForegroundServiceError, isNull);
    });

    test('startForegroundRecordingService surfaces ServiceRequestFailure via warningStream', () async {
      final warnings = <String>[];
      final sub = SessionManager.instance.warningStream.listen(warnings.add);
      addTearDown(sub.cancel);

      final ok = await SessionManager.instance.startForegroundRecordingService(
        checkNotificationPermission: () async => NotificationPermission.granted,
        isRunningService: () async => false,
        startService: () async => ServiceRequestFailure(error: Exception('FGS denied')),
      );

      await Future<void>.delayed(Duration.zero);
      expect(ok, isFalse);
      expect(SessionManager.instance.lastForegroundServiceError, contains('FGS denied'));
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('FGS denied'));
    });

    test('startForegroundRecordingService surfaces thrown exception instead of swallowing', () async {
      final warnings = <String>[];
      final sub = SessionManager.instance.warningStream.listen(warnings.add);
      addTearDown(sub.cancel);

      final ok = await SessionManager.instance.startForegroundRecordingService(
        checkNotificationPermission: () async => NotificationPermission.denied,
        requestNotificationPermission: () async => NotificationPermission.denied,
        isRunningService: () async => false,
        startService: () async => throw StateError('Manifest service missing'),
      );

      await Future<void>.delayed(Duration.zero);
      expect(ok, isFalse);
      expect(SessionManager.instance.lastForegroundServiceError, contains('Manifest service missing'));
      expect(warnings, hasLength(1));
    });
  });

  group('LiveScreen PopScope & Zero-Audio Finalization Tests', () {
    testWidgets('LiveScreen guards back navigation with PopScope confirmation dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const LiveScreen()),
                ),
                child: const Text('Open Live'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Live'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LiveScreen), findsOneWidget);

      // Verify PopScope(canPop: false) wraps LiveScreen
      final popScope = tester.widget<PopScope<dynamic>>(
        find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScope.canPop, isFalse);

      // Trigger system back gesture — should show confirmation dialog instead of popping
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Finish Recording?'), findsOneWidget);
      expect(find.text('Keep Recording'), findsOneWidget);
      expect(find.text('Finish & Diarize'), findsOneWidget);

      // Tapping Keep Recording dismisses dialog and keeps LiveScreen active
      await tester.tap(find.text('Keep Recording'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Finish Recording?'), findsNothing);
      expect(find.byType(LiveScreen), findsOneWidget);
    });

    test('finalizeStoppedSession with 0 audio and live transcript saves completed segments to backend', () async {
      SharedPreferences.setMockInitialValues({});
      String? savedStatus;
      List<Segment> savedSegments = const [];

      final baseSession = Session(
        id: 'sess_zero_with_text',
        deviceId: 'omi_1',
        title: 'Quick Note',
        status: SessionStatus.recording,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      final result = await SessionManager.instance.finalizeStoppedSession(
        session: baseSession,
        wavBytes: AudioDecoder.createWav(Uint8List(0)), // 44 bytes (0 PCM)
        liveTranscript: 'Hello from live stream',
        finishTime: DateTime.now(),
        durationSec: 12.0,
        apiConfigured: true,
        saveSegments: (id, segs, {title = '', summary = '', status}) async {
          savedSegments = segs;
          savedStatus = status;
          return true;
        },
      );

      expect(result.status, SessionStatus.completed);
      expect(result.segments, hasLength(1));
      expect(result.segments.first.text, 'Hello from live stream');
      expect(savedStatus, 'completed');
      expect(savedSegments, hasLength(1));
    });

    test('finalizeStoppedSession with 0 audio and 0 transcript marks session failed in backend', () async {
      SharedPreferences.setMockInitialValues({});
      String? savedStatus;
      String? savedSummary;

      final baseSession = Session(
        id: 'sess_zero_empty',
        deviceId: 'omi_1',
        title: 'Dropped BLE',
        status: SessionStatus.recording,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      final result = await SessionManager.instance.finalizeStoppedSession(
        session: baseSession,
        wavBytes: AudioDecoder.createWav(Uint8List(0)), // 44 bytes (0 PCM)
        liveTranscript: '',
        finishTime: DateTime.now(),
        durationSec: 8.0,
        apiConfigured: true,
        saveSegments: (id, segs, {title = '', summary = '', status}) async {
          savedStatus = status;
          savedSummary = summary;
          return true;
        },
      );

      expect(result.status, SessionStatus.failed);
      expect(savedStatus, 'failed');
      expect(savedSummary, contains('No audio'));
    });
  });
}
