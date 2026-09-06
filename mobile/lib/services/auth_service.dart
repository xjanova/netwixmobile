import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../models/member.dart';
import 'debug_reporter.dart';
import 'netwix_api.dart';

enum AuthProvider { google, line, email }

extension AuthProviderX on AuthProvider {
  String? get query => switch (this) {
        AuthProvider.google => 'google',
        AuthProvider.line => 'line',
        AuthProvider.email => null,
      };
  String get label => switch (this) {
        AuthProvider.google => 'Google',
        AuthProvider.line => 'LINE',
        AuthProvider.email => 'อีเมล',
      };
}

class AuthResult {
  const AuthResult(this.member);
  final Member member;
}

/// Thrown when the user dismisses the in-app browser without finishing.
class AuthCancelled implements Exception {}

/// Sign-in that reuses the NetWix **web** login (Google / LINE / email). Opens
/// `/mauth/start` in an in-app browser tab, lets the user authenticate on the
/// site, then captures the `netwix://auth?code=…` deep link and exchanges the
/// one-time code for a bearer token. No native OAuth client / SDK needed.
class AuthService {
  AuthService(this._api);
  final NetwixApi _api;

  static const String _callbackScheme = 'netwix';

  /// PKCE. The login code comes back over `netwix://`, a scheme ANY installed app may also
  /// register — and Android will let one of them take the redirect. One-time use is no defence when
  /// the thief redeems first. So the exchange is bound to a secret that never leaves this process:
  /// only its SHA-256 goes out with the sign-in, and a stolen code is worth nothing without it.
  static (String verifier, String challenge) _pkce() {
    final rnd = Random.secure();
    final verifier =
        base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge =
        base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    return (verifier, challenge);
  }

  Future<AuthResult> signIn(AuthProvider provider) async {
    final q = provider.query;
    final p = q ?? 'email';
    final (verifier, challenge) = _pkce();
    final url = '${NetwixApi.origin}/mauth/start'
        '?cc=$challenge${q != null ? '&provider=$q' : ''}';

    // Diagnostics carry only the provider + step + error text — never the
    // one-time code or the bearer token.
    unawaited(debugReport('auth.start', context: {'provider': p}));

    final String callback;
    try {
      callback = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: _callbackScheme,
      );
    } catch (e) {
      // The plugin throws on user-cancel (tab closed) AND on a real failure —
      // we can't tell them apart, so report the raw error for analysis.
      if (kDebugMode) debugPrint('web auth cancelled/failed: $e');
      unawaited(debugReport('auth.webauth_fail',
          level: 'warn', message: e.toString(), context: {'provider': p}));
      throw AuthCancelled();
    }

    final code = Uri.tryParse(callback)?.queryParameters['code'];
    if (code == null || code.isEmpty) {
      unawaited(debugReport('auth.no_code',
          level: 'error',
          message: 'callback had no code',
          context: {'provider': p, 'callback_len': callback.length}));
      throw Exception('ไม่ได้รับรหัสยืนยันจากการเข้าสู่ระบบ');
    }
    unawaited(debugReport('auth.callback', context: {'provider': p, 'has_code': true}));

    final data = await _api.exchangeCode(code, verifier: verifier);
    final token = data?['token'] as String?;
    final user = data?['user'];
    if (token == null || user is! Map) {
      unawaited(debugReport('auth.exchange_fail',
          level: 'error', context: {'provider': p, 'got_data': data != null}));
      throw Exception('แลกรหัสเข้าสู่ระบบไม่สำเร็จ');
    }

    unawaited(debugReport('auth.success', context: {'provider': p}));
    return AuthResult(Member.fromNetwixUser(user.cast<String, dynamic>(), token: token));
  }
}
