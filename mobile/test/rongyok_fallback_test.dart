import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netwix/services/netwix_api.dart';
import 'package:netwix/services/rongyok_client_resolver.dart';

void main() {
  final descriptor = {
    'source': 'rongyok',
    'series_id': '8207',
    'episode': '2',
    'endpoint': 'playseries.php',
  };
  String video({int seconds = 86400}) =>
      'https://cdn.discordapp.com/attachments/1/2/2.mp4?ex='
      '${((DateTime.now().millisecondsSinceEpoch ~/ 1000) + seconds).toRadixString(16)}&is=abc&hm=def';
  Dio fake(dynamic Function(RequestOptions) reply) {
    final dio = Dio(BaseOptions(baseUrl: NetwixApi.baseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (r, h) => h.resolve(reply(r))),
    );
    return dio;
  }

  test('server success uses no source request', () async {
    final upstream = fake((r) => throw StateError('unexpected source request'));
    final server = fake(
      (r) => Response(
        requestOptions: r,
        statusCode: 200,
        data: {
          'success': true,
          'data': {'ready': true, 'kind': 'mp4', 'url': video()},
        },
      ),
    );
    final api = NetwixApi(
      dio: server,
      sourceResolver: RongYokClientResolver(dio: upstream),
    );
    expect((await api.resolveSource(1))?.ready, isTrue);
  });

  test(
    '202 falls back on viewer connection without forwarding bearer credentials',
    () async {
      var called = 0;
      final url = video();
      final upstream = fake((r) {
        called++;
        expect(r.uri.host, 'rongyok.com');
        expect(r.uri.queryParameters['series_id'], '8207');
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.headers.containsKey('X-Relay-Key'), isFalse);
        expect(
          r.headers['Referer'],
          'https://rongyok.com/watch/?series_id=8207&ep=2',
        );
        return Response(
          requestOptions: r,
          statusCode: 200,
          data: {'ok': true, 'video_url': url},
        );
      });
      final server = fake(
        (r) => Response(
          requestOptions: r,
          statusCode: 202,
          data: {
            'success': true,
            'data': {'ready': false, 'client_resolve': descriptor},
          },
        ),
      );
      final api = NetwixApi(
        dio: server,
        token: 'private-member-token',
        sourceResolver: RongYokClientResolver(dio: upstream),
      );
      final result = await api.resolveSource(1);
      expect(result?.url, url);
      expect(result?.ready, isTrue);
      expect(called, 1);
    },
  );

  test(
    'paywall cannot trigger client resolution even with a descriptor',
    () async {
      var called = 0;
      final upstream = fake((r) {
        called++;
        throw StateError('unexpected');
      });
      final server = fake(
        (r) => Response(
          requestOptions: r,
          statusCode: 403,
          data: {
            'success': false,
            'data': {
              'ready': false,
              'error': 'pro_required',
              'client_resolve': descriptor,
            },
          },
        ),
      );
      final api = NetwixApi(
        dio: server,
        sourceResolver: RongYokClientResolver(dio: upstream),
      );
      expect((await api.resolveSource(1))?.isLocked, isTrue);
      expect(called, 0);
    },
  );

  test('untrusted descriptor never initiates a request', () async {
    var called = 0;
    final resolver = RongYokClientResolver(
      dio: fake((r) {
        called++;
        throw StateError('unexpected');
      }),
    );
    expect(
      await resolver.resolve({...descriptor, 'endpoint': '../../private.php'}),
      isNull,
    );
    expect(
      await resolver.resolve({
        ...descriptor,
        'series_id': '1&url=https://127.0.0.1',
      }),
      isNull,
    );
    expect(called, 0);
  });

  test('video destinations and expired signatures are rejected', () {
    expect(RongYokClientResolver.validVideoUrl(video()), isTrue);
    expect(RongYokClientResolver.validVideoUrl(video(seconds: -1)), isFalse);
    expect(
      RongYokClientResolver.validVideoUrl(
        video().replaceFirst(
          'cdn.discordapp.com',
          'cdn.discordapp.com.evil.test',
        ),
      ),
      isFalse,
    );
    expect(
      RongYokClientResolver.validVideoUrl(
        video().replaceFirst('https://', 'https://user:pass@'),
      ),
      isFalse,
    );
  });

  test('rotated endpoint is discovered on the device', () async {
    final resolver = RongYokClientResolver(
      dio: fake((r) {
        if (r.uri.path.endsWith('watch.js')) {
          return Response(
            requestOptions: r,
            statusCode: 200,
            data: 'fetch(`/watch/rotated123.php?series_id=1&ep=2`)',
          );
        }
        return Response(
          requestOptions: r,
          statusCode: 200,
          data: r.uri.path.endsWith('rotated123.php')
              ? {'ok': true, 'video_url': video()}
              : {'ok': false},
        );
      }),
    );
    expect(await resolver.resolve(descriptor), isNotNull);
  });
}
