import 'segment.dart';

enum SessionStatus {
  recording,
  processing,
  completed,
  failed,
}

class Session {
  final String id;
  final String deviceId;
  final String title;
  final String summary;
  final String audioUrl;
  final bool hasAudio;
  final SessionStatus status;
  final String language;
  final double durationSeconds;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;
  final List<Segment> segments;

  Session({
    required this.id,
    required this.deviceId,
    required this.title,
    this.summary = '',
    this.audioUrl = '',
    this.hasAudio = false,
    this.status = SessionStatus.recording,
    this.language = 'en',
    this.durationSeconds = 0.0,
    required this.startedAt,
    this.finishedAt,
    required this.createdAt,
    this.segments = const [],
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    var rawSegments = json['segments'] as List<dynamic>? ?? [];
    List<Segment> segs = rawSegments
        .map((s) => Segment.fromJson(s as Map<String, dynamic>))
        .toList();

    final audioUrl = json['audio_url'] as String? ?? '';
    final hasAudio = json['has_audio'] as bool? ?? (audioUrl.isNotEmpty);

    return Session(
      id: json['id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Conversation',
      summary: json['summary'] as String? ?? '',
      audioUrl: audioUrl,
      hasAudio: hasAudio,
      status: _parseStatus(json['status'] as String?),
      language: json['language'] as String? ?? 'en',
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ?? DateTime.now(),
      finishedAt: json['finished_at'] != null ? DateTime.tryParse(json['finished_at'] as String) : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      segments: segs,
    );
  }

  static SessionStatus _parseStatus(String? status) {
    switch (status) {
      case 'processing':
        return SessionStatus.processing;
      case 'completed':
        return SessionStatus.completed;
      case 'failed':
        return SessionStatus.failed;
      default:
        return SessionStatus.recording;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    'title': title,
    'summary': summary,
    'audio_url': audioUrl,
    'has_audio': hasAudio,
    'status': status.name,
    'language': language,
    'duration_seconds': durationSeconds,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  Session copyWith({
    String? title,
    String? summary,
    String? audioUrl,
    bool? hasAudio,
    SessionStatus? status,
    double? durationSeconds,
    DateTime? finishedAt,
    List<Segment>? segments,
  }) {
    return Session(
      id: id,
      deviceId: deviceId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      audioUrl: audioUrl ?? this.audioUrl,
      hasAudio: hasAudio ?? this.hasAudio,
      status: status ?? this.status,
      language: language,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      createdAt: createdAt,
      segments: segments ?? this.segments,
    );
  }
}
