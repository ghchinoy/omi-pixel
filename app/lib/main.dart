import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'services/settings_service.dart';
import 'theme/lustrous_theme.dart';
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

  SessionManager.instance.hardwareButtonActionStream.listen((action) {
    if (action == 'started' &&
        SessionManager.instance.isRecording &&
        !LiveScreen.isActive &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const LiveScreen()),
      );
    } else if (action == 'stopped' && LiveScreen.isActive) {
      appNavigatorKey.currentState?.pop();
    }
  });

  runApp(const OmiPixelApp());
}

class OmiPixelApp extends StatelessWidget {
  const OmiPixelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService.instance.themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Omi Pixel',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: LustrousTheme.light(),
          darkTheme: LustrousTheme.dark(),
          routes: {
            '/live': (_) => const LiveScreen(),
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
