import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../models/segment.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';

class SessionDetailScreen extends StatefulWidget {
  final Session session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _audioAvailable = false;
  bool _audioLoading = false;
  double _currentPositionSec = 0.0;

  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final baseUrl = SettingsService.instance.cloudRunUrl;
    if (baseUrl.isEmpty || (!widget.session.hasAudio && widget.session.audioUrl.isEmpty)) {
      return;
    }

    setState(() {
      _audioLoading = true;
    });

    try {
      final token = await AuthService.instance.getIdToken();
      final audioUrl = '$baseUrl/api/sessions/${widget.session.id}/audio';
      final headers = (token != null && token.isNotEmpty)
          ? {'Authorization': 'Bearer $token'}
          : <String, String>{};

      await _audioPlayer.setUrl(audioUrl, headers: headers);
      if (mounted) {
        setState(() {
          _audioAvailable = true;
          _audioLoading = false;
        });
      }

      _posSub = _audioPlayer.positionStream.listen((pos) {
        if (mounted) {
          setState(() {
            _currentPositionSec = pos.inMilliseconds / 1000.0;
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _audioLoading = false;
          _audioAvailable = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Color _getSpeakerColor(int speakerId) {
    const colors = [
      Color(0xFF38BDF8), // Blue
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber
      Color(0xFFEC4899), // Pink
      Color(0xFF8B5CF6), // Purple
      Color(0xFF06B6D4), // Cyan
    ];
    return colors[speakerId % colors.length];
  }

  String _formatDuration(double seconds) {
    int s = seconds.toInt();
    int mins = s ~/ 60;
    int secs = s % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _copyTranscript(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('Title: ${widget.session.title}');
    buffer.writeln('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(widget.session.startedAt)}');
    if (widget.session.summary.isNotEmpty) {
      buffer.writeln('\nSummary:\n${widget.session.summary}\n');
    }
    buffer.writeln('Transcript:');
    for (final seg in widget.session.segments) {
      buffer.writeln('[${_formatDuration(seg.start)}] ${seg.speaker}: ${seg.text}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transcript copied to clipboard')),
    );
  }

  void _seekTo(double startSeconds) {
    if (_audioAvailable) {
      _audioPlayer.seek(Duration(milliseconds: (startSeconds * 1000).toInt()));
      _audioPlayer.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy • HH:mm');
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title.isNotEmpty ? session.title : 'Conversation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy Transcript',
            onPressed: () => _copyTranscript(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        dateFormat.format(session.startedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 16),
                      if (session.durationSeconds > 0) ...[
                        Icon(Icons.timer, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(session.durationSeconds),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Audio Playback Player Card
          if (_audioAvailable || _audioLoading) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.audiotrack, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Session Recording (16kHz WAV)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        if (_audioLoading)
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    if (_audioAvailable) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          StreamBuilder<PlayerState>(
                            stream: _audioPlayer.playerStateStream,
                            builder: (context, snapshot) {
                              final playerState = snapshot.data;
                              final processingState = playerState?.processingState;
                              final playing = playerState?.playing ?? false;

                              if (processingState == ProcessingState.loading ||
                                  processingState == ProcessingState.buffering) {
                                return const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                );
                              } else if (!playing) {
                                return IconButton(
                                  icon: const Icon(Icons.play_circle_fill, size: 36),
                                  color: theme.colorScheme.primary,
                                  onPressed: _audioPlayer.play,
                                );
                              } else if (processingState != ProcessingState.completed) {
                                return IconButton(
                                  icon: const Icon(Icons.pause_circle_filled, size: 36),
                                  color: theme.colorScheme.primary,
                                  onPressed: _audioPlayer.pause,
                                );
                              } else {
                                return IconButton(
                                  icon: const Icon(Icons.replay_circle_filled, size: 36),
                                  color: theme.colorScheme.primary,
                                  onPressed: () => _audioPlayer.seek(Duration.zero),
                                );
                              }
                            },
                          ),
                          Expanded(
                            child: StreamBuilder<Duration?>(
                              stream: _audioPlayer.durationStream,
                              builder: (context, durSnapshot) {
                                final totalDur = durSnapshot.data ??
                                    Duration(seconds: session.durationSeconds.toInt());
                                final maxSec = totalDur.inMilliseconds > 0
                                    ? totalDur.inMilliseconds / 1000.0
                                    : session.durationSeconds;

                                return Slider(
                                  value: _currentPositionSec.clamp(0.0, maxSec > 0 ? maxSec : 1.0),
                                  min: 0.0,
                                  max: maxSec > 0 ? maxSec : 1.0,
                                  activeColor: theme.colorScheme.primary,
                                  onChanged: (val) {
                                    _audioPlayer.seek(Duration(milliseconds: (val * 1000).toInt()));
                                  },
                                );
                              },
                            ),
                          ),
                          Text(
                            _formatDuration(_currentPositionSec),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Gemini Summary Card
          if (session.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Gemini 3.7 Flash Summary',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Diarized Turns (${session.segments.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_audioAvailable)
                Text(
                  'Tap turn to listen',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (session.segments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    'No speaker segments available for this session.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            ...session.segments.map((seg) => _buildSegmentBubble(context, seg)),
        ],
      ),
    );
  }

  Widget _buildSegmentBubble(BuildContext context, Segment seg) {
    final theme = Theme.of(context);
    final speakerColor = _getSpeakerColor(seg.speakerId);
    final isPlayingThisSegment = _audioAvailable &&
        _currentPositionSec >= seg.start &&
        _currentPositionSec <= seg.end;

    return InkWell(
      onTap: () => _seekTo(seg.start),
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: isPlayingThisSegment
              ? speakerColor.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isPlayingThisSegment
                ? speakerColor
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isPlayingThisSegment ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: speakerColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: speakerColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    seg.speaker,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: speakerColor,
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (_audioAvailable) ...[
                      Icon(Icons.play_arrow, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      '${_formatDuration(seg.start)} - ${_formatDuration(seg.end)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              seg.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
