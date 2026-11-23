import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'services/settings_service.dart';
import 'ui/home_screen.dart';
import 'ui/live_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await AuthService.instance.init();
  await SettingsService.instance.init();
  await SessionManager.instance.init();

  FlutterForegroundTask.addTaskDataCallback((Object data) {
    if (data == 'open_live_recording' &&
        SessionManager.instance.isRecording &&
        !LiveScreen.isActive) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const LiveScreen()),
      );
    }
  });

  runApp(const OmiPixelApp());
}

class OmiPixelApp extends StatelessWidget {
  const OmiPixelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Omi Pixel',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8), // Electric Blue
          brightness: Brightness.dark,
          surface: const Color(0xFF0F172A),  // Deep Slate
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      routes: {
        '/live': (_) => const LiveScreen(),
      },
      home: const HomeScreen(),
    );
  }
}
