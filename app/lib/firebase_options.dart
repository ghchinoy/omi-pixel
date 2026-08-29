// Default FirebaseOptions template for Omi-Pixel.
//
// End-users can configure Firebase in either of two ways:
//   1. Run `make configure-firebase` (or `cd app && flutterfire configure`),
//      which overwrites this file with your project's platform options.
//   2. Pass `--dart-define=FIREBASE_API_KEY=...`, `--dart-define=FIREBASE_APP_ID=...`,
//      `--dart-define=FIREBASE_MESSAGING_SENDER_ID=...`, `--dart-define=FIREBASE_PROJECT_ID=...`
//      at build/run time.
//
// If neither is configured, `DefaultFirebaseOptions.currentPlatform` throws an
// UnsupportedError, and `AuthService.init()` gracefully falls back to
// offline/unauthenticated mode (`make run-local-noauth`).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _authDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const String _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static FirebaseOptions get currentPlatform {
    if (_apiKey.isEmpty || _appId.isEmpty || _projectId.isEmpty) {
      throw UnsupportedError(
        'Firebase is not configured. Run `make configure-firebase` (flutterfire configure) '
        'or pass --dart-define=FIREBASE_API_KEY=... at build time.',
      );
    }

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: _authDomain.isNotEmpty
          ? _authDomain
          : '$_projectId.firebaseapp.com',
      storageBucket: _storageBucket.isNotEmpty
          ? _storageBucket
          : '$_projectId.firebasestorage.app',
    );
  }
}
