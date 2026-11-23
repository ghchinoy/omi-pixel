import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/segment.dart';
import '../models/session.dart';
import 'auth_service.dart';
import 'settings_service.dart';

/// Result of uploading session WAV audio to Cloud Run for diarization.
class AudioUploadResult {
  final Session? session;
  final int? statusCode;
  final String? error;

  const AudioUploadResult({
    this.session,
    this.statusCode,
    this.error,
  });

  bool get isSuccess => session != null;
}

class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String get _baseUrl => SettingsService.instance.cloudRunUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<Map<String, String>> _authHeaders([
    Map<String, String>? extra,
    bool forceRefresh = false,
  ]) async {
    final headers = <String, String>{};
    if (extra != null) {
      headers.addAll(extra);
    }
    final token = await AuthService.instance.getIdToken(forceRefresh: forceRefresh);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Session?> createSession(Session session) async {
    if (!isConfigured) return null;

    try {
      final url = Uri.parse('$_baseUrl/api/sessions');
      final headers = await _authHeaders({'Content-Type': 'application/json'});
      final resp = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'id': session.id,
          'device_id': session.deviceId,
          'title': session.title,
          'language': session.language,
          'started_at': session.startedAt.toUtc().toIso8601String(),
        }),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return Session.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      debugPrint('[ApiClient] createSession failed: HTTP ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      debugPrint('[ApiClient] createSession error: $e');
      return null;
    }
  }

  Future<Session?> uploadAudio(String sessionId, Uint8List wavBytes, {bool? summary}) async {
    final result = await uploadAudioDetailed(sessionId, wavBytes: wavBytes, summary: summary);
    return result.session;
  }

  Future<AudioUploadResult> uploadAudioFile(String sessionId, File wavFile, {bool? summary}) {
    return uploadAudioDetailed(sessionId, wavFile: wavFile, summary: summary);
  }

  /// Uploads WAV audio (from [wavFile] or [wavBytes]) to `POST /api/sessions/{id}/audio`.
  ///
  /// Retries once with `forceRefresh: true` on HTTP 401 so expired Firebase ID
  /// tokens do not cause audio loss after long recordings.
  @visibleForTesting
  Future<AudioUploadResult> uploadAudioDetailed(
    String sessionId, {
    File? wavFile,
    Uint8List? wavBytes,
    bool? summary,
    String? summaryModel,
    String? baseUrlOverride,
    Future<String?> Function({bool forceRefresh})? tokenProvider,
    Future<http.Response> Function(http.MultipartRequest req)? sendRequest,
  }) async {
    final baseUrl = baseUrlOverride ?? _baseUrl;
    if (baseUrl.isEmpty) {
      return const AudioUploadResult(error: 'Cloud Run URL is not configured.');
    }
    if (wavFile == null && wavBytes == null) {
      return const AudioUploadResult(error: 'No WAV audio provided for upload.');
    }

    final shouldSummarize = summary ?? SettingsService.instance.generateSummary;
    final selectedSummaryModel = summaryModel ?? SettingsService.instance.summaryModel;
    final url = Uri.parse(
      '$baseUrl/api/sessions/$sessionId/audio?summary=$shouldSummarize&summary_model=${Uri.encodeQueryComponent(selectedSummaryModel)}',
    );
    final getToken = tokenProvider ?? ({bool forceRefresh = false}) => AuthService.instance.getIdToken(forceRefresh: forceRefresh);
    final doSend = sendRequest ??
        (http.MultipartRequest req) async {
          final streamedResp = await req.send().timeout(const Duration(minutes: 3));
          return http.Response.fromStream(streamedResp);
        };

    Future<http.Response> attempt({required bool forceRefresh}) async {
      final req = http.MultipartRequest('POST', url);
      final token = await getToken(forceRefresh: forceRefresh);
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      if (wavFile != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'audio',
          wavFile.path,
          filename: 'session_$sessionId.wav',
        ));
      } else {
        req.files.add(http.MultipartFile.fromBytes(
          'audio',
          wavBytes!,
          filename: 'session_$sessionId.wav',
        ));
      }
      return doSend(req);
    }

    try {
      var resp = await attempt(forceRefresh: false);
      if (resp.statusCode == 401) {
        debugPrint('[ApiClient] uploadAudio($sessionId) returned 401; refreshing Firebase token and retrying once.');
        resp = await attempt(forceRefresh: true);
      }

      if (resp.statusCode == 200 || resp.statusCode == 202) {
        final session = Session.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        return AudioUploadResult(session: session, statusCode: resp.statusCode);
      }

      final bodyPreview = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
      final errMsg = 'Upload failed (HTTP ${resp.statusCode}): $bodyPreview';
      debugPrint('[ApiClient] uploadAudio($sessionId): $errMsg');
      return AudioUploadResult(statusCode: resp.statusCode, error: errMsg);
    } catch (e) {
      final errMsg = 'Upload error: $e';
      debugPrint('[ApiClient] uploadAudio($sessionId): $errMsg');
      return AudioUploadResult(error: errMsg);
    }
  }

  Future<List<Session>> listSessions() async {
    if (!isConfigured) return [];

    try {
      final url = Uri.parse('$_baseUrl/api/sessions');
      final headers = await _authHeaders();
      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
      }
      debugPrint('[ApiClient] listSessions failed: HTTP ${resp.statusCode} ${resp.body}');
      return [];
    } catch (e) {
      debugPrint('[ApiClient] listSessions error: $e');
      return [];
    }
  }

  Future<Session?> getSession(String sessionId) async {
    if (!isConfigured) return null;

    try {
      final url = Uri.parse('$_baseUrl/api/sessions/$sessionId');
      final headers = await _authHeaders();
      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        return Session.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      debugPrint('[ApiClient] getSession($sessionId) failed: HTTP ${resp.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[ApiClient] getSession($sessionId) error: $e');
      return null;
    }
  }

  Future<bool> saveSegments(
    String sessionId,
    List<Segment> segments, {
    String title = '',
    String summary = '',
    String? status,
  }) async {
    if (!isConfigured) return false;

    try {
      final url = Uri.parse('$_baseUrl/api/sessions/$sessionId/segments');
      final headers = await _authHeaders({'Content-Type': 'application/json'});
      final payload = <String, dynamic>{
        'title': title,
        'summary': summary,
        'segments': segments.map((s) => s.toJson()).toList(),
      };
      if (status != null && status.isNotEmpty) {
        payload['status'] = status;
      }
      final resp = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (resp.statusCode != 200) {
        debugPrint('[ApiClient] saveSegments failed: HTTP ${resp.statusCode}');
      }
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiClient] saveSegments error: $e');
      return false;
    }
  }

  /// Requests backend reprocessing of an already-stored session WAV in GCS.
  Future<AudioUploadResult> reprocessSession(
    String sessionId, {
    bool? summary,
    String? summaryModel,
  }) async {
    if (!isConfigured) {
      return const AudioUploadResult(error: 'Cloud Run URL is not configured.');
    }
    final shouldSummarize = summary ?? SettingsService.instance.generateSummary;
    final selectedSummaryModel = summaryModel ?? SettingsService.instance.summaryModel;
    try {
      final url = Uri.parse(
        '$_baseUrl/api/sessions/$sessionId/reprocess?summary=$shouldSummarize&summary_model=${Uri.encodeQueryComponent(selectedSummaryModel)}',
      );
      var headers = await _authHeaders();
      var resp = await http.post(url, headers: headers).timeout(const Duration(minutes: 3));
      if (resp.statusCode == 401) {
        headers = await _authHeaders(null, true);
        resp = await http.post(url, headers: headers).timeout(const Duration(minutes: 3));
      }
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        return AudioUploadResult(
          session: Session.fromJson(jsonDecode(resp.body) as Map<String, dynamic>),
          statusCode: resp.statusCode,
        );
      }
      return AudioUploadResult(
        statusCode: resp.statusCode,
        error: 'Reprocess failed (HTTP ${resp.statusCode})',
      );
    } catch (e) {
      return AudioUploadResult(error: 'Reprocess error: $e');
    }
  }
}
