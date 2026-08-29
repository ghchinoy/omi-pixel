import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/settings_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cloudRunUrlController = TextEditingController();
  String _selectedLanguage = 'en';
  bool _generateSummary = true;
  bool _testingConnection = false;
  String? _connectionStatusMessage;
  bool _connectionSuccess = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _cloudRunUrlController.text = s.cloudRunUrl;
    _selectedLanguage = s.preferredLanguage;
    _generateSummary = s.generateSummary;
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
    s.generateSummary = _generateSummary;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: Colors.green,
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
        setState(() {
          _connectionStatusMessage = 'Cloud Run service reachable!';
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
                color: AuthService.instance.isSignedIn ? Colors.green : Colors.grey,
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
                color: _connectionSuccess ? Colors.green : Colors.red,
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
            subtitle: Text('gemini-3.5-transcribe-live-preview (Global)'),
            dense: true,
          ),
          const ListTile(
            leading: Icon(Icons.people),
            title: Text('Batch Diarization Model'),
            subtitle: Text('gemini-3.5-transcribe-preview (Global)'),
            dense: true,
          ),
          const ListTile(
            leading: Icon(Icons.title),
            title: Text('Title Generation Model'),
            subtitle: Text('gemini-3.5-flash-lite (Global)'),
            dense: true,
          ),
          const ListTile(
            leading: Icon(Icons.summarize),
            title: Text('Summary Generation Model'),
            subtitle: Text('gemini-3.7-flash (Global)'),
            dense: true,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Generate AI Summary'),
            subtitle: const Text('Uses Gemini 3.7 Flash after batch diarization completes'),
            value: _generateSummary,
            onChanged: (val) => setState(() => _generateSummary = val),
            secondary: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Language & Preferences',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
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
          FilledButton.icon(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
