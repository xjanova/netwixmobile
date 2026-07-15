import 'package:shared_preferences/shared_preferences.dart';

/// Per-device bookkeeping for pre-roll ad [PrerollAd.frequency].
///
/// This used to be a rotating-banner client pointed at
/// `main.thaiprompt.online/api/ads` — a different host whose endpoint was never
/// built, so every admin-configured AdCampaign silently never reached mobile and
/// in-app ad revenue was zero. Ads now come from NetWix itself via
/// `NetwixApi.fetchPreroll()`, which mirrors the web player exactly.
///
/// Everything that decides WHETHER an ad may show — targeting, schedule window,
/// hide_for_pro — is resolved server-side. The only thing the client owns is
/// frequency, because "once per session" and "once per day" are per-device facts
/// the server can't know.
class AdFrequency {
  AdFrequency._(this._prefs);

  final SharedPreferences _prefs;

  /// Campaign ids already shown in THIS app run (frequency: session).
  static final Set<int> _seenThisSession = {};

  static Future<AdFrequency> load() async =>
      AdFrequency._(await SharedPreferences.getInstance());

  static String _dailyKey(int id) => 'ad_seen_daily_$id';

  /// Whether [frequency] permits showing campaign [id] right now.
  bool mayShow(int id, String frequency) {
    switch (frequency) {
      case 'session':
        return !_seenThisSession.contains(id);
      case 'daily':
        final last = _prefs.getString(_dailyKey(id));
        return last != _today();
      default: // 'always'
        return true;
    }
  }

  /// Record that campaign [id] was shown, so the frequency rule can hold.
  Future<void> markShown(int id, String frequency) async {
    _seenThisSession.add(id);
    if (frequency == 'daily') {
      await _prefs.setString(_dailyKey(id), _today());
    }
  }

  /// Local calendar day. Deliberately date-only: "once daily" should roll over at
  /// the viewer's midnight, not 24h after the last impression.
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Test seam — session state is static and would otherwise leak between tests.
  static void resetSessionForTest() => _seenThisSession.clear();
}
