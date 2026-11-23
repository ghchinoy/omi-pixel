import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_decoder.dart';

/// Metadata for a locally persisted WAV file waiting to be uploaded to Cloud Run.
class PendingAudioUpload {
  final String sessionId;
  final String wavPath;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  const PendingAudioUpload({
    required this.sessionId,
    required this.wavPath,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  PendingAudioUpload copyWith({
    int? attempts,
    String? lastError,
  }) {
    return PendingAudioUpload(
      sessionId: sessionId,
      wavPath: wavPath,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'wav_path': wavPath,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'last_error': lastError,
      };

  factory PendingAudioUpload.fromJson(Map<String, dynamic> json) {
    return PendingAudioUpload(
      sessionId: json['session_id'] as String? ?? '',
      wavPath: json['wav_path'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}

/// Persists active PCM recording streams and finalized WAV files under
/// `getApplicationDocumentsDirectory()/omi_recordings` with a durable pending upload queue.
class RecordingFileStore {
  RecordingFileStore({Future<Directory> Function()? baseDirProvider})
      : _baseDirProvider = baseDirProvider ?? getApplicationDocumentsDirectory;

  static const String _recordingsSubdir = 'omi_recordings';
  static const String _queueFileName = 'pending_uploads.json';

  final Future<Directory> Function() _baseDirProvider;

  RandomAccessFile? _activePcmFile;
  File? _activePcmPath;
  String? _activeSessionId;
  int _chunksSinceFlush = 0;

  Future<Directory> _recordingsDir() async {
    final base = await _baseDirProvider();
    final dir = Directory('${base.path}/$_recordingsSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _queueFile() async {
    final dir = await _recordingsDir();
    return File('${dir.path}/$_queueFileName');
  }

  /// Opens a new on-device PCM file for streaming chunks during an active recording.
  Future<File> startPcmStream(String sessionId) async {
    await closeActivePcmStream();
    final dir = await _recordingsDir();
    final pcmFile = File('${dir.path}/$sessionId.pcm');
    _activePcmPath = pcmFile;
    _activeSessionId = sessionId;
    _chunksSinceFlush = 0;
    _activePcmFile = await pcmFile.open(mode: FileMode.write);
    return pcmFile;
  }

  /// Appends a decoded 16kHz PCM chunk directly to the active on-device file.
  void appendPcmChunk(Uint8List chunk) {
    final raf = _activePcmFile;
    if (raf == null || chunk.isEmpty) return;
    try {
      raf.writeFromSync(chunk);
      _chunksSinceFlush++;
      // Flush periodically (~every 2 seconds at 10-20ms Opus frames) for crash durability
      if (_chunksSinceFlush >= 100) {
        raf.flushSync();
        _chunksSinceFlush = 0;
      }
    } catch (e) {
      debugPrint('[RecordingFileStore] Failed writing PCM chunk for $_activeSessionId: $e');
    }
  }

  /// Closes the active PCM file without deleting it.
  Future<void> closeActivePcmStream() async {
    final raf = _activePcmFile;
    _activePcmFile = null;
    if (raf != null) {
      try {
        await raf.flush();
      } catch (_) {}
      try {
        await raf.close();
      } catch (_) {}
    }
  }

  /// Finalizes the active PCM file into a RIFF WAV file on disk and deletes the temp `.pcm`.
  ///
  /// Returns `null` if no PCM bytes were written (0-byte recording).
  Future<File?> finalizeActiveToWav(String sessionId) async {
    final pcmFile = _activePcmPath;
    await closeActivePcmStream();
    _activePcmPath = null;
    _activeSessionId = null;

    if (pcmFile == null || !await pcmFile.exists()) {
      return null;
    }

    return convertPcmFileToWav(sessionId, pcmFile);
  }

  /// Streams a `.pcm` file into `<sessionId>.wav` with a 44-byte RIFF header, then removes `.pcm`.
  Future<File?> convertPcmFileToWav(String sessionId, File pcmFile) async {
    if (!await pcmFile.exists()) return null;
    final pcmLength = await pcmFile.length();
    if (pcmLength <= 0) {
      try {
        await pcmFile.delete();
      } catch (_) {}
      return null;
    }

    final dir = await _recordingsDir();
    final wavFile = File('${dir.path}/$sessionId.wav');
    final sink = wavFile.openWrite();
    try {
      sink.add(AudioDecoder.createWavHeader(pcmLength));
      await sink.addStream(pcmFile.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }

    try {
      await pcmFile.delete();
    } catch (_) {}

    return wavFile;
  }

  /// Recovers any orphaned `.pcm` files left behind by a crash/process kill and queues them as WAVs.
  Future<List<PendingAudioUpload>> recoverOrphanedPcmFiles({String? activeSessionId}) async {
    final dir = await _recordingsDir();
    final queue = await loadPendingUploads();
    final existingIds = queue.map((e) => e.sessionId).toSet();
    bool changed = false;

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.pcm')) continue;
      final fileName = entity.uri.pathSegments.last;
      final sessionId = fileName.substring(0, fileName.length - 4);
      if (sessionId.isEmpty || sessionId == activeSessionId) continue;

      final wavFile = await convertPcmFileToWav(sessionId, entity);
      if (wavFile != null && !existingIds.contains(sessionId)) {
        debugPrint('[RecordingFileStore] Recovered interrupted recording $sessionId -> ${wavFile.path}');
        queue.insert(
          0,
          PendingAudioUpload(
            sessionId: sessionId,
            wavPath: wavFile.path,
            createdAt: DateTime.now(),
            lastError: 'Interrupted before upload completed',
          ),
        );
        existingIds.add(sessionId);
        changed = true;
      }
    }

    // Also prune entries whose WAV file no longer exists on disk
    final validQueue = <PendingAudioUpload>[];
    for (final entry in queue) {
      if (await File(entry.wavPath).exists()) {
        validQueue.add(entry);
      } else {
        changed = true;
      }
    }

    if (changed) {
      await savePendingUploads(validQueue);
    }
    return validQueue;
  }

  Future<List<PendingAudioUpload>> loadPendingUploads() async {
    try {
      final file = await _queueFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PendingAudioUpload.fromJson(e as Map<String, dynamic>))
          .where((e) => e.sessionId.isNotEmpty && e.wavPath.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[RecordingFileStore] Failed loading pending uploads queue: $e');
      return [];
    }
  }

  Future<void> savePendingUploads(List<PendingAudioUpload> queue) async {
    try {
      final file = await _queueFile();
      await file.writeAsString(jsonEncode(queue.map((e) => e.toJson()).toList()), flush: true);
    } catch (e) {
      debugPrint('[RecordingFileStore] Failed saving pending uploads queue: $e');
    }
  }

  Future<List<PendingAudioUpload>> enqueuePendingUpload(PendingAudioUpload item) async {
    final queue = await loadPendingUploads();
    final idx = queue.indexWhere((e) => e.sessionId == item.sessionId);
    if (idx >= 0) {
      queue[idx] = item;
    } else {
      queue.insert(0, item);
    }
    await savePendingUploads(queue);
    return queue;
  }

  /// Removes a completed upload from the queue and deletes its local WAV file.
  Future<List<PendingAudioUpload>> markUploadComplete(String sessionId) async {
    final queue = await loadPendingUploads();
    final matches = queue.where((e) => e.sessionId == sessionId).toList();
    queue.removeWhere((e) => e.sessionId == sessionId);
    await savePendingUploads(queue);

    for (final item in matches) {
      try {
        final f = File(item.wavPath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint('[RecordingFileStore] Failed deleting uploaded WAV ${item.wavPath}: $e');
      }
    }
    return queue;
  }

  Future<List<PendingAudioUpload>> recordUploadFailure(String sessionId, String errorMessage) async {
    final queue = await loadPendingUploads();
    final idx = queue.indexWhere((e) => e.sessionId == sessionId);
    if (idx >= 0) {
      final current = queue[idx];
      queue[idx] = current.copyWith(
        attempts: current.attempts + 1,
        lastError: errorMessage,
      );
      await savePendingUploads(queue);
    }
    return queue;
  }
}
