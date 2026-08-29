import 'dart:async';
import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import 'session_detail_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  StreamSubscription? _transcriptSub;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

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
    _pulseController.dispose();
    _transcriptSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimer(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _stopAndProcess() async {
    setState(() => _stopping = true);

    try {
      final session = await SessionManager.instance.stopRecording();
      if (!mounted) return;

      if (session != null) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Recording'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _stopping ? null : _stopAndProcess,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Timer & Status Banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
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
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withValues(alpha: 0.4 + (_pulseController.value * 0.6)),
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
                ],
              ),
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
    );
  }
}
