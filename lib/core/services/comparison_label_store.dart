import 'package:shared_preferences/shared_preferences.dart';

class ComparisonLabelStore {
  static Future<String?> load(String identity) async =>
      (await SharedPreferences.getInstance()).getString(
        'condition:v1:$identity',
      );
  static Future<void> save(String identity, String label) async {
    final prefs = await SharedPreferences.getInstance();
    if (label.trim().isEmpty) {
      await prefs.remove('condition:v1:$identity');
    } else {
      await prefs.setString('condition:v1:$identity', label.trim());
    }
  }
}
