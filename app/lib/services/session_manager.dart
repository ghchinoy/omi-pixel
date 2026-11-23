import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'recording_file_store.dart';
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

@pragma('vm:entry-point')
void omiForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_OmiRecordingTaskHandler());
}

class _OmiRecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.sendDataToMain('open_live_recording');
  }
}

class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  final GeminiLiveService _geminiLive = GeminiLiveService();
  RecordingFileStore _fileStore = RecordingFileStore();
  int _totalRecordedBytes = 0;
  int _receivedPacketCount = 0;
  DateTime? _lastAudioAt;
  bool _bleDisconnectedDuringRecording = false;
  bool _stalledWarningEmitted = false;
  bool _retryingPendingUploads = false;

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

  final _pendingUploadsController = StreamController<List<PendingAudioUpload>>.broadcast();
  Stream<List<PendingAudioUpload>> get pendingUploadsStream => _pendingUploadsController.stream;

  final _diarizingSessionsController = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get diarizingSessionsStream => _diarizingSessionsController.stream;

  final _diarizationCompletedController = StreamController<Session>.broadcast();
  Stream<Session> get diarizationCompletedStream => _diarizationCompletedController.stream;

  final Set<String> _activeDiarizingSessions = {};
  Set<String> get activeDiarizingSessions => Set.unmodifiable(_activeDiarizingSessions);

  bool isDiarizing(String sessionId) => _activeDiarizingSessions.contains(sessionId);

  List<PendingAudioUpload> _pendingUploads = [];
  List<PendingAudioUpload> get pendingUploads => List.unmodifiable(_pendingUploads);

  bool hasPendingUpload(String sessionId) =>
      _pendingUploads.any((u) => u.sessionId == sessionId);

  PendingAudioUpload? pendingUploadFor(String sessionId) {
    for (final u in _pendingUploads) {
      if (u.sessionId == sessionId) return u;
    }
    return null;
  }

  @visibleForTesting
  void setFileStoreForTesting(RecordingFileStore store) {
    _fileStore = store;
  }

  @visibleForTesting
  void setRecordingStateForTesting(bool recording, {int elapsedSeconds = 0}) {
    _isRecording = recording;
    _elapsedSeconds = elapsedSeconds;
    _recordingStateController.add(recording);
    _durationController.add(elapsedSeconds);
  }

  RecordingAudioHealth _currentAudioHealth = const RecordingAudioHealth();
  RecordingAudioHealth get currentAudioHealth => _currentAudioHealth;

  String? _lastForegroundServiceError;
  String? get lastForegroundServiceError => _lastForegroundServiceError;

  String? _lastUploadError;
  String? get lastUploadError => _lastUploadError;

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
    // Ensure no stale foreground notification remains when idle on startup
    if (!_isRecording) {
      await _stopForegroundRecordingService();
    }
    await _recoverAndRetryPendingUploadsOnStartup();
  }

  Future<void> _recoverAndRetryPendingUploadsOnStartup() async {
    try {
      _pendingUploads = await _fileStore.recoverOrphanedPcmFiles(
        activeSessionId: _activeSession?.id,
      );
      _pendingUploadsController.add(_pendingUploads);
      if (_pendingUploads.isNotEmpty && ApiClient.instance.isConfigured) {
        debugPrint('[SessionManager] Found ${_pendingUploads.length} pending audio upload(s); retrying in background.');
        unawaited(retryAllPendingUploads());
      }
    } catch (e) {
      debugPrint('[SessionManager] Error recovering pending uploads: $e');
    }
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
                  notificationInitialRoute: '/live',
                  callback: omiForegroundTaskCallback,
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

  Future<void> _updateForegroundNotificationForDiarization() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Omi Diarizing in Background',
          notificationText: 'Uploading & processing conversation audio...',
        );
      }
    } catch (e) {
      debugPrint('[SessionManager] Error updating foreground notification: $e');
    }
  }

  Future<void> _stopForegroundServiceIfIdle() async {
    if (_isRecording || _activeDiarizingSessions.isNotEmpty) return;
    await _stopForegroundRecordingService();
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
      transcriptionMode: SettingsService.instance.liveTranscriptionMode,
      startedAt: now,
      createdAt: now,
    );

    _totalRecordedBytes = 0;
    _receivedPacketCount = 0;
    _lastAudioAt = null;
    _bleDisconnectedDuringRecording = false;
    _stalledWarningEmitted = false;
    _lastUploadError = null;
    _liveTranscriptBuffer.clear();
    _elapsedSeconds = 0;
    _isRecording = true;
    _emitAudioHealth(bleConnected: true, stalled: false);
    _recordingStateController.add(true);
    _transcriptStreamController.add('');

    // Open on-device PCM file under ApplicationDocumentsDirectory for crash-safe streaming
    try {
      await _fileStore.startPcmStream(sessionId);
    } catch (e) {
      final msg = 'Failed to open local recording file: $e';
      debugPrint('[SessionManager] $msg');
      _warningController.add(msg);
    }

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
        _fileStore.appendPcmChunk(chunk);
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

    if (_activeSession == null) {
      await _stopForegroundServiceIfIdle();
      return null;
    }

    final finishTime = DateTime.now();
    final durationSec = _elapsedSeconds.toDouble();

    // Finalize disk-streamed PCM file into a durable local WAV file (<100ms)
    final wavFile = await _fileStore.finalizeActiveToWav(_activeSession!.id);

    final updatedSession = await finalizeStoppedSession(
      session: _activeSession!,
      wavFile: wavFile,
      liveTranscript: _liveTranscriptBuffer.toString(),
      finishTime: finishTime,
      durationSec: durationSec,
      awaitUpload: false,
    );

    _activeSession = null;
    _totalRecordedBytes = 0;
    _receivedPacketCount = 0;
    _lastAudioAt = null;
    _bleDisconnectedDuringRecording = false;
    _stalledWarningEmitted = false;
    _liveTranscriptBuffer.clear();

    if (_activeDiarizingSessions.isNotEmpty) {
      await _updateForegroundNotificationForDiarization();
    } else {
      await _stopForegroundServiceIfIdle();
    }

    return updatedSession;
  }

  /// Finalizes a stopped session locally and on the backend.
  ///
  /// When [awaitUpload] is `false` (default for interactive stop), the finalized
  /// WAV is durably queued and uploaded/diarized asynchronously in the background
  /// so callers return immediately without blocking UI navigation.
  /// Handles 0-audio recordings cleanly so Firestore never remains stuck in `status='recording'`.
  @visibleForTesting
  Future<Session> finalizeStoppedSession({
    required Session session,
    File? wavFile,
    Uint8List? wavBytes,
    required String liveTranscript,
    required DateTime finishTime,
    required double durationSec,
    bool awaitUpload = true,
    bool? apiConfigured,
    Future<AudioUploadResult> Function(String sessionId, File wavFile)? uploadAudioFile,
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
    final doUploadFile = uploadAudioFile ??
        (String id, File file) => ApiClient.instance.uploadAudioFile(
              id,
              file,
              mode: session.transcriptionMode,
            );
    final doSaveSegments = saveSegments ?? ApiClient.instance.saveSegments;

    Session updatedSession = session.copyWith(
      status: SessionStatus.processing,
      finishedAt: finishTime,
      durationSeconds: durationSec,
    );
    _saveSessionLocally(updatedSession);

    final hasWavFile = wavFile != null && await wavFile.exists() && await wavFile.length() > 44;
    final hasWavBytes = wavBytes != null && wavBytes.length > 44;

    if (hasWavFile) {
      // Enqueue durably BEFORE uploading so interruptions/failures never lose the WAV
      _pendingUploads = await _fileStore.enqueuePendingUpload(
        PendingAudioUpload(
          sessionId: updatedSession.id,
          wavPath: wavFile.path,
          createdAt: finishTime,
        ),
      );
      _pendingUploadsController.add(_pendingUploads);

      if (isConfigured) {
        if (awaitUpload) {
          final result = await _uploadQueuedItem(
            updatedSession.id,
            wavFile,
            doUploadFile: doUploadFile,
          );
          if (result.session != null) {
            return result.session!;
          }
          return updatedSession;
        }

        // Non-blocking background upload & diarization
        _activeDiarizingSessions.add(updatedSession.id);
        _diarizingSessionsController.add(Set.unmodifiable(_activeDiarizingSessions));
        unawaited(_runBackgroundUpload(
          updatedSession.id,
          wavFile,
          doUploadFile: doUploadFile,
        ));
        return updatedSession;
      }
      const msg = 'Cloud Run URL not configured. Recording saved on device for later upload.';
      _lastUploadError = msg;
      _pendingUploads = await _fileStore.recordUploadFailure(updatedSession.id, msg);
      _pendingUploadsController.add(_pendingUploads);
      _warningController.add(msg);
      return updatedSession;
    }

    if (isConfigured && hasWavBytes) {
      try {
        final doUploadBytes = uploadAudio ?? ApiClient.instance.uploadAudio;
        final diarizedSession = await doUploadBytes(updatedSession.id, wavBytes);
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

  Future<void> _runBackgroundUpload(
    String sessionId,
    File wavFile, {
    required Future<AudioUploadResult> Function(String sessionId, File wavFile) doUploadFile,
  }) async {
    try {
      final result = await _uploadQueuedItem(
        sessionId,
        wavFile,
        doUploadFile: doUploadFile,
      );
      if (result.isSuccess && result.session != null) {
        _diarizationCompletedController.add(result.session!);
      }
    } finally {
      _activeDiarizingSessions.remove(sessionId);
      _diarizingSessionsController.add(Set.unmodifiable(_activeDiarizingSessions));
      await _stopForegroundServiceIfIdle();
    }
  }

  Future<AudioUploadResult> _uploadQueuedItem(
    String sessionId,
    File wavFile, {
    required Future<AudioUploadResult> Function(String sessionId, File wavFile) doUploadFile,
  }) async {
    final result = await doUploadFile(sessionId, wavFile);
    if (result.isSuccess && result.session != null) {
      _lastUploadError = null;
      _saveSessionLocally(result.session!);
      _pendingUploads = await _fileStore.markUploadComplete(sessionId);
      _pendingUploadsController.add(_pendingUploads);
      debugPrint('[SessionManager] Uploaded and cleaned up local WAV for $sessionId.');
      return result;
    }

    final errMsg = result.error ?? 'Audio upload failed; saved on device for retry.';
    _lastUploadError = errMsg;
    _pendingUploads = await _fileStore.recordUploadFailure(sessionId, errMsg);
    _pendingUploadsController.add(_pendingUploads);
    _warningController.add(errMsg);
    debugPrint('[SessionManager] Keeping local WAV for $sessionId after failure: $errMsg');
    return result;
  }

  /// Retries uploading a single pending session WAV from disk.
  Future<AudioUploadResult> retryPendingUpload(
    String sessionId, {
    Future<AudioUploadResult> Function(String sessionId, File wavFile)? uploadAudioFile,
  }) async {
    final item = pendingUploadFor(sessionId);
    if (item == null) {
      return const AudioUploadResult(error: 'No pending upload found for this session.');
    }
    final wavFile = File(item.wavPath);
    if (!await wavFile.exists()) {
      _pendingUploads = await _fileStore.markUploadComplete(sessionId);
      _pendingUploadsController.add(_pendingUploads);
      return const AudioUploadResult(error: 'Local audio file no longer exists on device.');
    }
    return _uploadQueuedItem(
      sessionId,
      wavFile,
      doUploadFile: uploadAudioFile ?? ApiClient.instance.uploadAudioFile,
    );
  }

  /// Retries all pending on-device WAV uploads sequentially.
  Future<int> retryAllPendingUploads({
    Future<AudioUploadResult> Function(String sessionId, File wavFile)? uploadAudioFile,
  }) async {
    if (_retryingPendingUploads) return 0;
    _retryingPendingUploads = true;
    int succeeded = 0;
    try {
      final snapshot = List<PendingAudioUpload>.from(_pendingUploads);
      for (final item in snapshot) {
        final res = await retryPendingUpload(
          item.sessionId,
          uploadAudioFile: uploadAudioFile,
        );
        if (res.isSuccess) {
          succeeded++;
        }
      }
    } finally {
      _retryingPendingUploads = false;
    }
    return succeeded;
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

  /// Deletes a session from backend, local cache, and any queued local WAV file.
  Future<bool> deleteSession(String sessionId) async {
    final remoteOk = await ApiClient.instance.deleteSession(sessionId);
    if (!remoteOk) return false;

    _cachedSessions.removeWhere((s) => s.id == sessionId);
    _sessionsController.add(_cachedSessions);
    await _persistLocalSessions();

    _pendingUploads = await _fileStore.markUploadComplete(sessionId);
    _pendingUploadsController.add(_pendingUploads);
    return true;
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
