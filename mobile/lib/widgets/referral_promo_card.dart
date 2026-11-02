import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The live referral rules, with no client-invented qualification or reward promise.
class ReferralPromoCard extends StatelessWidget {
  const ReferralPromoCard({super.key, this.onShare});
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();
    final days = member.inviterProDays;
    final coins = member.referralSignupCoins;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.accentGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.pick('ชวนเพื่อนมาดูด้วยกัน', 'Invite friends to watch'),
            style: AppTheme.body(
              16,
              weight: FontWeight.w700,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.pick(
              'เพื่อนใช้โค้ดสำเร็จ รับ $coins เหรียญตามกติกาปัจจุบัน · Pro $days วัน และโบนัสตามแคมเปญ',
              'Successful referral: $coins coins · $days Pro days and campaign bonuses',
            ),
            style: AppTheme.body(12.5, color: T.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.pick(
                    'เพื่อนตอบรับแล้ว ${member.referralQualified} คน',
                    '${member.referralQualified} accepted invitations',
                  ),
                  style: AppTheme.body(12.5, color: T.textMuted),
                ),
              ),
              TextButton(
                onPressed: member.isLoggedIn ? onShare : null,
                child: Text(l.pick('ชวนเพื่อน', 'Invite')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
