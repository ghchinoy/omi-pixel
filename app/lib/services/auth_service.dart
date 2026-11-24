import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const String _keyRuntimeFirebaseConfig = 'runtime_firebase_config';

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;
  bool _usedRuntimeConfig = false;
  bool get usedRuntimeConfig => _usedRuntimeConfig;
  bool _googleSignInInitialized = false;

  FirebaseAuth? get _auth {
    if (!_isAvailable) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _auth?.currentUser;
  bool get isSignedIn => _auth?.currentUser != null;

  Stream<User?> get authStateChanges {
    final a = _auth;
    if (a == null) {
      return Stream<User?>.value(null);
    }
    return a.authStateChanges();
  }

  /// Parses public Firebase client options returned by `GET /api/client-config`.
  @visibleForTesting
  static FirebaseOptions? parseClientConfigJson(Map<String, dynamic> json) {
    if (json['auth_disabled'] == true) return null;
    final apiKey = (json['api_key'] as String? ?? '').trim();
    final appId = (json['app_id'] as String? ?? '').trim();
    final messagingSenderId = (json['messaging_sender_id'] as String? ?? '').trim();
    final projectId = (json['project_id'] as String? ?? '').trim();
    if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
      return null;
    }
    final authDomain = (json['auth_domain'] as String? ?? '').trim();
    final storageBucket = (json['storage_bucket'] as String? ?? '').trim();
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isNotEmpty ? authDomain : '$projectId.firebaseapp.com',
      storageBucket: storageBucket.isNotEmpty ? storageBucket : '$projectId.firebasestorage.app',
    );
  }

  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          _usedRuntimeConfig = false;
        } on UnsupportedError {
          // Universal pre-built APK path: restore persisted runtime Firebase config
          final saved = await _loadRuntimeFirebaseOptions();
          if (saved == null) rethrow;
          await Firebase.initializeApp(options: saved);
          _usedRuntimeConfig = true;
        }
      }
      _isAvailable = true;
      debugPrint(
        '[AuthService] Firebase Auth initialized (runtime=$_usedRuntimeConfig). '
        'Signed-in user: ${currentUser?.email ?? "none"}',
      );
    } catch (e) {
      _isAvailable = false;
      debugPrint('[AuthService] Firebase not configured on device ($e). Running in offline/unauthenticated mode.');
    }
  }

  Future<FirebaseOptions?> _loadRuntimeFirebaseOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRuntimeFirebaseConfig);
      if (raw == null || raw.isEmpty) return null;
      return parseClientConfigJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[AuthService] Failed loading persisted runtime Firebase config: $e');
      return null;
    }
  }

  /// Fetches public Firebase config from `<cloudRunUrl>/api/client-config`, persists it,
  /// and initializes Firebase at runtime so universal pre-built APKs work against any
  /// self-hosted Cloud Run backend without baked `google-services.json`.
  Future<bool> configureFromBackend(
    String cloudRunUrl, {
    Future<http.Response> Function(Uri uri)? httpGet,
    Future<void> Function(FirebaseOptions options)? initializeFirebase,
  }) async {
    var base = cloudRunUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.isEmpty) return false;

    try {
      final uri = Uri.parse('$base/api/client-config');
      final resp = await (httpGet ?? (u) => http.get(u).timeout(const Duration(seconds: 6)))(uri);
      if (resp.statusCode != 200) {
        debugPrint('[AuthService] GET /api/client-config failed: HTTP ${resp.statusCode}');
        return false;
      }

      final payload = jsonDecode(resp.body) as Map<String, dynamic>;
      final options = parseClientConfigJson(payload);
      if (options == null) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRuntimeFirebaseConfig, jsonEncode(payload));

      if (initializeFirebase != null) {
        await initializeFirebase(options);
      } else if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      _isAvailable = true;
      _usedRuntimeConfig = true;
      debugPrint('[AuthService] Configured Firebase at runtime for project ${options.projectId}');
      return true;
    } catch (e) {
      debugPrint('[AuthService] Runtime Firebase bootstrap failed: $e');
      return false;
    }
  }

  /// Obtains a valid Firebase ID Token (JWT) to attach to Cloud Run API requests.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('[AuthService] Error fetching ID token: $e');
      return null;
    }
  }

  /// Triggers Google Sign-In on Android/iOS.
  ///
  /// Uses native `GoogleSignIn` when configured with `google-services.json`, and
  /// falls back to `FirebaseAuth.signInWithProvider(GoogleAuthProvider())`
  /// (Chrome Custom Tab via Firebase Authorized Domains) on universal pre-built APKs
  /// where Android SHA-1 is not registered in the user's Firebase project.
  Future<UserCredential?> signInWithGoogle() async {
    if (!_isAvailable) {
      throw Exception(
        'Firebase is not configured yet. Enter your Cloud Run URL in Settings and tap Test Connection, or run make configure-firebase.',
      );
    }

    final a = _auth;
    if (a == null) {
      throw Exception('FirebaseAuth instance unavailable');
    }

    // Universal runtime-configured APK path: browser OAuth via Firebase Authorized Domains
    // requires zero Android SHA-1 registration in the user's Firebase project.
    if (_usedRuntimeConfig) {
      try {
        final provider = GoogleAuthProvider();
        final cred = await a.signInWithProvider(provider);
        debugPrint('[AuthService] Signed in via OAuth provider: ${cred.user?.email}');
        return cred;
      } catch (e) {
        debugPrint('[AuthService] Browser OAuth Sign-In failed: $e');
        rethrow;
      }
    }

    try {
      final googleSignIn = GoogleSignIn.instance;
      if (!_googleSignInInitialized) {
        await googleSignIn.initialize();
        _googleSignInInitialized = true;
      }

      final GoogleSignInAccount googleUser;
      try {
        googleUser = await googleSignIn.authenticate();
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          return null;
        }
        if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
          debugPrint('[AuthService] Native GoogleSignIn config error; falling back to browser OAuth provider.');
          return await a.signInWithProvider(GoogleAuthProvider());
        }
        rethrow;
      }

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await a.signInWithCredential(credential);
      debugPrint('[AuthService] Successfully signed in: ${userCredential.user?.email}');
      return userCredential;
    } catch (e) {
      debugPrint('[AuthService] Google Sign-In failed: $e');
      rethrow;
    }
  }

  /// Signs out of Firebase and Google.
  Future<void> signOut() async {
    try {
      if (_googleSignInInitialized) {
        await GoogleSignIn.instance.signOut();
      }
      await _auth?.signOut();
      debugPrint('[AuthService] User signed out');
    } catch (e) {
      debugPrint('[AuthService] Sign-out error: $e');
    }
  }
}
