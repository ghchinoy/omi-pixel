class Segment {
  final String speaker;
  final int speakerId;
  final String text;
  final double start;
  final double end;
  final bool isUser;

  Segment({
    required this.speaker,
    required this.speakerId,
    required this.text,
    required this.start,
    required this.end,
    this.isUser = false,
  });

  factory Segment.fromJson(Map<String, dynamic> json) {
    return Segment(
      speaker: json['speaker'] as String? ?? 'Speaker 1',
      speakerId: json['speaker_id'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      isUser: json['is_user'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'speaker_id': speakerId,
    'text': text,
    'start': start,
    'end': end,
    'is_user': isUser,
  };
}
