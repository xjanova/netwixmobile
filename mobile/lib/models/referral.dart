import '../services/netwix_api.dart';

/// The server's view of a member's referral programme + the launch promo:
/// **"invite [target] friends who qualify → [rewardMonths] months of Pro, free,
/// once."**
///
/// A friend counts as **qualified** on the SERVER only — they signed up with
/// this member's code, verified their account (email/phone), AND finished
/// watching at least one episode. The app never computes this; it only shows
/// what `GET /api/referral` reports, so the Pro perk can't be forged on-device
/// (fake signups, self-invites and re-installs are rejected server-side).
class ReferralStatus {
  const ReferralStatus({
    required this.code,
    this.qualified = 0,
    this.pending = 0,
    this.target = 3,
    this.rewardMonths = 2,
    this.claimed = false,
    this.proUntil,
    this.shareUrl,
  });

  /// This member's own invite code.
  final String code;

  /// Friends who fully qualified (signed up + verified + finished ≥1 episode).
  final int qualified;

  /// Friends who signed up but haven't qualified yet (still in progress).
  final int pending;

  /// Qualified friends needed to unlock the promo (default 3).
  final int target;

  /// Free-Pro months granted when [qualified] reaches [target] (default 2).
  final int rewardMonths;

  /// True once the one-time promo has been redeemed for this member.
  final bool claimed;

  /// When the referral-granted Pro expires (null if not granted yet).
  final DateTime? proUntil;

  /// Server-provided share link (falls back to the register page + ref code).
  final String? shareUrl;

  bool get unlocked => qualified >= target;
  int get remaining => (target - qualified).clamp(0, target);
  double get progress => target == 0 ? 0 : (qualified / target).clamp(0.0, 1.0);
  bool get proActive => proUntil != null && proUntil!.isAfter(DateTime.now());

  String get link =>
      (shareUrl != null && shareUrl!.isNotEmpty) ? shareUrl! : NetwixApi.referralUrl(code);

  factory ReferralStatus.fromJson(Map<String, dynamic> j) => ReferralStatus(
        code: '${j['code'] ?? j['referral_code'] ?? ''}',
        qualified: _int(j['qualified'] ?? j['count'] ?? j['confirmed']),
        pending: _int(j['pending']),
        target: _int(j['target'], 3),
        rewardMonths: _int(j['reward_months'] ?? j['months'], 2),
        claimed: j['claimed'] == true,
        proUntil: _date(j['pro_until'] ?? j['pro_expires_at']),
        shareUrl: (j['share_url'] ?? j['url']) as String?,
      );

  static int _int(dynamic v, [int fallback = 0]) =>
      v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);

  static DateTime? _date(dynamic v) =>
      (v == null || '$v'.isEmpty) ? null : DateTime.tryParse('$v')?.toLocal();
}
