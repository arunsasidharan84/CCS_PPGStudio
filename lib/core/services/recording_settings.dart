import 'package:shared_preferences/shared_preferences.dart';

class RecordingSettings {
  static const defaultPattern = '*_ppg_data.csv';
  static const defaultPipelineMode = 'standard';

  static Future<String> pattern() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('sensioFilePattern') ?? defaultPattern;
    } catch (_) {
      return defaultPattern;
    }
  }

  static Future<void> savePattern(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sensioFilePattern', value.trim());
    } catch (_) {}
  }

  static Future<String> pipelineMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('ppgPipelineMode') ?? defaultPipelineMode;
    } catch (_) {
      return defaultPipelineMode;
    }
  }

  static Future<void> savePipelineMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ppgPipelineMode', mode.trim());
    } catch (_) {}
  }
}
