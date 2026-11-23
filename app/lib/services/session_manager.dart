import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/device.dart';
import '../models/segment.dart';
import '../models/session.dart';
import 'api_client.dart';
import 'audio_decoder.dart';
import 'ble_service.dart';
import 'gemini_live_service.dart';
import 'settings_service.dart';

/// Snapshot of live BLE connection and PCM audio capture health during a recording.
class RecordingAudioHealth {
  final int bytesReceived;
  final int packetCount;
  final bool bleConnected;
  final bool stalled;

  const RecordingAudioHealth({
    this.bytesReceived = 0,
    this.packetCount = 0,
    this.bleConnected = true,
    this.stalled = false,
  });

  bool get hasWarning => !bleConnected || stalled;
}

class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  final GeminiLiveService _geminiLive = GeminiLiveService();
  final List<Uint8List> _recordedPcmChunks = [];
  int _totalRecordedBytes = 0;
  int _receivedPacketCount = 0;
  DateTime? _lastAudioAt;
  bool _bleDisconnectedDuringRecording = false;
  bool _stalledWarningEmitted = false;

  Session? _activeSession;
  Session? get activeSession => _activeSession;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  final StringBuffer _liveTranscriptBuffer = StringBuffer();
  String get liveTranscript => _liveTranscriptBuffer.toString();

  final _transcriptStreamController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptStreamController.stream;

  final _recordingStateController = StreamController<bool>.broadcast();
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  final _durationController = StreamController<int>.broadcast();
  Stream<int> get durationStream => _durationController.stream;

  final _sessionsController = StreamController<List<Session>>.broadcast();
  Stream<List<Session>> get sessionsStream => _sessionsController.stream;

  final _warningController = StreamController<String>.broadcast();
  Stream<String> get warningStream => _warningController.stream;

  final _audioHealthController = StreamController<RecordingAudioHealth>.broadcast();
  Stream<RecordingAudioHealth> get audioHealthStream => _audioHealthController.stream;

  RecordingAudioHealth _currentAudioHealth = const RecordingAudioHealth();
  RecordingAudioHealth get currentAudioHealth => _currentAudioHealth;

  String? _lastForegroundServiceError;
  String? get lastForegroundServiceError => _lastForegroundServiceError;

  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  StreamSubscription? _audioStreamSub;
  StreamSubscription? _geminiTranscriptSub;
  StreamSubscription<OmiDeviceInfo?>? _bleDeviceSub;

  List<Session> _cachedSessions = [];
  List<Session> get cachedSessions => _cachedSessions;

  Future<void> init() async {
    await AudioDecoder.instance.init();
    await _loadLocalSessions();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'omi_pixel_recording',
        channelName: 'Omi Pixel Recording',
        channelDescription: 'Recording audio from Omi wearable device',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts (or restarts) the Android foreground service for active BLE recording.
  ///
  /// Uses [ForegroundServiceTypes.connectedDevice] at runtime so Android 14+ does
  /// not require RECORD_AUDIO when capturing exclusively from an Omi BLE wearable.
  /// Any failure is logged via [debugPrint] and surfaced on [warningStream].
  @visibleForTesting
  Future<bool> startForegroundRecordingService({
    Future<NotificationPermission> Function()? checkNotificationPermission,
    Future<NotificationPermission> Function()? requestNotificationPermission,
    Future<bool> Function()? isRunningService,
    Future<ServiceRequestResult> Function()? restartService,
    Future<ServiceRequestResult> Function()? startService,
  }) async {
    _lastForegroundServiceError = null;
    try {
      final checkPerm =
          checkNotificationPermission ?? FlutterForegroundTask.checkNotificationPermission;
      final reqPerm =
          requestNotificationPermission ?? FlutterForegroundTask.requestNotificationPermission;
      if (await checkPerm() != NotificationPermission.granted) {
        await reqPerm();
      }

      final running = await (isRunningService ?? () => FlutterForegroundTask.isRunningService)();
      final ServiceRequestResult result;
      if (running) {
        result = await (restartService ?? FlutterForegroundTask.restartService)();
      } else {
        result = await (startService ??
            () => FlutterForegroundTask.startService(
                  serviceId: 256,
                  serviceTypes: const [ForegroundServiceTypes.connectedDevice],
                  notificationTitle: 'Omi Recording Active',
                  notificationText: 'Streaming and transcribing conversation...',
                ))();
      }

      if (result is ServiceRequestFailure) {
        final msg = 'Background recording service failed to start: ${result.error}';
        _lastForegroundServiceError = msg;
        debugPrint('[SessionManager] $msg');
        _warningController.add(msg);
        return false;
      }

      debugPrint('[SessionManager] Foreground recording service started.');
      return true;
    } catch (e, st) {
      final msg = 'Background recording service error: $e';
      _lastForegroundServiceError = msg;
      debugPrint('[SessionManager] $msg\n$st');
      _warningController.add(msg);
      return false;
    }
  }

  Future<void> _stopForegroundRecordingService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        final result = await FlutterForegroundTask.stopService();
        if (result is ServiceRequestFailure) {
          debugPrint('[SessionManager] Foreground service failed to stop: ${result.error}');
        }
      }
    } catch (e) {
      debugPrint('[SessionManager] Error stopping foreground service: $e');
    }
  }

  Future<bool> startRecording() async {
    if (_isRecording) return true;

    final device = BleService.instance.currentDevice;
    if (device == null || !device.isConnected) {
      return false;
    }

    final sessionId = 'sess_${const Uuid().v4().substring(0, 8)}';
    final now = DateTime.now();

    _activeSession = Session(
      id: sessionId,
      deviceId: device.id,
      title: 'Conversation with ${device.name}',
      status: SessionStatus.recording,
      language: SettingsService.instance.preferredLanguage,
      startedAt: now,
      createdAt: now,
    );

    _recordedPcmChunks.clear();
    _totalRecordedBytes = 0;
    _receivedPacketCount = 0;
    _lastAudioAt = null;
    _bleDisconnectedDuringRecording = false;
    _stalledWarningEmitted = false;
    _liveTranscriptBuffer.clear();
    _elapsedSeconds = 0;
    _isRecording = true;
    _emitAudioHealth(bleConnected: true, stalled: false);
    _recordingStateController.add(true);
    _transcriptStreamController.add('');

    // Monitor BLE connection drops during recording
    await _bleDeviceSub?.cancel();
    _bleDeviceSub = BleService.instance.deviceStream.listen((dev) {
      if (!_isRecording) return;
      final connected = dev != null && dev.isConnected;
      if (!connected && !_bleDisconnectedDuringRecording) {
        _bleDisconnectedDuringRecording = true;
        _emitAudioHealth(bleConnected: false, stalled: true);
        const msg = 'Omi device disconnected during recording. Tap Finish to save captured audio.';
        debugPrint('[SessionManager] $msg');
        _warningController.add(msg);
      } else if (connected && _bleDisconnectedDuringRecording) {
        _bleDisconnectedDuringRecording = false;
        _emitAudioHealth(bleConnected: true, stalled: false);
      }
    });

    // 1. Notify Cloud Run of session start (non-blocking)
    unawaited(ApiClient.instance.createSession(_activeSession!));

    // 2. Start Gemini 3.5 Live Streaming via Cloud Run proxy if configured
    final cloudRunUrl = SettingsService.instance.cloudRunUrl;
    if (cloudRunUrl.isNotEmpty) {
      final connected = await _geminiLive.connect(
        cloudRunUrl: cloudRunUrl,
        sessionId: sessionId,
        language: SettingsService.instance.preferredLanguage,
        mode: SettingsService.instance.liveTranscriptionMode,
      );

      if (connected) {
        _geminiTranscriptSub = _geminiLive.transcriptStream.listen((event) {
          if (event.isTurnComplete) {
            if (_liveTranscriptBuffer.isNotEmpty) {
              _liveTranscriptBuffer.write(' ');
            }
            _liveTranscriptBuffer.write(event.text);
            _transcriptStreamController.add(_liveTranscriptBuffer.toString());
          } else {
            // Emit accumulated text plus interim preview
            final preview = _liveTranscriptBuffer.isEmpty
                ? event.text
                : '${_liveTranscriptBuffer.toString()} ${event.text}';
            _transcriptStreamController.add(preview);
          }
        });
      }
    }

    // 3. Start Foreground notification service so Android keeps BLE/WS alive in background
    await startForegroundRecordingService();

    // 4. Start timer & periodic audio stall detection
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      _durationController.add(_elapsedSeconds);

      final isStalled = _bleDisconnectedDuringRecording ||
          (_elapsedSeconds >= 5 &&
              (_totalRecordedBytes == 0 ||
                  (_lastAudioAt != null &&
                      DateTime.now().difference(_lastAudioAt!).inSeconds >= 5)));
      if (isStalled != _currentAudioHealth.stalled) {
        _emitAudioHealth(
          bleConnected: !_bleDisconnectedDuringRecording,
          stalled: isStalled,
        );
      }
      if (isStalled && !_bleDisconnectedDuringRecording && !_stalledWarningEmitted) {
        _stalledWarningEmitted = true;
        final msg = _totalRecordedBytes == 0
            ? 'No audio packets received from Omi yet. Check wearable connection.'
            : 'Audio stream from Omi appears stalled.';
        debugPrint('[SessionManager] $msg');
        _warningController.add(msg);
      }
    });

    // 5. Subscribe to BLE Audio Stream
    await _audioStreamSub?.cancel();
    _audioStreamSub = BleService.instance.startPcmAudioStream().listen(
      (pcmBytes) {
        final chunk = Uint8List.fromList(pcmBytes);
        _recordedPcmChunks.add(chunk);
        _totalRecordedBytes += chunk.length;
        _receivedPacketCount++;
        _lastAudioAt = DateTime.now();
        _stalledWarningEmitted = false;
        _emitAudioHealth(
          bleConnected: !_bleDisconnectedDuringRecording,
          stalled: false,
        );

        // Stream to Gemini Live
        _geminiLive.sendPcmChunk(chunk);
      },
      onError: (Object err, StackTrace st) {
        debugPrint('[SessionManager] BLE audio stream error: $err\n$st');
        _emitAudioHealth(bleConnected: false, stalled: true);
        _warningController.add('Audio stream interrupted: $err');
      },
      onDone: () {
        if (!_isRecording) return;
        debugPrint('[SessionManager] BLE audio stream closed unexpectedly during recording.');
        _bleDisconnectedDuringRecording = true;
        _emitAudioHealth(bleConnected: false, stalled: true);
        _warningController.add('Omi audio stream ended unexpectedly. Tap Finish to save captured audio.');
      },
    );

    return true;
  }

  void _emitAudioHealth({required bool bleConnected, required bool stalled}) {
    _currentAudioHealth = RecordingAudioHealth(
      bytesReceived: _totalRecordedBytes,
      packetCount: _receivedPacketCount,
      bleConnected: bleConnected,
      stalled: stalled,
    );
    _audioHealthController.add(_currentAudioHealth);
  }

  Future<Session?> stopRecording() async {
    if (!_isRecording) return _activeSession;

    _isRecording = false;
    _recordingStateController.add(false);
    _durationTimer?.cancel();
    _durationTimer = null;

    await _bleDeviceSub?.cancel();
    _bleDeviceSub = null;
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _geminiTranscriptSub?.cancel();
    _geminiTranscriptSub = null;
    await _geminiLive.disconnect();

    await _stopForegroundRecordingService();

    if (_activeSession == null) return null;

    final finishTime = DateTime.now();
    final durationSec = _elapsedSeconds.toDouble();

    // Combine all PCM chunks
    final pcmBuffer = Uint8List(_totalRecordedBytes);
    int offset = 0;
    for (final chunk in _recordedPcmChunks) {
      pcmBuffer.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    // Package to WAV
    final wavBytes = AudioDecoder.createWav(pcmBuffer);

    final updatedSession = await finalizeStoppedSession(
      session: _activeSession!,
      wavBytes: wavBytes,
      liveTranscript: _liveTranscriptBuffer.toString(),
      finishTime: finishTime,
      durationSec: durationSec,
    );

    _activeSession = null;
    _recordedPcmChunks.clear();
    _totalRecordedBytes = 0;
    _receivedPacketCount = 0;
    _lastAudioAt = null;
    _bleDisconnectedDuringRecording = false;
    _stalledWarningEmitted = false;
    _liveTranscriptBuffer.clear();

    return updatedSession;
  }

  /// Finalizes a stopped session locally and on the backend.
  ///
  /// Handles 0-audio recordings cleanly so Firestore never remains stuck in
  /// `status='recording'`: saves live transcript segments if present, or marks
  /// the session `failed` when neither audio nor transcript was captured.
  @visibleForTesting
  Future<Session> finalizeStoppedSession({
    required Session session,
    required Uint8List wavBytes,
    required String liveTranscript,
    required DateTime finishTime,
    required double durationSec,
    bool? apiConfigured,
    Future<Session?> Function(String sessionId, Uint8List wavBytes)? uploadAudio,
    Future<bool> Function(
      String sessionId,
      List<Segment> segments, {
      String title,
      String summary,
      String? status,
    })? saveSegments,
  }) async {
    final isConfigured = apiConfigured ?? ApiClient.instance.isConfigured;
    final doUploadAudio = uploadAudio ?? ApiClient.instance.uploadAudio;
    final doSaveSegments = saveSegments ?? ApiClient.instance.saveSegments;

    Session updatedSession = session.copyWith(
      status: SessionStatus.processing,
      finishedAt: finishTime,
      durationSeconds: durationSec,
    );
    _saveSessionLocally(updatedSession);

    if (isConfigured && wavBytes.length > 44) {
      try {
        final diarizedSession = await doUploadAudio(updatedSession.id, wavBytes);
        if (diarizedSession != null) {
          updatedSession = diarizedSession;
          _saveSessionLocally(updatedSession);
          return updatedSession;
        }
      } catch (e) {
        debugPrint('[SessionManager] Audio upload failed for ${updatedSession.id}: $e');
      }
      return updatedSession;
    }

    final cleanTranscript = liveTranscript.trim();
    if (cleanTranscript.isNotEmpty) {
      final seg = Segment(
        speaker: 'Speaker 1',
        speakerId: 0,
        text: cleanTranscript,
        start: 0.0,
        end: durationSec,
      );
      updatedSession = updatedSession.copyWith(
        status: SessionStatus.completed,
        segments: [seg],
      );
      _saveSessionLocally(updatedSession);

      if (isConfigured) {
        await doSaveSegments(
          updatedSession.id,
          [seg],
          title: updatedSession.title,
          summary: updatedSession.summary,
          status: SessionStatus.completed.name,
        );
      }
      return updatedSession;
    }

    // Zero audio bytes AND zero live transcript: transition cleanly to failed
    // so neither local cache nor Firestore stays stuck in status='recording'.
    const noAudioSummary = 'No audio was received from the Omi device.';
    updatedSession = updatedSession.copyWith(
      status: SessionStatus.failed,
      summary: noAudioSummary,
    );
    _saveSessionLocally(updatedSession);

    if (isConfigured) {
      await doSaveSegments(
        updatedSession.id,
        const [],
        title: updatedSession.title,
        summary: noAudioSummary,
        status: SessionStatus.failed.name,
      );
    }
    return updatedSession;
  }

  Future<void> refreshSessions() async {
    if (ApiClient.instance.isConfigured) {
      try {
        final remote = await ApiClient.instance.listSessions();
        if (remote.isNotEmpty) {
          _cachedSessions = remote;
          _sessionsController.add(_cachedSessions);
          _persistLocalSessions();
          return;
        }
      } catch (_) {}
    }
    _sessionsController.add(_cachedSessions);
  }

  void updateCachedSession(Session session) {
    _saveSessionLocally(session);
  }

  void _saveSessionLocally(Session session) {
    int idx = _cachedSessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _cachedSessions[idx] = session;
    } else {
      _cachedSessions.insert(0, session);
    }
    _sessionsController.add(_cachedSessions);
    _persistLocalSessions();
  }

  Future<void> _loadLocalSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('local_sessions_cache') ?? '[]';
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _cachedSessions = list.map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
      _sessionsController.add(_cachedSessions);
    } catch (_) {}
  }

  Future<void> _persistLocalSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_cachedSessions.map((s) => s.toJson()).toList());
    await prefs.setString('local_sessions_cache', raw);
  }
}
