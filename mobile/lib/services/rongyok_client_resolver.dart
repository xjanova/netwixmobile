import 'package:dio/dio.dart';

/// Fixed source only. Uses the viewer's connection, without NetWix bearer tokens or proxy secrets.
class RongYokClientResolver {
  RongYokClientResolver({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 10),
              followRedirects: false,
            ),
          );

  final Dio _dio;
  static const origin = 'https://rongyok.com';
  static final _endpoint = RegExp(r'^[a-zA-Z0-9_]{4,64}\.php$');

  static bool validVideoUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value.length > 2048 ||
        uri.scheme != 'https' ||
        !{'cdn.discordapp.com', 'media.discordapp.net'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port != 443 ||
        !RegExp(
          r'^/attachments/\d+/\d+/[^/]+\.mp4$',
          caseSensitive: false,
        ).hasMatch(uri.path)) {
      return false;
    }
    final expiry = int.tryParse(uri.queryParameters['ex'] ?? '', radix: 16);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiry != null &&
        expiry > now + 300 &&
        expiry <= now + 172800 &&
        (uri.queryParameters['is'] ?? '').isNotEmpty &&
        (uri.queryParameters['hm'] ?? '').isNotEmpty;
  }

  Future<String?> resolve(Map<String, dynamic> descriptor) async {
    final id = descriptor['series_id']?.toString() ?? '';
    final ep = descriptor['episode']?.toString() ?? '';
    final endpoint = descriptor['endpoint']?.toString() ?? '';
    if (descriptor['source'] != 'rongyok' ||
        !RegExp(r'^\d{1,20}$').hasMatch(id) ||
        !RegExp(r'^[1-9]\d{0,3}$').hasMatch(ep) ||
        !_endpoint.hasMatch(endpoint)) {
      return null;
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36',
      'Referer': '$origin/watch/?series_id=$id&ep=$ep',
    };
    final first = await _request(endpoint, id, ep, headers);
    if (first != null) return first;
    // A filename may rotate while the server cannot read watch.js. Discover it on this device.
    try {
      final js = await _dio.get<String>(
        '$origin/watch/watch.js',
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      );
      final match = RegExp(
        r'''/watch/([a-zA-Z0-9_]{4,64}\.php)\?[^"'`\s]*series_id''',
      ).firstMatch((js.data ?? '').replaceAll(r'\/', '/'));
      final fresh = match?.group(1);
      if (fresh != null && fresh != endpoint)
        return _request(fresh, id, ep, headers);
    } catch (_) {
      /* Source unavailable on this connection as well. */
    }
    return null;
  }

  Future<String?> _request(
    String endpoint,
    String id,
    String ep,
    Map<String, String> headers,
  ) async {
    try {
      final r = await _dio.get(
        '$origin/watch/$endpoint',
        queryParameters: {'series_id': id, 'ep': ep},
        options: Options(headers: headers, followRedirects: false),
      );
      final data = r.data;
      if (data is! Map || (data['ok'] != true && data['ok'] != 'true'))
        return null;
      final url = data['video_url'];
      return url is String && validVideoUrl(url) ? url : null;
    } catch (_) {
      return null;
    }
  }
}
