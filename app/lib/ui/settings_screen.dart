import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../theme/lustrous_theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  static const String appVersion = '0.4.1+9';

  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cloudRunUrlController = TextEditingController();
  String _selectedLanguage = 'en';
  String _selectedLiveMode = 'verbatim';
  String _selectedSummaryModel = SettingsService.defaultSummaryModel;
  String _selectedThemeMode = 'system';
  bool _generateSummary = true;
  bool _testingConnection = false;
  String? _connectionStatusMessage;
  bool _connectionSuccess = false;
  String? _backendVersion;
  bool? _ignoringBatteryOptimizations;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _cloudRunUrlController.text = s.cloudRunUrl;
    _selectedLanguage = s.preferredLanguage;
    _selectedLiveMode = s.liveTranscriptionMode;
    _selectedSummaryModel = s.summaryModel;
    _selectedThemeMode = s.themeModePreference;
    _generateSummary = s.generateSummary;
    if (s.cloudRunUrl.isNotEmpty) {
      _fetchBackendVersion(s.cloudRunUrl);
    }
    _checkBatteryOptimizationStatus();
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final ignoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (mounted) {
        setState(() => _ignoringBatteryOptimizations = ignoring);
      }
    } catch (_) {}
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      await _checkBatteryOptimizationStatus();
    } catch (_) {}
  }

  Future<void> _fetchBackendVersion(String baseUrl) async {
    try {
      var endpoint = baseUrl.trim();
      while (endpoint.endsWith('/')) {
        endpoint = endpoint.substring(0, endpoint.length - 1);
      }
      final resp = await http.get(Uri.parse('$endpoint/api/health')).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final ver = data['version'] as String?;
        if (ver != null && ver.isNotEmpty) {
          setState(() {
            _backendVersion = ver;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _cloudRunUrlController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final s = SettingsService.instance;
    s.cloudRunUrl = _cloudRunUrlController.text;
    s.preferredLanguage = _selectedLanguage;
    s.liveTranscriptionMode = _selectedLiveMode;
    s.summaryModel = _selectedSummaryModel;
    s.themeModePreference = _selectedThemeMode;
    s.generateSummary = _generateSummary;

    final lustrous = LustrousColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved successfully'),
        backgroundColor: lustrous.positive,
      ),
    );
  }

  Future<void> _testCloudRun() async {
    final urlStr = _cloudRunUrlController.text.trim();
    if (urlStr.isEmpty) {
      setState(() {
        _connectionStatusMessage = 'Please enter a Cloud Run URL';
        _connectionSuccess = false;
      });
      return;
    }

    setState(() {
      _testingConnection = true;
      _connectionStatusMessage = null;
    });

    try {
      var endpoint = urlStr;
      while (endpoint.endsWith('/')) {
        endpoint = endpoint.substring(0, endpoint.length - 1);
      }
      final resp = await http.get(Uri.parse('$endpoint/api/health')).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        String? ver;
        try {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          ver = data['version'] as String?;
        } catch (_) {}
        setState(() {
          _backendVersion = ver ?? _backendVersion;
          _connectionStatusMessage = ver != null
              ? 'Cloud Run service reachable! (v$ver)'
              : 'Cloud Run service reachable!';
          _connectionSuccess = true;
        });
      } else {
        setState(() {
          _connectionStatusMessage = 'Service returned HTTP ${resp.statusCode}';
          _connectionSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatusMessage = 'Connection failed: $e';
        _connectionSuccess = false;
      });
    } finally {
      setState(() {
        _testingConnection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lustrous = LustrousColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'Google Account & Authentication',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                AuthService.instance.isSignedIn ? Icons.account_circle : Icons.no_accounts,
                color: AuthService.instance.isSignedIn
                    ? lustrous.positive
                    : theme.colorScheme.onSurfaceVariant,
                size: 36,
              ),
              title: Text(
                AuthService.instance.currentUser?.displayName ??
                    (AuthService.instance.isSignedIn ? 'Signed In' : 'Not signed in'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                AuthService.instance.currentUser?.email ?? 'Sign in to access authorized Cloud Run endpoints',
              ),
              trailing: AuthService.instance.isSignedIn
                  ? OutlinedButton(
                      onPressed: () async {
                        await AuthService.instance.signOut();
                        setState(() {});
                      },
                      child: const Text('Sign Out'),
                    )
                  : FilledButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                        setState(() {});
                      },
                      child: const Text('Sign In'),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Cloud Run Backend Service',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cloudRunUrlController,
            decoration: const InputDecoration(
              labelText: 'Cloud Run Service URL',
              hintText: 'https://omi-pixel-service-xyz.a.run.app',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud),
              helperText: 'Proxies Gemini 3.5 Live WS & executes batch diarization',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _testingConnection ? null : _testCloudRun,
                icon: _testingConnection
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: const Text('Test Connection'),
              ),
            ],
          ),
          if (_connectionStatusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _connectionStatusMessage!,
              style: TextStyle(
                color: _connectionSuccess ? lustrous.positive : lustrous.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Google Gemini Models (Vertex AI)',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.stream),
            title: Text('Live Streaming Model'),
            subtitle: Text('gemini-3.5-transcribe-live (Global)'),
            dense: true,
          ),
          const ListTile(
            leading: Icon(Icons.people),
            title: Text('Batch Diarization Model'),
            subtitle: Text('gemini-3.5-transcribe (Global)'),
            dense: true,
          ),
          const ListTile(
            leading: Icon(Icons.title),
            title: Text('Title Generation Model'),
            subtitle: Text('gemini-3.5-flash-lite (Global)'),
            dense: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedSummaryModel,
            decoration: const InputDecoration(
              labelText: 'Summary Generation Model',
              helperText: 'Used on Vertex AI (Global) when AI Summary is enabled',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.summarize),
            ),
            items: const [
              DropdownMenuItem(
                value: 'gemini-4-hydrogen',
                child: Text('Gemini 4 Hydrogen (Default)'),
              ),
              DropdownMenuItem(
                value: 'gemini-3.8-flash',
                child: Text('Gemini 3.8 Flash (Faster)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedSummaryModel = val);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Generate AI Summary'),
            subtitle: Text('Uses $_selectedSummaryModel after batch diarization completes'),
            value: _generateSummary,
            onChanged: (val) => setState(() => _generateSummary = val),
            secondary: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Appearance & Preferences',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.contrast)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {_selectedThemeMode},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              final mode = selection.first;
              setState(() => _selectedThemeMode = mode);
              SettingsService.instance.themeModePreference = mode;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedLiveMode,
            decoration: const InputDecoration(
              labelText: 'Live Transcription Mode',
              helperText: 'Smart mode removes disfluencies and applies inline verbal self-corrections (or long-press Start Conversation)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tune),
            ),
            items: const [
              DropdownMenuItem(
                value: 'verbatim',
                child: Text('Verbatim (Exact audio transcription)'),
              ),
              DropdownMenuItem(
                value: 'smart',
                child: Text('Smart (Inline self-corrections & cleaned disfluencies)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedLiveMode = val);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedLanguage,
            decoration: const InputDecoration(
              labelText: 'Spoken Language',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.language),
            ),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English (en)')),
              DropdownMenuItem(value: 'es', child: Text('Spanish (es)')),
              DropdownMenuItem(value: 'fr', child: Text('French (fr)')),
              DropdownMenuItem(value: 'de', child: Text('German (de)')),
              DropdownMenuItem(value: 'ja', child: Text('Japanese (ja)')),
              DropdownMenuItem(value: 'zh', child: Text('Chinese (zh)')),
              DropdownMenuItem(value: 'multi', child: Text('Auto-detect (multi)')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedLanguage = val);
            },
          ),
          const SizedBox(height: 32),
          if (Platform.isAndroid && _ignoringBatteryOptimizations != null) ...[
            Text(
              'Background Recording Reliability',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: _ignoringBatteryOptimizations!
                  ? lustrous.positiveContainer.withValues(alpha: 0.45)
                  : lustrous.warningContainer.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _ignoringBatteryOptimizations!
                      ? lustrous.positive.withValues(alpha: 0.45)
                      : lustrous.warning.withValues(alpha: 0.5),
                ),
              ),
              child: ListTile(
                leading: Icon(
                  _ignoringBatteryOptimizations! ? Icons.battery_saver : Icons.battery_alert,
                  color: _ignoringBatteryOptimizations! ? lustrous.positive : lustrous.warning,
                ),
                title: Text(
                  _ignoringBatteryOptimizations!
                      ? 'Unrestricted Background Battery'
                      : 'Battery Optimization Restricted',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _ignoringBatteryOptimizations!
                      ? 'Android will not throttle Omi-Pixel during long background recordings.'
                      : 'Pixel may pause long recordings while locked. Allow unrestricted battery usage for reliable capture.',
                ),
                trailing: _ignoringBatteryOptimizations!
                    ? null
                    : TextButton(
                        onPressed: _requestBatteryOptimizationExemption,
                        child: const Text('Allow'),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          FilledButton.icon(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Settings'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Omi Pixel Version'),
            subtitle: Text(
              _backendVersion != null
                  ? 'App v${SettingsScreen.appVersion} • Backend v$_backendVersion'
                  : 'App v${SettingsScreen.appVersion}',
            ),
            dense: true,
          ),
        ],
      ),
    );
  }
}
