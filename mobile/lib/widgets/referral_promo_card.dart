import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';

/// โปรชวนเพื่อน — "invite [target] friends who qualify → [rewardMonths] months of
/// Pro, free, once." Progress and the Pro grant are decided on the server; this
/// card only reflects what [MemberState] reports.
class ReferralPromoCard extends StatelessWidget {
  const ReferralPromoCard({super.key, this.onShare});

  /// Invoked when the user taps "ชวนเพื่อน" (share the invite). Null disables it.
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final m = context.watch<MemberState>();

    final target = m.referralTarget;
    final done = m.referralQualified.clamp(0, target);
    final months = m.referralRewardMonths;
    final until = m.proUntil;
    final proActive = m.isPro && until != null && until.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FF2D55), Color(0x22B026FF)],
        ),
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.accentGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GemCrest(size: 46, icon: Icons.workspace_premium_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.pick('ชวนครบ $target คน รับ Pro ฟรี $months เดือน',
                          'Invite $target friends — $months months of Pro free'),
                      style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.pick('เพื่อนสมัคร + ดูจบ 1 ตอน = นับ 1 คน',
                          'Each friend who signs up & finishes 1 episode counts'),
                      style: AppTheme.body(11.5, color: T.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (proActive)
            _proBadge(l, until)
          else ...[
            _progressDots(done, target),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    done >= target
                        ? l.pick('ครบแล้ว! กำลังเปิดสิทธิ์ Pro ให้…', 'Complete! Unlocking your Pro…')
                        : l.pick('ชวนอีก ${target - done} คน · แล้ว $done/$target',
                            '${target - done} more · $done/$target so far'),
                    style: AppTheme.body(12.5, weight: FontWeight.w700, color: T.accent),
                  ),
                ),
                const SizedBox(width: 8),
                _shareButton(context, l, m),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _progressDots(int done, int target) => Row(
        children: [
          for (int i = 0; i < target; i++) ...[
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: i < done ? T.accentGradient : null,
                  color: i < done ? null : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            if (i < target - 1) const SizedBox(width: 6),
          ],
        ],
      );

  Widget _shareButton(BuildContext context, L10n l, MemberState m) {
    final enabled = m.isLoggedIn && onShare != null;
    return GestureDetector(
      onTap: enabled ? onShare : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: enabled ? T.accentGradient : null,
          color: enabled ? null : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(100),
          border: enabled ? null : Border.all(color: T.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share_rounded, size: 15, color: enabled ? T.onAccent : T.textFaint),
            const SizedBox(width: 6),
            Text(
              m.isLoggedIn ? l.pick('ชวนเพื่อน', 'Invite') : l.pick('เข้าสู่ระบบก่อน', 'Sign in first'),
              style: AppTheme.body(12.5,
                  weight: FontWeight.w700, color: enabled ? T.onAccent : T.textFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proBadge(L10n l, DateTime until) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = '${two(until.day)}/${two(until.month)}/${until.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.accentGlow),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: T.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.pick('ปลดล็อก Pro ฟรีแล้ว · ถึง $d', 'Pro unlocked free · until $d'),
              style: AppTheme.body(13, weight: FontWeight.w700, color: T.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
