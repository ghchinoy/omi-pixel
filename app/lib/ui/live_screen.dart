import 'dart:async';
import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import 'session_detail_screen.dart';

class LiveScreen extends StatefulWidget {
  static bool isActive = false;

  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  StreamSubscription? _transcriptSub;
  StreamSubscription? _warningSub;
  bool _stopping = false;
  bool _confirmDialogOpen = false;
  String? _foregroundWarning;

  @override
  void initState() {
    super.initState();
    LiveScreen.isActive = true;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _foregroundWarning = SessionManager.instance.lastForegroundServiceError;
    _warningSub = SessionManager.instance.warningStream.listen((msg) {
      if (!mounted) return;
      setState(() => _foregroundWarning = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
        ),
      );
    });

    _transcriptSub = SessionManager.instance.transcriptStream.listen((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    LiveScreen.isActive = false;
    _pulseController.dispose();
    _transcriptSub?.cancel();
    _warningSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimer(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void _minimizeToHome() {
    if (_stopping || !mounted) return;
    Navigator.pop(context);
  }

  Future<void> _confirmBackNavigation() async {
    if (_stopping || _confirmDialogOpen) return;
    _confirmDialogOpen = true;

    try {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recording in Progress'),
          content: const Text(
            'You can minimize this screen and keep recording in the background, or finish and diarize now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'stay'),
              child: const Text('Stay'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'minimize'),
              child: const Text('Minimize'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'finish'),
              child: const Text('Finish & Diarize'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (action == 'minimize') {
        Navigator.pop(context);
      } else if (action == 'finish') {
        await _stopAndProcess();
      }
    } finally {
      _confirmDialogOpen = false;
    }
  }

  Future<void> _stopAndProcess() async {
    setState(() => _stopping = true);

    try {
      final session = await SessionManager.instance.stopRecording();
      if (!mounted) return;

      if (session != null) {
        if (SessionManager.instance.hasPendingUpload(session.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                SessionManager.instance.lastUploadError ??
                    'Audio saved on device and queued for retry.',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (ctx) => SessionDetailScreen(session: session),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process session: $e')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmBackNavigation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Recording'),
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Minimize (keep recording)',
            onPressed: _stopping ? null : _minimizeToHome,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_foregroundWarning != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.amber.withValues(alpha: 0.16),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _foregroundWarning!,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber.shade200),
                        ),
                      ),
                    ],
                  ),
                ),
              // Timer & Audio Health Banner
              StreamBuilder<RecordingAudioHealth>(
                stream: SessionManager.instance.audioHealthStream,
                initialData: SessionManager.instance.currentAudioHealth,
                builder: (context, healthSnap) {
                  final health = healthSnap.data ?? const RecordingAudioHealth();
                  final isDisconnected = !health.bleConnected;
                  final isStalled = health.stalled;

                  final Color pillColor = isDisconnected
                      ? Colors.red
                      : (isStalled
                          ? Colors.amber
                          : (health.bytesReceived > 0 ? Colors.green : theme.colorScheme.primary));
                  final IconData pillIcon = isDisconnected
                      ? Icons.bluetooth_disabled
                      : (isStalled ? Icons.warning_amber_rounded : Icons.graphic_eq);
                  final String pillText = isDisconnected
                      ? 'Omi disconnected • ${_formatBytes(health.bytesReceived)} captured'
                      : (isStalled
                          ? (health.bytesReceived == 0
                              ? 'No audio received from Omi (0 B)'
                              : 'Audio stream stalled • ${_formatBytes(health.bytesReceived)}')
                          : (health.bytesReceived > 0
                              ? 'Audio active • ${_formatBytes(health.bytesReceived)} (${health.packetCount} pkts)'
                              : 'Waiting for Omi audio...'));

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        StreamBuilder<int>(
                          stream: SessionManager.instance.durationStream,
                          initialData: SessionManager.instance.elapsedSeconds,
                          builder: (context, snapshot) {
                            return Text(
                              _formatTimer(snapshot.data ?? 0),
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                color: theme.colorScheme.primary,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final dotColor = isDisconnected ? Colors.amber : Colors.red;
                                return Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dotColor.withValues(alpha: 0.4 + (_pulseController.value * 0.6)),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Gemini 3.5 Transcribe Live',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: pillColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: pillColor.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(pillIcon, size: 14, color: pillColor),
                              const SizedBox(width: 6),
                              Text(
                                pillText,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: pillColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              // Live Transcript Stream View
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  width: double.infinity,
                  child: StreamBuilder<String>(
                    stream: SessionManager.instance.transcriptStream,
                    initialData: SessionManager.instance.liveTranscript,
                    builder: (context, snapshot) {
                      final transcript = snapshot.data ?? '';

                      if (transcript.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mic_none,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Listening via Omi device...',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Speech will appear live in real-time',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        controller: _scrollController,
                        child: Text(
                          transcript,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 18,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Stop and Diarize Button
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _stopping ? null : _stopAndProcess,
                    icon: _stopping
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.stop),
                    label: Text(
                      _stopping ? 'Diarizing with Gemini 3.5...' : 'Finish Recording & Diarize',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
