import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/segment.dart';
import '../models/session.dart';
import 'api_client.dart';
import 'audio_decoder.dart';
import 'ble_service.dart';
import 'gemini_live_service.dart';
import 'settings_service.dart';

class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  final GeminiLiveService _geminiLive = GeminiLiveService();
  final List<Uint8List> _recordedPcmChunks = [];
  int _totalRecordedBytes = 0;

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

  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  StreamSubscription? _audioStreamSub;
  StreamSubscription? _geminiTranscriptSub;

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
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
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
    _liveTranscriptBuffer.clear();
    _elapsedSeconds = 0;
    _isRecording = true;
    _recordingStateController.add(true);
    _transcriptStreamController.add('');

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

    // 3. Start Foreground notification
    try {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.restartService();
      } else {
        FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'Omi Recording Active',
          notificationText: 'Streaming and transcribing conversation...',
        );
      }
    } catch (_) {}

    // 4. Start timer
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      _durationController.add(_elapsedSeconds);
    });

    // 5. Subscribe to BLE Audio Stream
    _audioStreamSub?.cancel();
    _audioStreamSub = BleService.instance.startPcmAudioStream().listen((pcmBytes) {
      final chunk = Uint8List.fromList(pcmBytes);
      _recordedPcmChunks.add(chunk);
      _totalRecordedBytes += chunk.length;

      // Stream to Gemini Live
      _geminiLive.sendPcmChunk(chunk);
    });

    return true;
  }

  Future<Session?> stopRecording() async {
    if (!_isRecording) return _activeSession;

    _isRecording = false;
    _recordingStateController.add(false);
    _durationTimer?.cancel();
    _durationTimer = null;

    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _geminiTranscriptSub?.cancel();
    _geminiTranscriptSub = null;
    await _geminiLive.disconnect();

    try {
      FlutterForegroundTask.stopService();
    } catch (_) {}

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

    Session updatedSession = _activeSession!.copyWith(
      status: SessionStatus.processing,
      finishedAt: finishTime,
      durationSeconds: durationSec,
    );

    // Save initial local state
    _saveSessionLocally(updatedSession);

    // Upload audio WAV to Cloud Run Go service for Gemini 3.5 diarization
    if (ApiClient.instance.isConfigured && wavBytes.length > 44) {
      try {
        final diarizedSession = await ApiClient.instance.uploadAudio(updatedSession.id, wavBytes);
        if (diarizedSession != null) {
          updatedSession = diarizedSession;
          _saveSessionLocally(updatedSession);
        }
      } catch (_) {}
    } else if (_liveTranscriptBuffer.isNotEmpty) {
      // Fallback: save live transcript as single segment if Cloud Run not configured
      final seg = Segment(
        speaker: 'Speaker 1',
        speakerId: 0,
        text: _liveTranscriptBuffer.toString(),
        start: 0.0,
        end: durationSec,
      );
      updatedSession = updatedSession.copyWith(
        status: SessionStatus.completed,
        segments: [seg],
      );
      _saveSessionLocally(updatedSession);
    }

    _activeSession = null;
    _recordedPcmChunks.clear();
    _totalRecordedBytes = 0;
    _liveTranscriptBuffer.clear();

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
