import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/ad.dart';
import '../models/content.dart';
import '../models/notice.dart';
import '../models/episode.dart';
import '../models/member.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/wallet.dart';

/// Client for the NetWix mobile API (`https://netwix.online/api/app/*`).
///
/// This is the app's ONLY content backend. NetWix resolves each episode's stream
/// server-side, on demand: a FRESH signed CDN mp4 for rongyok (the links expire
/// ~24h but are NOT IP-locked — the old app just kept fetching stale ones), or an
/// HMAC-signed HLS proxy for wow-drama. Either way the client plays the returned
/// url directly (no headers), from any IP. Envelope: `{ "success": bool, "data": {...} }`.
class NetwixApi {
  NetwixApi({Dio? dio, String? token})
      : _token = token,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json'},
            ));

  static const String origin = 'https://netwix.online';
  static const String baseUrl = '$origin/api/app';

  /// Public web page for a title. Must match the web route `/title/{content}`,
  /// which binds by slug (Content::getRouteKeyName). The app previously shared
  /// `/t/{slug}`, a route that has never existed — every shared link 404'd.
  static String titleUrl(String slug) => '$origin/title/$slug';

  /// Referral invite link. The web has no `/r/{code}` route; the register page
  /// reads the code from `?ref=` (RegisterController redeems it on signup).
  static String referralUrl(String code) =>
      '$origin/register?ref=${Uri.encodeQueryComponent(code)}';

  /// Legal pages (admin-editable on the web; the app renders them in a WebView
  /// so there is exactly one source of truth).
  static const String termsUrl = '$origin/terms';
  static const String privacyUrl = '$origin/privacy';

  final Dio _dio;
  String? _token;

  /// Set/clear the member token (Phase 3). Sent as Bearer on every request.
  void setToken(String? token) => _token = token;

  Options get _opts => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  Map<String, dynamic>? _data(Response r) {
    final b = r.data;
    if (b is Map && b['success'] == true && b['data'] is Map) {
      return (b['data'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  // ------------------------------------------------------------- catalog

  /// Home hero + rails.
  Future<NetwixHome?> fetchHome() async {
    try {
      final d = _data(await _dio.get('/home', options: _opts));
      if (d == null) return null;
      final hero = d['hero'] is Map ? Content.fromJson((d['hero'] as Map).cast<String, dynamic>()) : null;
      final rails = <NetwixRail>[];
      if (d['rails'] is List) {
        for (final r in d['rails']) {
          if (r is Map) rails.add(NetwixRail.fromJson(r.cast<String, dynamic>()));
        }
      }
      return NetwixHome(hero: hero, rails: rails);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchHome: $e');
      return null;
    }
  }

  /// One page of titles + total + whether more pages exist — for the Explore
  /// grid's infinite scroll. Narrow by media [type] (series|movie|vertical), by
  /// [genre] slug, by main-category [scope] (anime|notanime — keeps movies/series
  /// from bleeding into anime, like the web), or set [anime] for the anime bucket.
  /// scope + genre combine server-side.
  Future<PagedContent> fetchTitlesPage(
      {String? type, String? genre, String? scope, bool anime = false, int page = 1, int per = 30}) async {
    try {
      final d = _data(await _dio.get('/titles', queryParameters: {
        'type': ?type,
        'genre': ?genre,
        'scope': ?scope,
        if (anime) 'anime': 1,
        'page': page,
        'per': per,
      }, options: _opts));
      return PagedContent(
        _contentList(d?['items']),
        d?['has_more'] == true,
        total: (d?['total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchTitlesPage: $e');
      return const PagedContent(<Content>[], false);
    }
  }

  /// One page of server-side search results (matches title + synopsis).
  Future<PagedContent> searchPage(String q, {int page = 1}) async {
    try {
      final d = _data(await _dio.get('/search',
          queryParameters: {'q': q, 'page': page}, options: _opts));
      return PagedContent(_contentList(d?['items']), d?['has_more'] == true);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix searchPage: $e');
      return const PagedContent(<Content>[], false);
    }
  }

  /// The genre taxonomy for the app's category chips (name, name_en, slug,
  /// is_anime). Empty on failure.
  Future<List<GenreChip>> fetchGenres() async {
    try {
      final d = _data(await _dio.get('/genres', options: _opts));
      final items = d?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => GenreChip.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchGenres: $e');
      return const [];
    }
  }

  Future<NetwixDetail?> fetchDetail(String slug) async {
    try {
      final d = _data(await _dio.get('/titles/$slug', options: _opts));
      if (d == null) return null;
      return NetwixDetail(
        content: Content.fromJson((d['content'] as Map).cast<String, dynamic>()),
        episodes: _episodeList(d['episodes']),
        related: _contentList(d['related']),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchDetail: $e');
      return null;
    }
  }

  // ------------------------------------------------------------- playback

  /// Resolves a playable stream for an episode.
  /// Returns null on network error; a [NetwixSource] with `ready=false` when the
  /// episode isn't mirrored yet ("preparing").
  Future<NetwixSource?> resolveSource(int episodeId) async {
    try {
      final r = await _dio.get('/episodes/$episodeId/source',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final data = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : null;
      if (data == null) return const NetwixSource(ready: false);
      return NetwixSource.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix resolveSource($episodeId): $e');
      return null;
    }
  }

  /// The pre-roll ad the server picked for this title + viewer, or null.
  /// Targeting/schedule/hide_for_pro are all decided server-side; a failure just
  /// means no ad — it must never block playback.
  Future<PrerollAd?> fetchPreroll(int contentId) async {
    try {
      final d = _data(await _dio.get('/content/$contentId/ad', options: _opts));
      final ad = d?['ad'];
      return ad is Map ? PrerollAd.fromJson(ad.cast<String, dynamic>()) : null;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix preroll($contentId): $e');
      return null;
    }
  }

  /// Count a watch on the server (deduped server-side). Fire-and-forget.
  Future<void> recordView(int contentId) async {
    try {
      await _dio.post('/content/$contentId/view',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix recordView($contentId): $e');
    }
  }

  // ---------------------------------------------------- notifications / banners

  /// The admin-broadcast notification inbox, newest first. Empty on failure.
  Future<List<AppNotice>> fetchNotifications({int limit = 30}) async {
    try {
      final d = _data(await _dio.get('/notifications',
          queryParameters: {'limit': limit}, options: _opts));
      final items = d?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => AppNotice.fromJson(m.cast<String, dynamic>()))
          .whereType<AppNotice>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchNotifications: $e');
      return const [];
    }
  }

  /// Admin-controlled home-screen promo banners, in display order. The server
  /// already resolved schedule + hide-for-Pro for this viewer. Empty on failure.
  Future<List<PromoBanner>> fetchBanners() async {
    try {
      final d = _data(await _dio.get('/banners', options: _opts));
      final items = d?['banners'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => PromoBanner.fromJson(m.cast<String, dynamic>()))
          .whereType<PromoBanner>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchBanners: $e');
      return const [];
    }
  }

  /// Report anonymous device statistics (disclosed in the privacy policy).
  /// Fire-and-forget; never throws.
  Future<void> sendTelemetry(Map<String, dynamic> payload) async {
    try {
      await _dio.post('/telemetry',
          data: payload,
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix sendTelemetry: $e');
    }
  }

  /// Permanently delete the signed-in account (danger zone). Returns true when
  /// the server confirms deletion.
  Future<bool> deleteAccount() async {
    try {
      final r = await _dio.delete('/account',
          data: {'confirm': 'DELETE'},
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      return b is Map && b['success'] == true;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix deleteAccount: $e');
      return false;
    }
  }

  // ------------------------------------------------------------- member auth

  /// Exchange the one-time login code (from the netwix:// deep link) for a
  /// bearer token. Returns `{token, user}` or null.
  Future<Map<String, dynamic>?> exchangeCode(String code, {String device = 'android'}) async {
    try {
      final r = await _dio.post('/auth/exchange',
          data: {'code': code, 'device': device},
          options: Options(validateStatus: (s) => s != null && s < 500));
      return _data(r);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix exchangeCode: $e');
      return null;
    }
  }

  /// Which social sign-in providers the server has configured, so the app hides
  /// the ones without credentials. Defaults to LINE-only on failure (its creds
  /// are known-good) so a network blip never shows a dead Google button.
  Future<Map<String, bool>> fetchAuthProviders() async {
    try {
      final d = _data(await _dio.get('/auth/providers', options: _opts));
      return {
        'google': d?['google'] == true,
        'line': d?['line'] == true,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('netwix authProviders: $e');
      return const {'google': false, 'line': true};
    }
  }

  /// Current member + default profile (requires a token via [setToken]).
  Future<Map<String, dynamic>?> fetchMe() async {
    try {
      return _data(await _dio.get('/auth/me', options: _opts));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchMe: $e');
      return null;
    }
  }

  /// Revoke the current token server-side. Best-effort.
  Future<void> logoutToken() async {
    try {
      await _dio.post('/auth/logout',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix logoutToken: $e');
    }
  }

  // -------------------------------------------------- membership / coins
  //
  // The server (App\Services\Membership) is authoritative for coins, Pro, and
  // the referral promo. `state` maps below carry:
  //   {is_pro, plan, pro_until, coins, referral_code, referred,
  //    referrals_count, daily_checkin_available}

  /// The member's affiliate downline (levels + members + dividend earned) for
  /// the "My Team" screen. Null on failure.
  Future<Map<String, dynamic>?> fetchTeam() async {
    try {
      return _data(await _dio.get('/team', options: _opts));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix team: $e');
      return null;
    }
  }

  /// The PUBLIC admin-defined membership rules (`membership/config`) — free-Pro
  /// signup window (`pro.free_days`), referral rewards, coin rates. Works for
  /// guests, so the app can show the live campaign promos. Null on failure.
  Future<Map<String, dynamic>?> fetchMembershipConfig() async {
    try {
      return _data(await _dio.get('/membership/config'));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix membershipConfig: $e');
      return null;
    }
  }

  // -------------------------------------------------------------- missions
  //
  // Watch-to-earn missions (same MissionService anti-cheat as the web /missions
  // page): start issues a token, then the app beats every ~15s ONLY while the
  // video is playing AND the app is foregrounded. The server credits real
  // wall-clock time between beats and awards once watched ≥ required.

  /// Active missions + this member's status for each (token-only).
  Future<List<MissionItem>> fetchMissions() async {
    try {
      final d = _data(await _dio.get('/missions', options: _opts));
      final items = d?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => MissionItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix missions: $e');
      return const [];
    }
  }

  /// Begin (or restart) a mission attempt → the heartbeat token.
  Future<MissionStart> startMission(int missionId) async {
    try {
      final r = await _dio.post('/missions/$missionId/start',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final d = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      return MissionStart(
        ok: b is Map && b['success'] == true,
        token: d['token'] as String?,
        required: (d['required'] as num?)?.toInt() ?? 0,
        error: (b is Map ? b['error'] : null) as String?,
        alreadyEarned: d['earned'] == true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix startMission($missionId): $e');
      return const MissionStart(ok: false);
    }
  }

  /// One heartbeat from an actively-playing, foregrounded player.
  Future<MissionBeat> beatMission(int missionId, String token) async {
    try {
      final r = await _dio.post('/missions/$missionId/beat',
          data: {'token': token},
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final d = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final reward = d['reward'];
      return MissionBeat(
        ok: b is Map && b['success'] == true,
        done: d['done'] == true,
        watched: (d['watched'] as num?)?.toInt() ?? 0,
        required: (d['required'] as num?)?.toInt() ?? 0,
        rewardLabel: reward is Map ? reward['label'] as String? : null,
        membership: d['membership'] is Map ? (d['membership'] as Map).cast<String, dynamic>() : null,
        error: (b is Map ? b['error'] : null) as String?,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix beatMission($missionId): $e');
      return const MissionBeat(ok: false);
    }
  }

  /// The member's Pro / coins / referral state (token-only). Null on failure.
  Future<Map<String, dynamic>?> fetchMembership() async {
    try {
      return _data(await _dio.get('/membership', options: _opts));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix membership: $e');
      return null;
    }
  }

  /// Earn coins for an activity (kind: daily | watch). Returns whether it
  /// counted (false = already done / capped) + the fresh state.
  Future<({bool ok, Map<String, dynamic>? state})> earnCoins(String kind) async {
    try {
      final r = await _dio.post('/coins/earn',
          data: {'kind': kind},
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final ok = b is Map && b['success'] == true;
      final state = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : null;
      return (ok: ok, state: state);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix earnCoins($kind): $e');
      return (ok: false, state: null);
    }
  }

  /// Spend coins to unlock a locked episode. Returns ok + the fresh state.
  Future<({bool ok, Map<String, dynamic>? state})> unlockEpisodeApp(int episodeId) async {
    try {
      final r = await _dio.post('/episodes/$episodeId/unlock',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final ok = b is Map && b['success'] == true;
      final data = (b is Map && b['data'] is Map) ? (b['data'] as Map) : null;
      final state =
          (data?['membership'] is Map) ? (data!['membership'] as Map).cast<String, dynamic>() : null;
      return (ok: ok, state: state);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix unlock($episodeId): $e');
      return (ok: false, state: null);
    }
  }

  /// Redeem a friend's referral code (grants the promo both sides). Returns
  /// ok/error + the fresh state.
  Future<({bool ok, String? error, Map<String, dynamic>? state})> redeemReferral(String code) async {
    try {
      final r = await _dio.post('/referral/redeem',
          data: {'code': code},
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final ok = b is Map && b['success'] == true;
      final error = (b is Map ? b['error'] : null) as String?;
      final state = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : null;
      return (ok: ok, error: error, state: state);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix redeem: $e');
      return (ok: false, error: null, state: null);
    }
  }

  // -------------------------------------------------- member library / social
  //
  // Backed by the real `/api/app/*` member endpoints (Library + Feedback
  // controllers). All writes require a member token (set via [setToken]); the
  // server 401s a guest, which surfaces here as a null return — callers gate on
  // login first and treat null as "offline/declined, keep local state".

  /// Per-title interaction state for the detail screen (liked / in-list / my
  /// rating + counts). Token-only — returns null for guests or on failure.
  Future<ContentState?> fetchContentState(int contentId) async {
    try {
      final d = _data(await _dio.get('/content/$contentId/state', options: _opts));
      return d == null ? null : ContentState.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix contentState($contentId): $e');
      return null;
    }
  }

  /// Public rating summary (avg + count) — works for guests too.
  Future<RatingSummary?> fetchRatings(int contentId) async {
    try {
      final d = _data(await _dio.get('/content/$contentId/ratings', options: _opts));
      return d == null ? null : RatingSummary.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix ratings($contentId): $e');
      return null;
    }
  }

  /// Toggle like on a title. Returns the server-authoritative {liked, count}
  /// or null (guest/offline).
  Future<LikeResult?> toggleLike(int contentId) async {
    try {
      final d = _data(await _dio.post('/content/$contentId/like', options: _opts));
      return d == null ? null : LikeResult.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix toggleLike($contentId): $e');
      return null;
    }
  }

  /// Toggle a title in the member's list. Returns the new in-list flag or null.
  Future<bool?> toggleList(int contentId) async {
    try {
      final d = _data(await _dio.post('/content/$contentId/list', options: _opts));
      return d == null ? null : d['in_list'] == true;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix toggleList($contentId): $e');
      return null;
    }
  }

  /// Rate a title 1–5. Returns {myRating, avg, count} or null.
  Future<RatingResult?> postRating(int contentId, int stars) async {
    try {
      final d = _data(await _dio.post('/content/$contentId/rating',
          data: {'stars': stars}, options: _opts));
      return d == null ? null : RatingResult.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix postRating($contentId): $e');
      return null;
    }
  }

  /// Comments for a title (public read; newest first). Empty list on failure.
  Future<List<Comment>> fetchComments(int contentId) async {
    try {
      final d = _data(await _dio.get('/content/$contentId/comments', options: _opts));
      final items = d?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => Comment.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix comments($contentId): $e');
      return const [];
    }
  }

  /// Post a comment (token-only). Returns the created comment or null.
  Future<Comment?> postComment(int contentId, String body) async {
    try {
      final d = _data(await _dio.post('/content/$contentId/comments',
          data: {'body': body}, options: _opts));
      final c = d?['comment'];
      return c is Map ? Comment.fromJson(c.cast<String, dynamic>()) : null;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix postComment($contentId): $e');
      return null;
    }
  }

  /// Mirror the on-device resume position to the server (token-only, best-effort
  /// — a guest or a network blip just leaves the local SQLite resume as truth).
  Future<void> saveProgress({
    required int contentId,
    int? episodeId,
    required int positionSeconds,
    int? durationSeconds,
  }) async {
    try {
      await _dio.post('/progress',
          data: {
            'content_id': contentId,
            'episode_id': ?episodeId,
            'position_seconds': positionSeconds,
            'duration_seconds': ?durationSeconds,
          },
          options: Options(
              headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
    } catch (e) {
      if (kDebugMode) debugPrint('netwix saveProgress: $e');
    }
  }

  /// The member's saved list (token-only). Empty on failure.
  Future<List<Content>> fetchMyList() async {
    try {
      final d = _data(await _dio.get('/my-list', options: _opts));
      return _contentList(d?['items']);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix myList: $e');
      return const [];
    }
  }

  /// Server-side continue-watching (token-only). Empty on failure.
  Future<List<ProgressItem>> fetchProgress() async {
    try {
      final d = _data(await _dio.get('/progress', options: _opts));
      final items = d?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((m) => ProgressItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('netwix progress: $e');
      return const [];
    }
  }

  // -------------------------------------------------------------- profiles
  // Kids mode is enforced server-side: `selectProfile` binds the choice to this
  // device's token, and the server filters adult titles from there. The app
  // never decides what a kids profile may see.

  Future<ProfileList?> fetchProfiles() async {
    try {
      final d = _data(await _dio.get('/profiles', options: _opts));
      return d == null ? null : ProfileList.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix profiles: $e');
      return null;
    }
  }

  /// Create a profile. Returns null on failure (e.g. the 5-profile ceiling).
  Future<Profile?> createProfile({
    required String name,
    String? avatarColor,
    bool isKids = false,
  }) async {
    return _profileWrite(() => _dio.post('/profiles',
        data: {'name': name, 'avatar_color': ?avatarColor, 'is_kids': isKids},
        options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500)));
  }

  /// Make [profileId] this device's active profile (server binds it to the token).
  Future<Profile?> selectProfile(int profileId) async {
    return _profileWrite(() => _dio.post('/profiles/$profileId/select',
        options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500)));
  }

  Future<Profile?> updateProfile(
    int profileId, {
    required String name,
    String? avatarColor,
    bool isKids = false,
  }) async {
    return _profileWrite(() => _dio.post('/profiles/$profileId',
        data: {'name': name, 'avatar_color': ?avatarColor, 'is_kids': isKids},
        options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500)));
  }

  /// Delete a profile. False when the server refuses (e.g. it's the last one).
  Future<bool> deleteProfile(int profileId) async {
    try {
      final r = await _dio.delete('/profiles/$profileId',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      return r.data is Map && (r.data as Map)['success'] == true;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix deleteProfile($profileId): $e');
      return false;
    }
  }

  Future<Profile?> _profileWrite(Future<Response> Function() send) async {
    try {
      final d = _data(await send());
      final p = d?['profile'];
      return p is Map ? Profile.fromJson(p.cast<String, dynamic>()) : null;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix profileWrite: $e');
      return null;
    }
  }

  // ----------------------------------------------------------- gold wallet
  // Thin client over WalletController (auth.apptoken). The web stays
  // authoritative: every balance, rate and cap here is server-computed, and the
  // app only ever renders what the snapshot reports.

  /// Balances + convert rules + USDT config + VIP config, in one trip.
  Future<WalletState?> fetchWallet() async {
    try {
      final d = _data(await _dio.get('/wallet', options: _opts));
      return d == null ? null : WalletState.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix wallet: $e');
      return null;
    }
  }

  /// Convert silver → gold. Returns the refreshed wallet, or the server's error
  /// code (insufficient funds, over the daily cap, convert disabled).
  Future<WalletResult> convertGold(int gold) async {
    return _walletWrite(() => _dio.post('/gold/convert',
        data: {'gold': gold},
        options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500)));
  }

  /// Buy Pro with gold (instant, no chain).
  Future<WalletResult> buyProWithGold() async {
    return _walletWrite(() => _dio.post('/pro/buy-gold',
        options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500)));
  }

  Future<WalletResult> _walletWrite(Future<Response> Function() send) async {
    try {
      final r = await send();
      final b = r.data;
      final ok = b is Map && b['success'] == true;
      final data = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : null;
      return WalletResult(
        ok: ok,
        error: (b is Map ? b['error'] : null) as String?,
        wallet: data == null ? null : WalletState.fromJson(data),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix walletWrite: $e');
      return const WalletResult(ok: false, error: 'network');
    }
  }

  /// VIP access for a title: open | pro | unlocked | locked (+ gold price).
  Future<VipAccess?> fetchVipAccess(int contentId) async {
    try {
      final d = _data(await _dio.get('/content/$contentId/vip', options: _opts));
      return d == null ? null : VipAccess.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix vipAccess($contentId): $e');
      return null;
    }
  }

  /// Spend gold to permanently unlock a VIP title.
  Future<WalletResult> unlockVip(int contentId) async {
    try {
      final r = await _dio.post('/content/$contentId/vip/unlock',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final b = r.data;
      final ok = b is Map && b['success'] == true;
      final data = (b is Map && b['data'] is Map) ? (b['data'] as Map).cast<String, dynamic>() : null;
      final ms = (data?['membership'] is Map)
          ? (data!['membership'] as Map).cast<String, dynamic>()
          : null;
      return WalletResult(
        ok: ok,
        error: (b is Map ? b['error'] : null) as String?,
        access: data?['access'] as String?,
        wallet: ms == null ? null : WalletState.fromJson(ms),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('netwix unlockVip($contentId): $e');
      return const WalletResult(ok: false, error: 'network');
    }
  }

  /// Create a USDT (BEP20) order. `purpose` is 'gold' (needs [usdt]) or 'pro'.
  Future<UsdtOrder?> createUsdtOrder({required String purpose, double? usdt}) async {
    try {
      final r = await _dio.post('/usdt/order',
          data: {'purpose': purpose, 'usdt': ?usdt},
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final d = _data(r);
      return d == null ? null : UsdtOrder.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix createUsdtOrder: $e');
      return null;
    }
  }

  /// Poll an order — the server live-verifies it against the chain. Keyed by the
  /// order's `reference` (UsdtOrder binds on that, not an id).
  Future<UsdtOrder?> checkUsdtOrder(String reference) async {
    try {
      final r = await _dio.post('/usdt/order/${Uri.encodeComponent(reference)}/check',
          options: Options(headers: _opts.headers, validateStatus: (s) => s != null && s < 500));
      final d = _data(r);
      return d == null ? null : UsdtOrder.fromJson(d);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix checkUsdtOrder($reference): $e');
      return null;
    }
  }

  List<Content> _contentList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((m) => Content.fromJson(m.cast<String, dynamic>())).toList();
  }

  List<Episode> _episodeList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((m) => Episode.fromJson(m.cast<String, dynamic>())).toList();
  }
}

class NetwixHome {
  const NetwixHome({this.hero, required this.rails});
  final Content? hero;
  final List<NetwixRail> rails;
}

/// One page of catalog results (for infinite scroll / search).
class PagedContent {
  const PagedContent(this.items, this.hasMore, {this.total = 0});
  final List<Content> items;
  final bool hasMore;
  final int total; // server total for the query (0 when unknown, e.g. search)
}

/// One genre in the taxonomy (`GET /genres`) — backs an Explore category chip.
class GenreChip {
  const GenreChip({required this.name, this.nameEn, required this.slug, this.isAnime = false});
  final String name;
  final String? nameEn;
  final String slug;
  final bool isAnime;

  factory GenreChip.fromJson(Map<String, dynamic> j) => GenreChip(
        name: (j['name'] as String?) ?? '',
        nameEn: j['name_en'] as String?,
        slug: (j['slug'] as String?) ?? '',
        isAnime: j['is_anime'] == true,
      );
}

class NetwixRail {
  const NetwixRail({required this.key, required this.title, required this.ranked, required this.items});
  final String key;
  final String title;
  final bool ranked;
  final List<Content> items;

  factory NetwixRail.fromJson(Map<String, dynamic> j) => NetwixRail(
        key: (j['key'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        ranked: j['ranked'] == true,
        items: (j['items'] is List)
            ? (j['items'] as List).whereType<Map>().map((m) => Content.fromJson(m.cast<String, dynamic>())).toList()
            : const [],
      );
}

class NetwixDetail {
  const NetwixDetail({required this.content, required this.episodes, required this.related});
  final Content content;
  final List<Episode> episodes;
  final List<Content> related;
}

class NetwixSource {
  const NetwixSource({required this.ready, this.kind, this.url, this.error});
  final bool ready;
  final String? kind; // 'mp4' | 'hls'
  final String? url;

  /// Why the stream isn't playable, straight from the server:
  /// `pro_required` / `vip_required` (403 paywalls) or `no_source` (404, gone).
  /// A 202 carries no error — that one really is "still being mirrored".
  /// Without this the app rendered every paywall as a mirroring delay, so a
  /// member who needed to buy something just waited forever.
  final String? error;

  bool get isHls => kind == 'hls';

  /// Blocked behind a purchase rather than a temporary mirroring delay.
  bool get isLocked => error == 'pro_required' || error == 'vip_required';

  /// The source is gone upstream — retrying will never help.
  bool get isGone => error == 'no_source';

  /// Genuinely still mirroring: not ready, but nothing is blocking it.
  bool get isPreparing => !ready && error == null;

  factory NetwixSource.fromJson(Map<String, dynamic> j) => NetwixSource(
        ready: j['ready'] == true,
        kind: j['kind'] as String?,
        url: j['url'] as String?,
        error: j['error'] as String?,
      );
}

/// Per-title member interaction state (`GET /content/{id}/state`).
class ContentState {
  const ContentState({
    this.liked = false,
    this.inList = false,
    this.myRating,
    this.likesCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.commentsCount = 0,
  });

  final bool liked;
  final bool inList;
  final int? myRating; // 1..5, null if the member hasn't rated
  final int likesCount;
  final double ratingAvg;
  final int ratingCount;
  final int commentsCount;

  factory ContentState.fromJson(Map<String, dynamic> j) => ContentState(
        liked: j['liked'] == true,
        inList: j['in_list'] == true,
        myRating: (j['my_rating'] as num?)?.toInt(),
        likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
        ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
        commentsCount: (j['comments_count'] as num?)?.toInt() ?? 0,
      );
}

/// Result of `POST /content/{id}/like`.
class LikeResult {
  const LikeResult({required this.liked, required this.likesCount});
  final bool liked;
  final int likesCount;

  factory LikeResult.fromJson(Map<String, dynamic> j) => LikeResult(
        liked: j['liked'] == true,
        likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
      );
}

/// Result of `POST /content/{id}/rating`.
class RatingResult {
  const RatingResult({required this.myRating, required this.avg, required this.count});
  final int myRating;
  final double avg;
  final int count;

  factory RatingResult.fromJson(Map<String, dynamic> j) => RatingResult(
        myRating: (j['my_rating'] as num?)?.toInt() ?? 0,
        avg: (j['avg'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// Public rating summary (`GET /content/{id}/ratings`).
class RatingSummary {
  const RatingSummary({required this.avg, required this.count});
  final double avg;
  final int count;

  factory RatingSummary.fromJson(Map<String, dynamic> j) => RatingSummary(
        avg: (j['avg'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// One server-side continue-watching row (`GET /progress`).
class ProgressItem {
  const ProgressItem({
    required this.content,
    this.episodeId,
    this.percent = 0,
    this.positionSeconds = 0,
  });

  final Content content;
  final int? episodeId;
  final int percent;
  final int positionSeconds;

  factory ProgressItem.fromJson(Map<String, dynamic> j) => ProgressItem(
        content: Content.fromJson((j['content'] as Map).cast<String, dynamic>()),
        episodeId: (j['episode_id'] as num?)?.toInt(),
        percent: (j['percent'] as num?)?.toInt() ?? 0,
        positionSeconds: (j['position_seconds'] as num?)?.toInt() ?? 0,
      );
}
