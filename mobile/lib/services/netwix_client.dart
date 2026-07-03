import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/referral.dart';

/// Client for **netwix.online** — the membership / coins / social backend.
/// It is wired and ready but degrades to a **silent no-op** until the backend
/// is live (every method returns null/empty on failure), so the app ships now
/// and runs fully on the local-first fallback in AccountService.
///
/// ── netwix.online API contract to build (Laravel, `{success,data}` envelope,
///    same style as main.thaiprompt.online) ──
///   POST /api/auth/google   { id_token, ref? }         → { token, member{…,coins,referral_code,is_pro} }
///   POST /api/auth/line     { access_token, ref? }     → same
///   GET  /api/me            (Bearer)                    → member + coins
///   GET  /api/wallet        (Bearer)                    → { coins, ledger[] }
///   POST /api/coins/earn    { activity, meta? }         → { coins }              (server-authoritative)
///   POST /api/unlock        { series_id, episode }      → { unlocked, coins }
///   GET  /api/unlocks?series_id=                        → { episodes[] }
///   GET  /api/series/{id}/social                        → { likes, liked, comments }
///   POST /api/series/{id}/like                          → { likes, liked }
///   GET  /api/series/{id}/comments                      → { comments[] }
///   POST /api/series/{id}/comments  { text }            → { comment }
///   GET  /api/referral      (Bearer)  → { code, qualified, pending, target,
///                                         reward_months, claimed, pro_until, share_url }
///        (qualified = friends who signed up + verified + finished ≥1 episode;
///         at qualified>=target the server grants Pro until pro_until, once.)
///   GET  /api/rewards/tasks (Bearer)                    → { tasks[] }
///   POST /api/rewards/heartbeat { task_id, session, seconds }   (anti-cheat)
///   POST /api/rewards/claim { task_id }                 → { coins }
class NetwixClient {
  NetwixClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Accept': 'application/json'},
            ));

  static const String baseUrl = 'https://netwix.online';

  final Dio _dio;
  String? _token;

  bool get hasToken => _token != null;
  void setToken(String? token) => _token = token;

  Options get _auth => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  /// True only when the backend actually answered our health check.
  Future<bool> ping() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/ping');
      return r.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------ auth

  /// Exchanges a provider token for a netwix session. Returns null if the
  /// backend is unavailable (caller falls back to a local account).
  Future<Member?> authWithGoogle(String idToken, {String? ref}) =>
      _auth2('/api/auth/google', {'id_token': idToken, 'ref': ?ref});

  Future<Member?> authWithLine(String accessToken, {String? ref}) =>
      _auth2('/api/auth/line', {'access_token': accessToken, 'ref': ?ref});

  Future<Member?> _auth2(String path, Map<String, dynamic> body) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = r.data;
      if (data == null || data['success'] != true) return null;
      final d = data['data'] as Map<String, dynamic>?;
      if (d == null) return null;
      final token = d['token'] as String?;
      final m = (d['member'] as Map<String, dynamic>?) ?? d;
      final member = Member.fromJson({...m, 'token': token});
      _token = token;
      return member;
    } catch (e) {
      if (kDebugMode) debugPrint('netwix $path failed: $e');
      return null;
    }
  }

  // -------------------------------------------------------- coins / unlock

  Future<int?> earn(String activity, {Map<String, dynamic>? meta}) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/api/coins/earn',
          data: {'activity': activity, 'meta': ?meta}, options: _auth);
      final d = r.data;
      if (d?['success'] != true) return null;
      return ((d!['data'] as Map)['coins'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<bool> unlock(int seriesId, int episode) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/api/unlock',
          data: {'series_id': seriesId, 'episode': episode}, options: _auth);
      return r.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ referral

  /// Referral programme + launch-promo status (Bearer). Returns null when the
  /// backend is unavailable — the caller then shows the local code with 0/target
  /// progress until the server answers. The Pro grant itself is decided
  /// server-side (see [ReferralStatus]); the app never unlocks Pro on its own.
  Future<ReferralStatus?> fetchReferral() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/referral', options: _auth);
      if (r.data?['success'] != true) return null;
      final d = r.data!['data'];
      return d is Map<String, dynamic> ? ReferralStatus.fromJson(d) : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- social

  /// Returns {likes:int, liked:bool} or null.
  Future<Map<String, dynamic>?> toggleLike(int seriesId) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/api/series/$seriesId/like', options: _auth);
      if (r.data?['success'] != true) return null;
      return r.data!['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<List<Comment>?> comments(int seriesId) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/series/$seriesId/comments', options: _auth);
      if (r.data?['success'] != true) return null;
      final list = (r.data!['data'] as Map)['comments'];
      if (list is! List) return const [];
      return list.whereType<Map<String, dynamic>>().map(Comment.fromJson).toList();
    } catch (_) {
      return null;
    }
  }

  Future<Comment?> postComment(int seriesId, String text) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/api/series/$seriesId/comments',
          data: {'text': text}, options: _auth);
      if (r.data?['success'] != true) return null;
      final c = (r.data!['data'] as Map)['comment'];
      return c is Map<String, dynamic> ? Comment.fromJson(c) : null;
    } catch (_) {
      return null;
    }
  }
}
