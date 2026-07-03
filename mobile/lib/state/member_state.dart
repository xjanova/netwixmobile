import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/referral.dart';
import '../services/account_store.dart';
import '../services/auth_service.dart';
import '../services/netwix_api.dart';
import '../services/netwix_client.dart';
import '../services/reward_config.dart';

/// The app-facing account/coins state. Auth + identity come from NetWix
/// (bearer token on [NetwixApi]); coins/activities stay local-first for now.
class MemberState extends ChangeNotifier {
  MemberState(this._store, this._netwix, this._api, this._auth);

  final AccountStore _store;
  final NetwixClient _netwix;
  final NetwixApi _api;
  final AuthService _auth;

  Member? _member;
  int _coins = 0;
  ReferralStatus? _referral;

  Member? get member => _member;
  bool get isLoggedIn => _member?.isLoggedIn ?? false;
  bool get isPro => _member?.proActive ?? false;
  int get coins => _coins;

  /// Prefer the server's referral code; fall back to the cached member's.
  String get referralCode {
    final r = _referral?.code;
    if (r != null && r.isNotEmpty) return r;
    return _member?.referralCode ?? '';
  }

  // ---- referral → free-Pro promo (server-authoritative; see [ReferralStatus]) ----
  ReferralStatus? get referral => _referral;
  int get referralQualified => _referral?.qualified ?? 0;
  int get referralTarget => _referral?.target ?? RewardConfig.referralTarget;
  int get referralRewardMonths => _referral?.rewardMonths ?? RewardConfig.referralRewardMonths;
  bool get referralUnlocked => _referral?.unlocked ?? false;

  /// When the current Pro expires (referral-granted or paid), if known.
  DateTime? get proUntil => _referral?.proUntil ?? _member?.proUntil;

  /// The link to share when inviting friends.
  String get shareLink =>
      _referral?.link ?? 'https://netwix.online/r/$referralCode';

  void init() {
    _member = _store.member;
    _coins = _store.coins;
    final token = _member?.token;
    _netwix.setToken(token);
    _api.setToken(token);
    notifyListeners();
    if (token != null) {
      unawaited(_refreshMe());
      unawaited(refreshReferral());
    }
  }

  /// Re-pull the profile from the server (name/avatar/plan may have changed).
  Future<void> _refreshMe() async {
    final me = await _api.fetchMe();
    if (me == null) return; // transient/401 — keep the cached member
    _member = Member.fromNetwixUser(me, token: _member?.token);
    await _store.setMember(_member);
    notifyListeners();
  }

  /// Pull referral/promo progress (qualified friends, Pro grant) from the
  /// server. Keeps the cached value on transient failure so the UI never
  /// flickers back to 0. The Pro perk is granted server-side, not here.
  Future<void> refreshReferral() async {
    if (!isLoggedIn) {
      _referral = null;
      notifyListeners();
      return;
    }
    final r = await _netwix.fetchReferral();
    if (r == null) return; // backend not answering — keep what we have
    _referral = r;
    notifyListeners();
  }

  // -------------------------------------------------------------- auth

  /// Runs the web sign-in bridge. Throws [AuthCancelled] if the user backs out.
  Future<AuthResult> login(AuthProvider provider) async {
    final res = await _auth.signIn(provider);
    _member = res.member;
    await _store.setMember(res.member);
    _netwix.setToken(res.member.token);
    _api.setToken(res.member.token);

    // ล็อกอินครั้งแรกด้วยบัญชี → +10 เหรียญ (ครั้งเดียวตลอดกาล)
    if (!_store.firstLoginBonusDone) {
      await _addCoins(RewardConfig.firstLoginBonus, 'first_login');
      await _store.setFirstLoginBonusDone();
    }
    notifyListeners();
    unawaited(refreshReferral());
    return res;
  }

  Future<void> logout() async {
    await _api.logoutToken(); // best-effort server revoke
    _member = null;
    _referral = null;
    _netwix.setToken(null);
    _api.setToken(null);
    await _store.setMember(null);
    notifyListeners();
  }

  // ------------------------------------------------------------- coins

  Future<void> _addCoins(int delta, String reason) async {
    _coins = (_coins + delta).clamp(0, 1 << 31);
    await _store.setCoins(_coins);
    unawaited(_netwix.earn(reason)); // server reconciles when live
  }

  /// Public earn (referral bonuses, etc.).
  Future<void> earn(int delta, String reason) async {
    await _addCoins(delta, reason);
    notifyListeners();
  }

  Future<bool> _spend(int amount) async {
    if (_coins < amount) return false;
    _coins -= amount;
    await _store.setCoins(_coins);
    return true;
  }

  // ----------------------------------------------------------- gating

  /// Free for the first [freeEpisodes] (by position), for Pro members, or if
  /// unlocked. When the lock is disabled, every episode is free.
  /// [episodeId] is the stable NetWix episode id used as the unlock key.
  bool isEpisodeUnlocked(int contentId, int episodeId, int index, {required bool isPro}) {
    if (!RewardConfig.gatingEnabled) return true;
    if (isPro) return true;
    if (index < RewardConfig.freeEpisodes) return true;
    return _store.isUnlocked(contentId, episodeId);
  }

  bool isUnlocked(int contentId, int episodeId) => _store.isUnlocked(contentId, episodeId);

  /// Spends coins to unlock one episode. Returns false if not enough coins.
  Future<bool> unlockEpisode(int contentId, int episodeId) async {
    if (_store.isUnlocked(contentId, episodeId)) return true;
    if (!await _spend(RewardConfig.unlockCost)) return false;
    await _store.addUnlock(contentId, episodeId);
    unawaited(_netwix.unlock(contentId, episodeId));
    notifyListeners();
    return true;
  }

  int get unlockCost => RewardConfig.unlockCost;

  // -------------------------------------------------------- activities

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get checkedInToday => _store.activityCount(_today, 'checkin') > 0;

  /// Daily check-in → coins (once per day). Returns coins granted (0 if already).
  Future<int> dailyCheckIn() async {
    if (checkedInToday) return 0;
    await _store.bumpActivity(_today, 'checkin');
    await _addCoins(RewardConfig.dailyCheckin, 'daily_checkin');
    notifyListeners();
    return RewardConfig.dailyCheckin;
  }

  int get rewardWatchesToday => _store.activityCount(_today, 'reward');
  bool get canRewardWatch => rewardWatchesToday < RewardConfig.rewardWatchDailyMax;

  /// Grants coins for finishing a reward clip (respects the daily cap).
  Future<int> claimRewardWatch() async {
    if (!canRewardWatch) return 0;
    await _store.bumpActivity(_today, 'reward');
    await _addCoins(RewardConfig.rewardWatchCoins, 'reward_watch');
    notifyListeners();
    return RewardConfig.rewardWatchCoins;
  }

  // -------------------------------------------------- social → coins
  // Small coin nudges for like/comment/share. Signed-in only, daily-capped so
  // repeatedly toggling a like can't farm coins. The server is authoritative
  // for the real balance ([_addCoins] fires `earn(reason)`); these are the
  // local, best-effort mirror so the reward shows instantly.

  Future<int> _awardCapped(String key, int coins, int dailyMax) async {
    if (!isLoggedIn) return 0;
    if (_store.activityCount(_today, key) >= dailyMax) return 0;
    await _store.bumpActivity(_today, key);
    await _addCoins(coins, key);
    notifyListeners();
    return coins;
  }

  /// +coins for liking a title (only when turning a like ON; capped/day).
  Future<int> awardLike() =>
      _awardCapped('like', RewardConfig.likeCoins, RewardConfig.likeDailyMax);

  /// +coins for posting a comment (capped/day).
  Future<int> awardComment() =>
      _awardCapped('comment', RewardConfig.commentCoins, RewardConfig.commentDailyMax);

  /// +coins for sharing a title or an invite (capped/day).
  Future<int> awardShare() =>
      _awardCapped('share', RewardConfig.shareCoins, RewardConfig.shareDailyMax);
}
