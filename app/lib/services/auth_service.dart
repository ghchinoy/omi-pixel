import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

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

  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _isAvailable = true;
      debugPrint('[AuthService] Firebase Auth initialized. Signed-in user: ${currentUser?.email ?? "none"}');
    } catch (e) {
      _isAvailable = false;
      debugPrint('[AuthService] Firebase not configured on device ($e). Running in offline/unauthenticated mode.');
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

  /// Triggers standard Google Sign-In on Android/iOS.
  Future<UserCredential?> signInWithGoogle() async {
    if (!_isAvailable) {
      throw Exception('Firebase is not configured on this device yet. Run flutterfire configure to set up authentication.');
    }

    try {
      final googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in dialog
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final a = _auth;
      if (a == null) {
        throw Exception('FirebaseAuth instance unavailable');
      }

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
      await GoogleSignIn().signOut();
      await _auth?.signOut();
      debugPrint('[AuthService] User signed out');
    } catch (e) {
      debugPrint('[AuthService] Sign-out error: $e');
    }
  }
}
