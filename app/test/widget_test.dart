import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi_pixel/models/device.dart';
import 'package:omi_pixel/models/segment.dart';
import 'package:omi_pixel/models/session.dart';
import 'package:omi_pixel/services/api_client.dart';
import 'package:omi_pixel/services/audio_decoder.dart';
import 'package:omi_pixel/services/gemini_live_service.dart';
import 'package:omi_pixel/services/recording_file_store.dart';
import 'package:omi_pixel/services/session_manager.dart';
import 'package:omi_pixel/services/settings_service.dart';
import 'package:omi_pixel/theme/lustrous_theme.dart';
import 'package:omi_pixel/ui/home_screen.dart';
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

    test('SettingsService liveTranscriptionMode and summaryModel default and save', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();

      expect(SettingsService.instance.liveTranscriptionMode, 'verbatim');
      SettingsService.instance.liveTranscriptionMode = 'smart';
      expect(SettingsService.instance.liveTranscriptionMode, 'smart');

      expect(SettingsService.instance.summaryModel, 'gemini-4-hydrogen');
      SettingsService.instance.summaryModel = 'gemini-3.8-flash';
      expect(SettingsService.instance.summaryModel, 'gemini-3.8-flash');
      // Unknown model falls back safely to default
      SettingsService.instance.summaryModel = 'unknown-model';
      expect(SettingsService.instance.summaryModel, 'gemini-4-hydrogen');

      expect(SettingsService.instance.themeModePreference, 'system');
      expect(SettingsService.instance.themeModeNotifier.value, ThemeMode.system);
      SettingsService.instance.themeModePreference = 'light';
      expect(SettingsService.instance.themeModeNotifier.value, ThemeMode.light);
      SettingsService.instance.themeModePreference = 'dark';
      expect(SettingsService.instance.themeModeNotifier.value, ThemeMode.dark);
    });

    test('LustrousTheme provides Mineral Slate light and Obsidian Slate dark tokens', () {
      final light = LustrousTheme.light();
      final dark = LustrousTheme.dark();

      expect(light.colorScheme.primary, const Color(0xFF1D4ED8));
      expect(light.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(dark.colorScheme.primary, const Color(0xFF93C5FD));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0B0F17));

      final lightColors = light.extension<LustrousColors>()!;
      final darkColors = dark.extension<LustrousColors>()!;
      expect(lightColors.speakerPalette, hasLength(6));
      expect(darkColors.speakerPalette, hasLength(6));
    });

    test('GeminiLiveService.buildLiveProxyUri never embeds access_token in query string', () {
      final uri = GeminiLiveService.buildLiveProxyUri(
        'https://omi-pixel.example.run.app/',
        language: 'en',
        mode: 'smart',
        sessionId: 'sess_abc',
      );
      expect(uri.scheme, 'wss');
      expect(uri.path, '/api/live');
      expect(uri.queryParameters['lang'], 'en');
      expect(uri.queryParameters['mode'], 'smart');
      expect(uri.queryParameters['session'], 'sess_abc');
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
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

      expect(find.text('Recording in Progress'), findsOneWidget);
      expect(find.text('Stay'), findsOneWidget);
      expect(find.text('Minimize'), findsOneWidget);
      expect(find.text('Finish & Diarize'), findsOneWidget);

      // Tapping Stay dismisses dialog and keeps LiveScreen active
      await tester.tap(find.text('Stay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Recording in Progress'), findsNothing);
      expect(find.byType(LiveScreen), findsOneWidget);

      // Tapping Minimize button pops LiveScreen cleanly without stopping recording
      await tester.tap(find.byTooltip('Minimize (keep recording)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(LiveScreen), findsNothing);
    });

    testWidgets('HomeScreen differentiates idle vs active recording state', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();
      SessionManager.instance.setRecordingStateForTesting(false);
      addTearDown(() => SessionManager.instance.setRecordingStateForTesting(false));

      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      await tester.pump();

      // Idle state shows Start Conversation
      expect(find.text('Start Conversation'), findsOneWidget);
      expect(find.text('Return to Live Recording'), findsNothing);

      // Active recording state shows Recording in Progress banner + live timer + Return CTA
      SessionManager.instance.setRecordingStateForTesting(true, elapsedSeconds: 65);
      await tester.pump();
      await tester.pump();

      expect(find.text('Recording in Progress'), findsOneWidget);
      expect(find.text('01:05'), findsOneWidget);
      expect(find.text('Return to Live Recording'), findsOneWidget);
      expect(find.text('Start Conversation'), findsNothing);
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

  group('Disk-Backed PCM/WAV & Pending Upload Queue Tests', () {
    test('RecordingFileStore streams PCM to disk, finalizes valid WAV, and recovers orphaned PCM', () async {
      final tempDir = await Directory.systemTemp.createTemp('omi_pixel_store_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final store = RecordingFileStore(baseDirProvider: () async => tempDir);

      // 1. Stream PCM chunks and finalize to WAV
      final pcmFile = await store.startPcmStream('sess_disk_1');
      store.appendPcmChunk(Uint8List.fromList(List<int>.filled(1600, 1)));
      store.appendPcmChunk(Uint8List.fromList(List<int>.filled(1600, 2)));

      final wavFile = await store.finalizeActiveToWav('sess_disk_1');
      expect(wavFile, isNotNull);
      expect(await wavFile!.exists(), isTrue);
      expect(await pcmFile.exists(), isFalse);
      final wavBytes = await wavFile.readAsBytes();
      expect(wavBytes.length, 44 + 3200);
      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), 'WAVE');

      // 2. Simulate crash leaving an orphaned .pcm file on disk
      final orphanPcm = File('${tempDir.path}/omi_recordings/sess_crashed.pcm');
      await orphanPcm.writeAsBytes(Uint8List(640));

      final recovered = await store.recoverOrphanedPcmFiles();
      expect(recovered.any((u) => u.sessionId == 'sess_crashed'), isTrue);
      expect(await orphanPcm.exists(), isFalse);
      final recoveredItem = recovered.firstWhere((u) => u.sessionId == 'sess_crashed');
      expect(await File(recoveredItem.wavPath).exists(), isTrue);
      expect(await File(recoveredItem.wavPath).length(), 44 + 640);
    });

    test('Failed upload keeps WAV on disk and succeeds on manual retry with cleanup', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('omi_pixel_queue_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final store = RecordingFileStore(baseDirProvider: () async => tempDir);
      SessionManager.instance.setFileStoreForTesting(store);

      await store.startPcmStream('sess_retry_1');
      store.appendPcmChunk(Uint8List(1024));
      final wavFile = await store.finalizeActiveToWav('sess_retry_1');
      expect(wavFile, isNotNull);

      final baseSession = Session(
        id: 'sess_retry_1',
        deviceId: 'omi_1',
        title: 'Retry Test',
        status: SessionStatus.recording,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      // First attempt fails (503) — WAV must remain on disk & queued
      final firstResult = await SessionManager.instance.finalizeStoppedSession(
        session: baseSession,
        wavFile: wavFile,
        liveTranscript: '',
        finishTime: DateTime.now(),
        durationSec: 5.0,
        apiConfigured: true,
        uploadAudioFile: (id, file) async => const AudioUploadResult(
          statusCode: 503,
          error: 'Upload failed (HTTP 503): Service Unavailable',
        ),
      );

      expect(firstResult.status, SessionStatus.processing);
      expect(await wavFile!.exists(), isTrue);
      expect(SessionManager.instance.hasPendingUpload('sess_retry_1'), isTrue);
      expect(SessionManager.instance.pendingUploadFor('sess_retry_1')?.attempts, 1);
      expect(SessionManager.instance.lastUploadError, contains('503'));

      // Retry succeeds (200) — WAV must be deleted and queue cleared
      final retryResult = await SessionManager.instance.retryPendingUpload(
        'sess_retry_1',
        uploadAudioFile: (id, file) async => AudioUploadResult(
          statusCode: 200,
          session: baseSession.copyWith(status: SessionStatus.completed, title: 'Diarized Retry'),
        ),
      );

      expect(retryResult.isSuccess, isTrue);
      expect(await wavFile.exists(), isFalse);
      expect(SessionManager.instance.hasPendingUpload('sess_retry_1'), isFalse);
    });

    test('ApiClient.uploadAudioDetailed retries once with forceRefresh=true on HTTP 401', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();

      final forceRefreshCalls = <bool>[];
      int attemptCount = 0;

      final result = await ApiClient.instance.uploadAudioDetailed(
        'sess_401_test',
        wavBytes: AudioDecoder.createWav(Uint8List(320)),
        baseUrlOverride: 'https://example.run.app',
        tokenProvider: ({bool forceRefresh = false}) async {
          forceRefreshCalls.add(forceRefresh);
          return forceRefresh ? 'fresh-jwt-token' : 'expired-jwt-token';
        },
        sendRequest: (req) async {
          attemptCount++;
          expect(req.url.queryParameters['summary_model'], 'gemini-4-hydrogen');
          if (attemptCount == 1) {
            expect(req.headers['Authorization'], 'Bearer expired-jwt-token');
            return http.Response('{"error":"token expired"}', 401);
          }
          expect(req.headers['Authorization'], 'Bearer fresh-jwt-token');
          return http.Response(
            jsonEncode({
              'id': 'sess_401_test',
              'device_id': 'omi_1',
              'title': 'Recovered After 401',
              'status': 'completed',
              'started_at': DateTime.now().toUtc().toIso8601String(),
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        },
      );

      expect(result.isSuccess, isTrue);
      expect(result.session?.title, 'Recovered After 401');
      expect(attemptCount, 2);
      expect(forceRefreshCalls, [false, true]);
    });

    test('finalizeStoppedSession(awaitUpload: false) returns immediately and completes diarization in background', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('omi_pixel_async_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final store = RecordingFileStore(baseDirProvider: () async => tempDir);
      SessionManager.instance.setFileStoreForTesting(store);

      await store.startPcmStream('sess_bg_1');
      store.appendPcmChunk(Uint8List(2048));
      final wavFile = await store.finalizeActiveToWav('sess_bg_1');
      expect(wavFile, isNotNull);

      final uploadCompleter = Completer<AudioUploadResult>();
      final completedSessions = <Session>[];
      final sub = SessionManager.instance.diarizationCompletedStream.listen(completedSessions.add);
      addTearDown(sub.cancel);

      final baseSession = Session(
        id: 'sess_bg_1',
        deviceId: 'omi_1',
        title: 'Async Test',
        status: SessionStatus.recording,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      // Returns immediately without waiting for uploadCompleter
      final immediateResult = await SessionManager.instance.finalizeStoppedSession(
        session: baseSession,
        wavFile: wavFile,
        liveTranscript: '',
        finishTime: DateTime.now(),
        durationSec: 15.0,
        awaitUpload: false,
        apiConfigured: true,
        uploadAudioFile: (id, file) => uploadCompleter.future,
      );

      expect(immediateResult.status, SessionStatus.processing);
      expect(SessionManager.instance.isDiarizing('sess_bg_1'), isTrue);
      expect(await wavFile!.exists(), isTrue);

      // Now complete background diarization
      uploadCompleter.complete(
        AudioUploadResult(
          statusCode: 200,
          session: baseSession.copyWith(
            status: SessionStatus.completed,
            title: 'Background Diarized Session',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(SessionManager.instance.isDiarizing('sess_bg_1'), isFalse);
      expect(SessionManager.instance.hasPendingUpload('sess_bg_1'), isFalse);
      expect(await wavFile.exists(), isFalse);
      expect(completedSessions, hasLength(1));
      expect(completedSessions.first.title, 'Background Diarized Session');
    });
  });
}
