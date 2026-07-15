import 'dart:convert';

import 'package:characters/characters.dart';

/// A signed-in member. Backed by netwix.online once live; until then a local
/// guest/session record persisted on-device.
class Member {
  const Member({
    required this.id,
    required this.name,
    this.avatar,
    this.email,
    this.provider = 'guest',
    this.referralCode = '',
    this.token,
    this.isPro = false,
    this.proUntil,
  });

  final String id;
  final String name;
  final String? avatar;
  final String? email;

  /// 'google' | 'line' | 'email' | 'guest'
  final String provider;

  /// The member's own code to invite friends.
  final String referralCode;

  /// NetWix app bearer token (null while guest).
  final String? token;

  /// Server plan is a paid tier (ad-free). This is the source of truth — a
  /// referral-granted free Pro also sets it to true (with [proUntil]).
  final bool isPro;

  /// When the current Pro expires (null = no expiry / not Pro). Used to show
  /// "Pro free until dd/mm" for the referral promo; ad-gating just uses [isPro].
  final DateTime? proUntil;

  bool get isGuest => provider == 'guest';
  bool get isLoggedIn => provider != 'guest';
  bool get proActive => isPro && (proUntil == null || proUntil!.isAfter(DateTime.now()));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'email': email,
        'provider': provider,
        'referral_code': referralCode,
        'token': token,
        'is_pro': isPro,
        'pro_until': proUntil?.toIso8601String(),
      };

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: '${j['id'] ?? ''}',
        name: (j['name'] as String?) ?? 'สมาชิก',
        avatar: j['avatar'] as String?,
        email: j['email'] as String?,
        provider: (j['provider'] as String?) ?? 'guest',
        referralCode: (j['referral_code'] ?? j['referralCode'] ?? '') as String,
        token: j['token'] as String?,
        isPro: j['is_pro'] == true,
        proUntil: _date(j['pro_until'] ?? j['pro_expires_at']),
      );

  /// Build from the `/api/app/auth/me` (or exchange) user payload + token.
  factory Member.fromNetwixUser(Map<String, dynamic> u, {String? token}) => Member(
        id: '${u['id'] ?? ''}',
        name: (u['name'] as String?) ?? 'สมาชิก',
        avatar: u['avatar'] as String?,
        email: u['email'] as String?,
        // server sends null provider for email/password accounts
        provider: (u['provider'] as String?) ?? 'email',
        token: token,
        isPro: u['is_pro'] == true,
        proUntil: _date(u['pro_until'] ?? u['pro_expires_at']),
      );

  static DateTime? _date(dynamic v) =>
      (v == null || '$v'.isEmpty) ? null : DateTime.tryParse('$v')?.toLocal();

  String encode() => jsonEncode(toJson());
  static Member? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return Member.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Member copyWith(
          {String? name,
          String? avatar,
          String? referralCode,
          String? token,
          bool? isPro,
          DateTime? proUntil}) =>
      Member(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        email: email,
        provider: provider,
        referralCode: referralCode ?? this.referralCode,
        token: token ?? this.token,
        isPro: isPro ?? this.isPro,
        proUntil: proUntil ?? this.proUntil,
      );
}

/// A comment on a series (netwix.online-backed).
class Comment {
  const Comment({
    required this.id,
    required this.author,
    this.avatarColor,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String author;

  /// Profile tint as a `#rrggbb` string (`avatar_color` in the payload). The web
  /// renders comments as a colour+initial tile rather than a photo, so this is
  /// the whole avatar. Null → fall back to the accent colour.
  final String? avatarColor;

  final String text;

  /// Null when the server didn't send a parseable timestamp — the UI then just
  /// omits the "x นาทีที่แล้ว" line instead of inventing one (an unparsed date
  /// used to fall back to epoch 0, which would read as "55 years ago").
  final DateTime? createdAt;

  /// First character of the author's name, matching the web's `initial`.
  String get initial => author.trim().isEmpty ? '?' : author.trim().characters.first;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: '${j['id'] ?? ''}',
        author: (j['author'] ?? j['name'] ?? 'สมาชิก') as String,
        avatarColor: (j['avatar_color'] ?? j['color']) as String?,
        text: (j['text'] ?? j['body'] ?? '') as String,
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      );
}
