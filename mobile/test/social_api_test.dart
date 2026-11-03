import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netwix/services/netwix_api.dart';

/// The like / comment calls behind the Shorts + player rail, against the same envelope the web
/// serves (`/api/app/content/{id}/*`).
NetwixApi _api(Map<String, dynamic> Function(RequestOptions o) reply, {int status = 200, String? token}) {
  final dio = Dio(BaseOptions(baseUrl: NetwixApi.baseUrl));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    if (status != 200) {
      h.reject(DioException(
          requestOptions: o, response: Response(requestOptions: o, statusCode: status), type: DioExceptionType.badResponse));
      return;
    }
    h.resolve(Response(requestOptions: o, statusCode: 200, data: {'success': true, 'data': reply(o)}));
  }));
  return NetwixApi(dio: dio, token: token);
}

void main() {
  test('guest state carries the public counts with no liked flag', () async {
    final st = await _api((_) => {'liked': false, 'in_list': false, 'my_rating': null, 'likes_count': 12, 'comments_count': 4})
        .fetchContentState(9);
    expect(st!.liked, isFalse);
    expect(st.likesCount, 12);
    expect(st.commentsCount, 4);
  });

  test('comment list returns the server total, not just the capped page', () async {
    final res = await _api((o) {
      expect(o.path, '/content/9/comments');
      return {
        'items': [
          {'id': 1, 'author': 'ผู้ชม', 'avatar_color': '#ff2d55', 'initial': 'ผ', 'text': 'สนุก', 'created_at': '2026-11-03T03:00:00+07:00', 'ago': '1 นาทีที่แล้ว'},
        ],
        'count': 140,
      };
    }).fetchCommentList(9);
    expect(res!.items.single.text, 'สนุก');
    expect(res.count, 140);
  });

  test('an offline comment list is null, so the sheet can offer a retry', () async {
    expect(await _api((_) => {}, status: 500).fetchCommentList(9), isNull);
    expect(await _api((_) => {}, status: 500).fetchComments(9), isEmpty);
  });

  test('a like that the server refuses comes back null (the rail rolls back)', () async {
    expect(await _api((_) => {}, status: 429, token: 't').toggleLike(9), isNull);
    final ok = await _api((_) => {'liked': true, 'likes_count': 13}, token: 't').toggleLike(9);
    expect(ok!.liked, isTrue);
    expect(ok.likesCount, 13);
  });

  test('a rate-limited comment post is null, not a phantom comment', () async {
    expect(await _api((_) => {}, status: 429, token: 't').postComment(9, 'สวัสดี'), isNull);
  });
}
