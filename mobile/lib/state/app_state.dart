import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../services/settings_store.dart';

/// Global UI state: language, onboarding.
///
/// Pro deliberately does NOT live here. It is a paid entitlement, so it is read
/// from MemberState, which mirrors the server's `pro_until`. See
/// [SettingsStore.clearLegacyProFlag].
class AppState extends ChangeNotifier {
  AppState(this.settings);
  final SettingsStore settings;

  AppLang get lang => settings.language;
  L10n get l => L10n(lang);
  bool get onboarded => settings.onboarded;
  bool get autoSkipIntro => settings.autoSkipIntro;

  Future<void> setAutoSkipIntro(bool v) async {
    await settings.setAutoSkipIntro(v);
    notifyListeners();
  }

  Future<void> setLang(AppLang v) async {
    await settings.setLanguage(v);
    notifyListeners();
  }

  Future<void> toggleLang() => setLang(lang == AppLang.th ? AppLang.en : AppLang.th);

  Future<void> completeOnboarding() async {
    await settings.setOnboarded(true);
    notifyListeners();
  }
}
