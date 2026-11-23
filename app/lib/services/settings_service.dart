import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const String _keyCloudRunUrl = 'cloud_run_url';
  static const String _keyLiveModel = 'live_model';
  static const String _keyBatchModel = 'batch_model';
  static const String _keySummaryModel = 'summary_model';
  static const String _keyLanguage = 'preferred_language';
  static const String _keyGenerateSummary = 'generate_summary';
  static const String _keyLiveTranscriptionMode = 'live_transcription_mode';
  static const String _keyThemeMode = 'theme_mode';

  static const String defaultSummaryModel = 'gemini-4-hydrogen';
  static const List<String> supportedSummaryModels = [
    'gemini-4-hydrogen',
    'gemini-3.8-flash',
  ];

  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    themeModeNotifier.value = _parseThemeMode(themeModePreference);
  }

  static ThemeMode _parseThemeMode(String pref) {
    switch (pref) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String get themeModePreference => _prefs?.getString(_keyThemeMode) ?? 'system';
  set themeModePreference(String value) {
    final normalized = (value == 'light' || value == 'dark') ? value : 'system';
    _prefs?.setString(_keyThemeMode, normalized);
    themeModeNotifier.value = _parseThemeMode(normalized);
  }

  String get cloudRunUrl => _prefs?.getString(_keyCloudRunUrl) ?? '';
  set cloudRunUrl(String value) {
    var url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _prefs?.setString(_keyCloudRunUrl, url);
  }

  String get liveModel => _prefs?.getString(_keyLiveModel) ?? 'gemini-3.5-transcribe-live';
  set liveModel(String value) => _prefs?.setString(_keyLiveModel, value.trim());

  String get batchModel => _prefs?.getString(_keyBatchModel) ?? 'gemini-3.5-transcribe';
  set batchModel(String value) => _prefs?.setString(_keyBatchModel, value.trim());

  String get summaryModel {
    final stored = _prefs?.getString(_keySummaryModel);
    if (stored != null && supportedSummaryModels.contains(stored)) {
      return stored;
    }
    return defaultSummaryModel;
  }

  set summaryModel(String value) {
    final clean = value.trim();
    _prefs?.setString(
      _keySummaryModel,
      supportedSummaryModels.contains(clean) ? clean : defaultSummaryModel,
    );
  }

  String get preferredLanguage => _prefs?.getString(_keyLanguage) ?? 'en';
  set preferredLanguage(String value) => _prefs?.setString(_keyLanguage, value.trim());

  String get liveTranscriptionMode => _prefs?.getString(_keyLiveTranscriptionMode) ?? 'verbatim';
  set liveTranscriptionMode(String value) => _prefs?.setString(_keyLiveTranscriptionMode, value.trim().toLowerCase());

  bool get generateSummary => _prefs?.getBool(_keyGenerateSummary) ?? true;
  set generateSummary(bool value) => _prefs?.setBool(_keyGenerateSummary, value);
}
