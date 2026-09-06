import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';

/// Local-first persistence for the account layer (member, coin balance, unlocked
/// episodes, daily-activity counters). Authoritative until netwix.online is live;
/// afterwards the server reconciles.
///
/// The member record lives in SharedPreferences — a plaintext XML file — but the BEARER TOKEN does
/// not: it is the account, and it now sits in the platform keystore instead (EncryptedSharedPrefs
/// on Android, Keychain on iOS). An install that predates this moves its token across on first
/// launch and the plaintext copy is rewritten without it.
///
/// If the keystore is unusable — and on a few Android OEMs it genuinely is — the token stays where
/// it has always been rather than the member being locked out of their own account. Better storage
/// is worth having; it is not worth a sign-in that fails on somebody's phone and nowhere else.
class AccountStore {
  AccountStore._(this._p, this._secure, this._token, this._secureOk);
  final SharedPreferences _p;
  final FlutterSecureStorage _secure;
  final bool _secureOk;
  String? _token;

  static const _kToken = 'app_token';

  static Future<AccountStore> load() async {
    final p = await SharedPreferences.getInstance();
    // Defaults are what we want on both platforms: Android wraps an AES-GCM data key with an
    // RSA key held in the hardware KeyStore (API 23+; we ship 24+), iOS uses the Keychain.
    const secure = FlutterSecureStorage();

    String? token;
    var ok = true;
    try {
      token = await secure.read(key: _kToken);
    } catch (_) {
      ok = false;
    }

    final store = AccountStore._(p, secure, token, ok);
    if (ok) await store._adoptLegacyToken();

    return store;
  }

  /// One-time move: an existing install has its token inside the `member` JSON in prefs. Copy it
  /// into the keystore and rewrite the plaintext record without it. Only ever runs while the
  /// keystore works, so a failed write can never leave the device with no token at all.
  Future<void> _adoptLegacyToken() async {
    final legacy = Member.decode(_p.getString(_kMember));
    final legacyToken = legacy?.token;
    if (legacy == null || legacyToken == null || legacyToken.isEmpty) return;

    try {
      _token ??= legacyToken;
      await _secure.write(key: _kToken, value: _token);
    } catch (_) {
      return; // keep the plaintext copy — it is still the only one that works
    }
    await _p.setString(_kMember, legacy.withoutToken().encode());
  }

  static const _kMember = 'member';
  static const _kCoins = 'coins';
  static const _kUnlocks = 'unlocks'; // List<"seriesId:ep">
  static const _kFirstLogin = 'first_login_bonus_done';
  static const _kActivity = 'daily_activity'; // { "yyyy-mm-dd": { key: count } }

  /// The stored member, with the token read back out of the keystore.
  Member? get member {
    final m = Member.decode(_p.getString(_kMember));
    if (m == null) return null;
    final token = _token ?? m.token; // m.token is only ever set on a device still on the old layout
    return token == null ? m : m.copyWith(token: token);
  }

  Future<void> setMember(Member? m) async {
    _token = m?.token;

    if (m == null) {
      await _forgetToken();
      await _p.remove(_kMember);
      return;
    }

    if (_secureOk) {
      try {
        if (m.token == null) {
          await _secure.delete(key: _kToken);
        } else {
          await _secure.write(key: _kToken, value: m.token);
        }
        await _p.setString(_kMember, m.withoutToken().encode());
        return;
      } catch (_) {
        // fall through: a keystore that fails mid-session must not cost the member their session
      }
    }
    await _p.setString(_kMember, m.encode());
  }

  Future<void> _forgetToken() async {
    _token = null;
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {}
  }

  int get coins => _p.getInt(_kCoins) ?? 0;
  Future<void> setCoins(int v) => _p.setInt(_kCoins, v < 0 ? 0 : v);

  bool get firstLoginBonusDone => _p.getBool(_kFirstLogin) ?? false;
  Future<void> setFirstLoginBonusDone() => _p.setBool(_kFirstLogin, true);

  Set<String> get _unlocks => (_p.getStringList(_kUnlocks) ?? const []).toSet();
  bool isUnlocked(int seriesId, int ep) => _unlocks.contains('$seriesId:$ep');
  Future<void> addUnlock(int seriesId, int ep) async {
    final set = _unlocks..add('$seriesId:$ep');
    await _p.setStringList(_kUnlocks, set.toList());
  }

  // ---- daily activity counters (e.g. reward-watch count, check-in) ----
  Map<String, dynamic> _activityFor(String date) {
    final raw = _p.getString(_kActivity);
    if (raw == null) return {};
    try {
      final all = jsonDecode(raw) as Map<String, dynamic>;
      return (all[date] as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  int activityCount(String date, String key) => (_activityFor(date)[key] as num?)?.toInt() ?? 0;

  Future<void> bumpActivity(String date, String key) async {
    Map<String, dynamic> all = {};
    final raw = _p.getString(_kActivity);
    if (raw != null) {
      try {
        all = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    // keep only today's bucket to avoid unbounded growth
    final today = (all[date] as Map<String, dynamic>?) ?? {};
    today[key] = ((today[key] as num?)?.toInt() ?? 0) + 1;
    await _p.setString(_kActivity, jsonEncode({date: today}));
  }

  Future<void> clear() async {
    await _forgetToken();
    await _p.remove(_kMember);
    await _p.remove(_kCoins);
    await _p.remove(_kUnlocks);
    await _p.remove(_kActivity);
    // keep _kFirstLogin so signing in again doesn't re-grant the bonus
  }
}
