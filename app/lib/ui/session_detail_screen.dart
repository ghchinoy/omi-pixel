import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../models/segment.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recording_file_store.dart';
import '../services/session_manager.dart';
import '../services/settings_service.dart';
import '../theme/lustrous_theme.dart';

class SessionDetailScreen extends StatefulWidget {
  final Session session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Session _session;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _audioAvailable = false;
  bool _audioLoading = false;
  bool _detailLoading = false;
  bool _retryingUpload = false;
  double _currentPositionSec = 0.0;
  String _transcriptView = 'diarized';

  StreamSubscription? _posSub;
  StreamSubscription<List<Session>>? _sessionsSub;
  Timer? _processingPollTimer;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session.smartTranscript.trim().isNotEmpty) {
      _transcriptView = 'smart';
    }
    _sessionsSub = SessionManager.instance.sessionsStream.listen((sessions) {
      if (!mounted) return;
      for (final s in sessions) {
        if (s.id == _session.id) {
          final hadNoAudio = !_session.hasAudio && _session.audioUrl.isEmpty;
          final hadNoSmart = _session.smartTranscript.trim().isEmpty;
          setState(() {
            _session = s;
            if (hadNoSmart && s.smartTranscript.trim().isNotEmpty) {
              _transcriptView = 'smart';
            }
          });
          if (hadNoAudio && (s.hasAudio || s.audioUrl.isNotEmpty)) {
            _initAudio();
          }
          if (s.status != SessionStatus.processing) {
            _processingPollTimer?.cancel();
            _processingPollTimer = null;
          }
          break;
        }
      }
    });
    _fetchFullSessionDetail();
    _initAudio();
    _startProcessingPollIfNeeded();
  }

  void _startProcessingPollIfNeeded() {
    if (_session.status != SessionStatus.processing || !ApiClient.instance.isConfigured) {
      _processingPollTimer?.cancel();
      _processingPollTimer = null;
      return;
    }
    _processingPollTimer?.cancel();
    _processingPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _session.status != SessionStatus.processing) {
        _processingPollTimer?.cancel();
        _processingPollTimer = null;
        return;
      }
      await _fetchFullSessionDetail(silent: true);
    });
  }

  Future<void> _fetchFullSessionDetail({bool silent = false}) async {
    if (!ApiClient.instance.isConfigured) return;

    // If segments or summary are missing, fetch the full SessionDetail from backend
    if (!silent && (_session.segments.isEmpty || _session.summary.isEmpty || !_session.hasAudio)) {
      setState(() {
        _detailLoading = true;
      });
    }

    try {
      final detailed = await ApiClient.instance.getSession(_session.id);
      if (detailed != null && mounted) {
        final hadNoAudio = !_session.hasAudio && _session.audioUrl.isEmpty;
        final hadNoSmart = _session.smartTranscript.trim().isEmpty;
        setState(() {
          _session = detailed;
          _detailLoading = false;
          if (hadNoSmart && detailed.smartTranscript.trim().isNotEmpty) {
            _transcriptView = 'smart';
          }
        });
        SessionManager.instance.updateCachedSession(detailed);

        // If audio became available from detail fetch, initialize audio player
        if (hadNoAudio && (detailed.hasAudio || detailed.audioUrl.isNotEmpty)) {
          _initAudio();
        }
        if (detailed.status != SessionStatus.processing) {
          _processingPollTimer?.cancel();
          _processingPollTimer = null;
        }
      } else if (mounted) {
        setState(() {
          _detailLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _detailLoading = false;
        });
      }
    }
  }

  Future<void> _initAudio() async {
    final baseUrl = SettingsService.instance.cloudRunUrl;
    if (baseUrl.isEmpty || (!_session.hasAudio && _session.audioUrl.isEmpty)) {
      return;
    }

    setState(() {
      _audioLoading = true;
    });

    try {
      final token = await AuthService.instance.getIdToken();
      final audioUrl = '$baseUrl/api/sessions/${_session.id}/audio';
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
    _processingPollTimer?.cancel();
    _sessionsSub?.cancel();
    _posSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  LustrousCategoryColor _getSpeakerCategory(BuildContext context, int speakerId) {
    return LustrousColors.of(context).speakerColorFor(speakerId);
  }

  String _formatDuration(double seconds) {
    int s = seconds.toInt();
    int mins = s ~/ 60;
    int secs = s % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _copyTranscript(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('Title: ${_session.title}');
    buffer.writeln('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(_session.startedAt.toLocal())}');
    if (_session.summary.isNotEmpty) {
      buffer.writeln('\nSummary:\n${_session.summary}');
    }
    if (_session.smartTranscript.trim().isNotEmpty) {
      buffer.writeln('\nSmart Corrected Transcript:\n${_session.smartTranscript.trim()}');
    }
    if (_session.segments.isNotEmpty) {
      buffer.writeln('\nDiarized Transcript:');
      for (final seg in _session.segments) {
        buffer.writeln('[${_formatDuration(seg.start)}] ${seg.speaker}: ${seg.text}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transcript copied to clipboard')),
    );
  }

  Future<void> _retrySessionUpload() async {
    if (_retryingUpload) return;
    setState(() => _retryingUpload = true);
    try {
      final result = await SessionManager.instance.retryPendingUpload(_session.id);
      if (!mounted) return;
      if (result.isSuccess && result.session != null) {
        setState(() {
          _session = result.session!;
        });
        _initAudio();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio uploaded and diarized.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Upload retry failed.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _retryingUpload = false);
      }
    }
  }

  Future<void> _confirmDeleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: const Text('This permanently deletes the transcript and stored audio recording.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await SessionManager.instance.deleteSession(_session.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation deleted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete conversation from server'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
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
    final lustrous = LustrousColors.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy • HH:mm');
    final session = _session;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title.isNotEmpty ? session.title : 'Conversation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy Transcript',
            onPressed: () => _copyTranscript(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete Conversation',
            onPressed: _confirmDeleteSession,
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
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            dateFormat.format(session.startedAt.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      if (session.durationSeconds > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, size: 14, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(session.durationSeconds),
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      if (session.isSmartMode)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: lustrous.speakerColorFor(0).container,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_fix_high, size: 12, color: lustrous.speakerColorFor(0).onContainer),
                              const SizedBox(width: 4),
                              Text(
                                'SMART',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: lustrous.speakerColorFor(0).onContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Pending Local Upload Banner (only when not actively diarizing right now)
          StreamBuilder<Set<String>>(
            stream: SessionManager.instance.diarizingSessionsStream,
            initialData: SessionManager.instance.activeDiarizingSessions,
            builder: (context, diarizingSnap) {
              final isActivelyDiarizing = (diarizingSnap.data ?? const <String>{}).contains(session.id);
              if (isActivelyDiarizing || session.status == SessionStatus.processing) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Card(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.45)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Diarizing in Background…',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Gemini 3.5 Transcribe is separating speakers and summarizing. This view updates automatically.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return StreamBuilder<List<PendingAudioUpload>>(
                stream: SessionManager.instance.pendingUploadsStream,
                initialData: SessionManager.instance.pendingUploads,
                builder: (context, snapshot) {
                  final pendingItem = SessionManager.instance.pendingUploadFor(session.id);
                  if (pendingItem == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Card(
                      color: lustrous.warningContainer.withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: lustrous.warning.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.cloud_upload_outlined, color: lustrous.warning, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Audio saved on device — upload pending',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: lustrous.onWarningContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (pendingItem.lastError != null && pendingItem.lastError!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                pendingItem.lastError!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: _retryingUpload ? null : _retrySessionUpload,
                                icon: _retryingUpload
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh, size: 16),
                                label: Text(_retryingUpload ? 'Uploading...' : 'Retry Upload'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // Audio Playback Player Card
          if (_audioAvailable || _audioLoading) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
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
                        'AI Summary',
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
          if (session.smartTranscript.trim().isNotEmpty) ...[
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(
                  value: 'smart',
                  label: Text('Smart Transcript'),
                  icon: Icon(Icons.auto_fix_high, size: 16),
                ),
                ButtonSegment(
                  value: 'diarized',
                  label: Text('Diarized (${session.segments.length})'),
                  icon: const Icon(Icons.people_outline, size: 16),
                ),
              ],
              selected: {_transcriptView},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => _transcriptView = selection.first);
                }
              },
            ),
            const SizedBox(height: 14),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Diarized Turns (${session.segments.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_detailLoading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                if (_audioAvailable)
                  Text(
                    'Tap turn to listen',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          if (session.smartTranscript.trim().isNotEmpty && _transcriptView == 'smart')
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_fix_high, size: 16, color: lustrous.speakerColorFor(0).onContainer),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Smart Corrected Transcript (self-corrections resolved)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      session.smartTranscript.trim(),
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 15.5),
                    ),
                  ],
                ),
              ),
            )
          else if (session.segments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: _detailLoading
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Loading speaker diarization...'),
                          ],
                        )
                      : Text(
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
    final speakerPalette = _getSpeakerCategory(context, seg.speakerId);
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
              ? speakerPalette.container.withValues(alpha: 0.55)
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isPlayingThisSegment
                ? speakerPalette.onContainer
                : theme.colorScheme.outlineVariant,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: speakerPalette.container,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    seg.speaker,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: speakerPalette.onContainer,
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
