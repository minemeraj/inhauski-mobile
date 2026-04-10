import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'inhauski_locale';

/// LocaleService holds the user's chosen locale and persists it across
/// restarts.  Expose it as a ChangeNotifier so MaterialApp.locale
/// rebuilds whenever the user switches language.
///
/// Priority order:
///   1. User manual override (stored in SharedPreferences)
///   2. Device system locale (Flutter default — null override)
class LocaleService extends ChangeNotifier {
  Locale? _locale; // null → follow system locale

  Locale? get locale => _locale;

  LocaleService() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code != null) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  /// Set and persist the locale.  Pass [null] to revert to system locale.
  Future<void> setLocale(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_kLocaleKey);
      _locale = null;
    } else {
      await prefs.setString(_kLocaleKey, languageCode);
      _locale = Locale(languageCode);
    }
    notifyListeners();
  }
}
