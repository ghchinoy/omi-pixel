import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_service.dart';

class LiveTranscriptEvent {
  final String text;
  final bool isTurnComplete;
  final double timestamp;

  LiveTranscriptEvent({
    required this.text,
    this.isTurnComplete = false,
    required this.timestamp,
  });
}

class GeminiLiveService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _transcriptController = StreamController<LiveTranscriptEvent>.broadcast();
  Stream<LiveTranscriptEvent> get transcriptStream => _transcriptController.stream;

  final _connectedController = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connectedController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final List<Uint8List> _pcmBuffer = [];
  int _bufferedBytes = 0;
  static const int _minBytesToSend = 3200; // ~100ms of 16kHz 16-bit mono

  int _sentChunksCount = 0;

  Future<bool> connect({
    required String cloudRunUrl,
    String language = 'en',
    String mode = 'verbatim',
    String? sessionId,
  }) async {
    if (cloudRunUrl.isEmpty) {
      debugPrint('[GeminiLive] Missing Cloud Run URL for Live Proxy');
      return false;
    }
    await disconnect();

    var baseUrl = cloudRunUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    // Convert http(s) URL to ws(s)
    String wsUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = 'wss://${baseUrl.substring(8)}/api/live';
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = 'ws://${baseUrl.substring(7)}/api/live';
    } else {
      wsUrl = 'wss://$baseUrl/api/live';
    }

    final queryParams = <String>[];
    if (language.isNotEmpty) {
      queryParams.add('lang=$language');
    }
    if (mode.isNotEmpty) {
      queryParams.add('mode=$mode');
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      queryParams.add('session=$sessionId');
    }
    final token = await AuthService.instance.getIdToken();
    if (token != null && token.isNotEmpty) {
      queryParams.add('access_token=$token');
    }
    if (queryParams.isNotEmpty) {
      wsUrl += '?${queryParams.join('&')}';
    }

    try {
      _sentChunksCount = 0;
      debugPrint('[GeminiLive] Connecting to Cloud Run Live Proxy ($wsUrl)...');

      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 12),
      );

      await _channel!.ready;
      debugPrint('[GeminiLive] Proxy WebSocket connected. Listening for events...');

      _sub = _channel!.stream.listen(
        _handleServerMessage,
        onError: (err) {
          debugPrint('[GeminiLive] Proxy WebSocket error: $err');
          _isConnected = false;
          _connectedController.add(false);
        },
        onDone: () {
          debugPrint('[GeminiLive] Proxy WebSocket connection closed');
          _isConnected = false;
          _connectedController.add(false);
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      debugPrint('[GeminiLive] Failed to connect to proxy: $e');
      _isConnected = false;
      _connectedController.add(false);
      return false;
    }
  }

  void _handleServerMessage(dynamic message) {
    try {
      String messageStr;
      if (message is String) {
        messageStr = message;
      } else if (message is List<int>) {
        messageStr = utf8.decode(message);
      } else {
        return;
      }

      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      if (type == 'ready') {
        _isConnected = true;
        _connectedController.add(true);
        debugPrint('[GeminiLive] Live Proxy Ready (Session: ${json['sessionId']})');
        return;
      }

      if (type == 'error') {
        debugPrint('[GeminiLive] Proxy Error: ${json['error']}');
        return;
      }

      if (type == 'transcript') {
        final text = json['text'] as String?;
        final isFinal = json['isFinal'] == true;
        final ts = (json['timestamp'] as num?)?.toDouble() ?? 0.0;

        if (text != null && text.trim().isNotEmpty) {
          debugPrint('[GeminiLive] >>> [${isFinal ? "Final" : "Interim"}] "$text"');
          _transcriptController.add(LiveTranscriptEvent(
            text: text.trim(),
            isTurnComplete: isFinal,
            timestamp: ts,
          ));
        }
      }
    } catch (e) {
      debugPrint('[GeminiLive] Error parsing proxy message: $e');
    }
  }

  void sendPcmChunk(Uint8List pcmChunk) {
    if (_channel == null) return;

    _pcmBuffer.add(pcmChunk);
    _bufferedBytes += pcmChunk.length;

    if (_bufferedBytes >= _minBytesToSend) {
      final combined = Uint8List(_bufferedBytes);
      int offset = 0;
      for (final chunk in _pcmBuffer) {
        combined.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _pcmBuffer.clear();
      _bufferedBytes = 0;

      final frame = {
        'audio': base64Encode(combined),
        'mimeType': 'audio/pcm;rate=16000',
      };

      try {
        _channel!.sink.add(jsonEncode(frame));
        _sentChunksCount++;
        if (_sentChunksCount % 20 == 0) {
          debugPrint('[GeminiLive] Streamed $_sentChunksCount audio chunks to proxy');
        }
      } catch (e) {
        debugPrint('[GeminiLive] Failed to send media chunk: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _connectedController.add(false);
    _pcmBuffer.clear();
    _bufferedBytes = 0;
    _sentChunksCount = 0;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
