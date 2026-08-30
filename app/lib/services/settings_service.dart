import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const String _keyGeminiApiKey = 'gemini_api_key';
  static const String _keyCloudRunUrl = 'cloud_run_url';
  static const String _keyLiveModel = 'live_model';
  static const String _keyBatchModel = 'batch_model';
  static const String _keyLanguage = 'preferred_language';
  static const String _keyGenerateSummary = 'generate_summary';
  static const String _keyLiveTranscriptionMode = 'live_transcription_mode';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get geminiApiKey => _prefs?.getString(_keyGeminiApiKey) ?? '';
  set geminiApiKey(String value) => _prefs?.setString(_keyGeminiApiKey, value.trim());

  String get cloudRunUrl => _prefs?.getString(_keyCloudRunUrl) ?? '';
  set cloudRunUrl(String value) {
    var url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _prefs?.setString(_keyCloudRunUrl, url);
  }

  String get liveModel => _prefs?.getString(_keyLiveModel) ?? 'gemini-3.5-transcribe-live-preview';
  set liveModel(String value) => _prefs?.setString(_keyLiveModel, value.trim());

  String get batchModel => _prefs?.getString(_keyBatchModel) ?? 'gemini-3.5-transcribe-preview';
  set batchModel(String value) => _prefs?.setString(_keyBatchModel, value.trim());

  String get preferredLanguage => _prefs?.getString(_keyLanguage) ?? 'en';
  set preferredLanguage(String value) => _prefs?.setString(_keyLanguage, value.trim());

  String get liveTranscriptionMode => _prefs?.getString(_keyLiveTranscriptionMode) ?? 'verbatim';
  set liveTranscriptionMode(String value) => _prefs?.setString(_keyLiveTranscriptionMode, value.trim().toLowerCase());

  bool get generateSummary => _prefs?.getBool(_keyGenerateSummary) ?? true;
  set generateSummary(bool value) => _prefs?.setBool(_keyGenerateSummary, value);
}
