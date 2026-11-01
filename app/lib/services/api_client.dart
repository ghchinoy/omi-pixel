import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/segment.dart';
import '../models/session.dart';
import 'auth_service.dart';
import 'settings_service.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String get _baseUrl => SettingsService.instance.cloudRunUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<Map<String, String>> _authHeaders([Map<String, String>? extra]) async {
    final headers = <String, String>{};
    if (extra != null) {
      headers.addAll(extra);
    }
    final token = await AuthService.instance.getIdToken();
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
    if (!isConfigured) return null;

    final shouldSummarize = summary ?? SettingsService.instance.generateSummary;
    try {
      final url = Uri.parse('$_baseUrl/api/sessions/$sessionId/audio?summary=$shouldSummarize');
      final req = http.MultipartRequest('POST', url);
      final authHeaders = await _authHeaders();
      req.headers.addAll(authHeaders);

      req.files.add(http.MultipartFile.fromBytes(
        'audio',
        wavBytes,
        filename: 'session_$sessionId.wav',
      ));

      final streamedResp = await req.send().timeout(const Duration(minutes: 3));
      final resp = await http.Response.fromStream(streamedResp);

      if (resp.statusCode == 200) {
        return Session.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      debugPrint('[ApiClient] uploadAudio failed: HTTP ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      debugPrint('[ApiClient] uploadAudio error: $e');
      return null;
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

  Future<bool> saveSegments(String sessionId, List<Segment> segments, {String title = '', String summary = ''}) async {
    if (!isConfigured) return false;

    try {
      final url = Uri.parse('$_baseUrl/api/sessions/$sessionId/segments');
      final headers = await _authHeaders({'Content-Type': 'application/json'});
      final resp = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'title': title,
          'summary': summary,
          'segments': segments.map((s) => s.toJson()).toList(),
        }),
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
}
