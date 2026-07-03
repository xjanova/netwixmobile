import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/content.dart';
import '../models/episode.dart';

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

  /// Titles by type (series | movie | vertical), paginated.
  Future<List<Content>> fetchTitles({String? type, int page = 1, int per = 24}) async {
    try {
      final d = _data(await _dio.get('/titles', queryParameters: {
        'type': ?type,
        'page': page,
        'per': per,
      }, options: _opts));
      return _contentList(d?['items']);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix fetchTitles: $e');
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

  Future<List<Content>> search(String q) async {
    try {
      final d = _data(await _dio.get('/search', queryParameters: {'q': q}, options: _opts));
      return _contentList(d?['items']);
    } catch (e) {
      if (kDebugMode) debugPrint('netwix search: $e');
      return const [];
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
  const NetwixSource({required this.ready, this.kind, this.url});
  final bool ready;
  final String? kind; // 'mp4' | 'hls'
  final String? url;

  bool get isHls => kind == 'hls';

  factory NetwixSource.fromJson(Map<String, dynamic> j) => NetwixSource(
        ready: j['ready'] == true,
        kind: j['kind'] as String?,
        url: j['url'] as String?,
      );
}
