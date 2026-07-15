import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/mission.dart';
import '../models/referral.dart';
import '../services/account_store.dart';
import '../services/auth_service.dart';
import '../services/netwix_api.dart';
import '../services/reward_config.dart';

/// The app-facing account/coins state. Identity + the coin economy come from
/// NetWix (`/api/app/*`, bearer token): when signed in, coins / Pro / referral
/// are **server-authoritative** — daily check-in, watch-reward and episode
/// unlocks post to the server and the balance is read back from it. Guests fall
/// back to the local store.
class MemberState extends ChangeNotifier {
  MemberState(this._store, this._api, this._auth);

  final AccountStore _store;
  final NetwixApi _api;
  final AuthService _auth;

  Member? _member;
  int _coins = 0;
  int _gold = 0;
  ReferralStatus? _referral;
  bool _dailyAvailable = true; // server: daily_checkin_available
  List<MissionItem> _missions = const [];
  Map<String, dynamic>? _config; // public membership/config (campaign rules)

  Member? get member => _member;
  bool get isLoggedIn => _member?.isLoggedIn ?? false;
  bool get isPro => _member?.proActive ?? false;
  int get coins => _coins;

  /// Gold-coin balance (server-authoritative; missions can reward gold).
  int get goldCoins => _gold;

  /// Watch-to-earn missions from the server (empty for guests).
  List<MissionItem> get missions => _missions;

  // ---- live campaign rules (public membership/config; works for guests) ----

  /// Free-Pro days a NEW signup gets right now (0 = campaign off).
  int get signupFreeProDays {
    final pro = _config?['pro'];
    return pro is Map ? ((pro['free_days'] as num?)?.toInt() ?? 0) : 0;
  }

  /// Free-Pro days each referred friend grants (0 = off).
  int get referralProDays {
    final ref = _config?['referral'];
    if (ref is! Map || ref['enabled'] == false) return 0;
    return (ref['referee_pro_days'] as num?)?.toInt() ?? 0;
  }

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
  String get shareLink => _referral?.link ?? NetwixApi.referralUrl(referralCode);

  void init() {
    _member = _store.member;
    _coins = _store.coins;
    final token = _member?.token;
    _api.setToken(token);
    notifyListeners();
    if (token != null) unawaited(refreshMembership());
    unawaited(refreshCampaignConfig()); // public — guests see live promos too
  }

  /// Pull the PUBLIC campaign rules (free-Pro signup window, referral rewards)
  /// so the app's promos always match the web's live config.
  Future<void> refreshCampaignConfig() async {
    final cfg = await _api.fetchMembershipConfig();
    if (cfg == null) return;
    _config = cfg;
    notifyListeners();
  }

  /// Pull the member's server truth — profile, coins, Pro, referral. Keeps the
  /// cached values on a transient failure so the UI never flickers.
  Future<void> refreshMembership() async {
    if (!isLoggedIn) return;
    final me = await _api.fetchMe();
    if (me == null) return; // 401 / offline — keep cache
    _member = Member.fromNetwixUser(me, token: _member?.token);
    unawaited(_store.setMember(_member));
    _applyState(me['membership'] ?? me);
    notifyListeners();
  }

  /// Back-compat alias (referral now comes from the membership state).
  Future<void> refreshReferral() => refreshMembership();

  /// Pull the watch-to-earn missions + this member's status for each.
  Future<void> refreshMissions() async {
    if (!isLoggedIn) {
      if (_missions.isNotEmpty) {
        _missions = const [];
        notifyListeners();
      }
      return;
    }
    final items = await _api.fetchMissions();
    _missions = items;
    notifyListeners();
  }

  /// Apply a fresh server membership state (e.g. the one a completed mission
  /// hands back) so coins/Pro update everywhere at once.
  void applyMembershipState(Map<String, dynamic> state) {
    _applyState(state);
    notifyListeners();
  }

  /// Apply a server membership `state` map to local coins / Pro / referral.
  void _applyState(dynamic raw) {
    if (raw is! Map) return;
    final s = raw.cast<String, dynamic>();

    _coins = (s['coins'] as num?)?.toInt() ?? _coins;
    _gold = (s['gold_coins'] as num?)?.toInt() ?? _gold;
    unawaited(_store.setCoins(_coins));

    if (s.containsKey('daily_checkin_available')) {
      _dailyAvailable = s['daily_checkin_available'] != false;
    }

    final code = (s['referral_code'] ?? _referral?.code ?? _member?.referralCode ?? '').toString();
    _referral = ReferralStatus(
      code: code,
      qualified: (s['referrals_count'] as num?)?.toInt() ?? 0,
      target: RewardConfig.referralTarget,
      rewardMonths: RewardConfig.referralRewardMonths,
      proUntil: _dateFrom(s['pro_until']),
    );

    if (_member != null) {
      _member = _member!.copyWith(isPro: s['is_pro'] == true, proUntil: _dateFrom(s['pro_until']));
      unawaited(_store.setMember(_member));
    }
  }

  static DateTime? _dateFrom(dynamic v) =>
      (v == null || '$v'.isEmpty) ? null : DateTime.tryParse('$v')?.toLocal();

  // -------------------------------------------------------------- auth

  /// Runs the web sign-in bridge. Throws [AuthCancelled] if the user backs out.
  Future<AuthResult> login(AuthProvider provider) async {
    final res = await _auth.signIn(provider);
    _member = res.member;
    await _store.setMember(res.member);
    _api.setToken(res.member.token);
    // Server is the source of truth for coins/Pro/referral (incl. the signup
    // bonus + any referral grant applied at sign-up).
    await refreshMembership();
    notifyListeners();
    return res;
  }

  Future<void> logout() async {
    await _api.logoutToken(); // best-effort server revoke
    _member = null;
    _referral = null;
    _missions = const [];
    _gold = 0;
    _api.setToken(null);
    await _store.setMember(null);
    notifyListeners();
  }

  /// Redeem a friend's referral code → both sides get the promo (server-side).
  /// Returns null on success, or a localized error message.
  Future<String?> redeemReferral(String code) async {
    if (!isLoggedIn) return 'ต้องเข้าสู่ระบบก่อน';
    final res = await _api.redeemReferral(code.trim());
    if (res.state != null) _applyState(res.state);
    notifyListeners();
    return res.ok ? null : (res.error ?? 'ใช้โค้ดไม่สำเร็จ');
  }

  // ------------------------------------------------------------- coins

  Future<void> _addCoins(int delta) async {
    _coins = (_coins + delta).clamp(0, 1 << 31);
    await _store.setCoins(_coins);
  }

  /// Public earn (local, guest-side).
  Future<void> earn(int delta, String reason) async {
    await _addCoins(delta);
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
  bool isEpisodeUnlocked(int contentId, int episodeId, int index, {required bool isPro}) {
    if (!RewardConfig.gatingEnabled) return true;
    if (isPro) return true;
    if (index < RewardConfig.freeEpisodes) return true;
    return _store.isUnlocked(contentId, episodeId);
  }

  bool isUnlocked(int contentId, int episodeId) => _store.isUnlocked(contentId, episodeId);

  /// Unlock one episode. Signed in → the server spends coins and records the
  /// unlock (persists across devices); guest → local coins only.
  Future<bool> unlockEpisode(int contentId, int episodeId) async {
    if (_store.isUnlocked(contentId, episodeId)) return true;

    if (isLoggedIn) {
      final res = await _api.unlockEpisodeApp(episodeId);
      if (res.state != null) _applyState(res.state);
      if (!res.ok) {
        notifyListeners();
        return false;
      }
      await _store.addUnlock(contentId, episodeId); // local cache mirror
      notifyListeners();
      return true;
    }

    if (!await _spend(RewardConfig.unlockCost)) return false;
    await _store.addUnlock(contentId, episodeId);
    notifyListeners();
    return true;
  }

  int get unlockCost => RewardConfig.unlockCost;

  // -------------------------------------------------------- activities

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get checkedInToday =>
      isLoggedIn ? !_dailyAvailable : _store.activityCount(_today, 'checkin') > 0;

  /// Daily check-in → coins (once per day). Signed in → server; guest → local.
  /// Returns coins granted (0 if already done today).
  Future<int> dailyCheckIn() async {
    if (isLoggedIn) {
      final before = _coins;
      final res = await _api.earnCoins('daily');
      if (res.state != null) _applyState(res.state);
      notifyListeners();
      if (!res.ok) return 0;
      final earned = _coins - before;
      return earned > 0 ? earned : RewardConfig.dailyCheckin;
    }
    if (checkedInToday) return 0;
    await _store.bumpActivity(_today, 'checkin');
    await _addCoins(RewardConfig.dailyCheckin);
    notifyListeners();
    return RewardConfig.dailyCheckin;
  }

  int get rewardWatchesToday => _store.activityCount(_today, 'reward');
  bool get canRewardWatch => rewardWatchesToday < RewardConfig.rewardWatchDailyMax;

  /// Grants coins for finishing a reward clip. Signed in → server (which
  /// enforces the daily cap); guest → local.
  Future<int> claimRewardWatch() async {
    if (isLoggedIn) {
      final before = _coins;
      final res = await _api.earnCoins('watch');
      if (res.state != null) _applyState(res.state);
      await _store.bumpActivity(_today, 'reward'); // local cap hint for the UI
      notifyListeners();
      if (!res.ok) return 0;
      final earned = _coins - before;
      return earned > 0 ? earned : RewardConfig.rewardWatchCoins;
    }
    if (!canRewardWatch) return 0;
    await _store.bumpActivity(_today, 'reward');
    await _addCoins(RewardConfig.rewardWatchCoins);
    notifyListeners();
    return RewardConfig.rewardWatchCoins;
  }

  // -------------------------------------------------- social → coins
  // like/comment/share now earn REAL coins server-side (POST /coins/earn),
  // capped per day by the server ledger. Signed-in only.

  Future<int> _awardServer(String kind, int fallback) async {
    if (!isLoggedIn) return 0;
    final before = _coins;
    final res = await _api.earnCoins(kind);
    if (res.state != null) _applyState(res.state);
    notifyListeners();
    if (!res.ok) return 0; // capped for today (or offline)
    final earned = _coins - before;
    return earned > 0 ? earned : fallback;
  }

  /// +coins for liking a title (only when turning a like ON; capped/day).
  Future<int> awardLike() => _awardServer('like', RewardConfig.likeCoins);

  /// +coins for posting a comment (capped/day).
  Future<int> awardComment() => _awardServer('comment', RewardConfig.commentCoins);

  /// +coins for sharing a title or an invite (capped/day).
  Future<int> awardShare() => _awardServer('share', RewardConfig.shareCoins);
}
