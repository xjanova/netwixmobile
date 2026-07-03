import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../services/auth_service.dart';
import '../services/reward_config.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/referral_promo_card.dart';
import 'reward_watch_screen.dart';

/// หาเหรียญ · Earn coins — the activities I defined (backend can add more).
class EarnCoinsScreen extends StatelessWidget {
  const EarnCoinsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l.bi('หาเหรียญ', 'Earn coins'), style: AppTheme.display(18, weight: FontWeight.w700)),
      ),
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _balance(l, member),
            const SizedBox(height: 18),

            // ⭐ Headline promo: invite 3 qualified friends → 2 months Pro free.
            ReferralPromoCard(onShare: () => _shareReferral(context, member, l)),

            if (!member.isLoggedIn) _loginCard(context, l),

            _activity(
              icon: Icons.event_available_rounded,
              title: l.bi('เช็คอินรายวัน', 'Daily check-in'),
              sub: l.pick('รับทุกวัน', 'Once per day'),
              coins: RewardConfig.dailyCheckin,
              done: member.checkedInToday,
              actionLabel: member.checkedInToday ? l.pick('รับแล้ววันนี้', 'Claimed') : l.pick('เช็คอิน', 'Check in'),
              onTap: member.checkedInToday
                  ? null
                  : () async {
                      final got = await member.dailyCheckIn();
                      if (context.mounted && got > 0) _toast(context, '+$got ${l.pick('เหรียญ', 'coins')}');
                    },
            ),
            _activity(
              icon: Icons.smart_display_rounded,
              title: l.bi('ดูคลิปรับรางวัล', 'Watch a reward clip'),
              sub: '${member.rewardWatchesToday}/${RewardConfig.rewardWatchDailyMax} ${l.pick('วันนี้', 'today')} · ${RewardConfig.rewardWatchSeconds}s',
              coins: RewardConfig.rewardWatchCoins,
              done: !member.canRewardWatch,
              actionLabel: member.canRewardWatch ? l.pick('ดูเลย', 'Watch') : l.pick('ครบวันนี้', 'Maxed'),
              onTap: member.canRewardWatch
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RewardWatchScreen()))
                  : null,
            ),
            _activity(
              icon: Icons.group_add_rounded,
              title: l.bi('ชวนเพื่อน', 'Invite friends'),
              sub: l.pick('เพื่อนสมัครผ่านโค้ดเรา', 'Friend signs up with your code'),
              coins: RewardConfig.referralSignupBonus,
              actionLabel: l.pick('แชร์', 'Share'),
              onTap: () => _shareReferral(context, member, l),
            ),
            _activity(
              icon: Icons.playlist_play_rounded,
              title: l.bi('ดูครบ 5 ตอนใน 1 วัน', 'Watch 5 episodes today'),
              sub: l.pick('รับอัตโนมัติเมื่อครบ', 'Auto-granted'),
              coins: RewardConfig.watchFiveDaily,
              actionLabel: l.pick('อัตโนมัติ', 'Auto'),
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _balance(L10n l, MemberState member) {
    return GlassCard(
      child: Row(
        children: [
          const HexIcon(icon: Icons.monetization_on_rounded, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.bi('เหรียญของฉัน', 'My coins'),
                    style: AppTheme.body(12.5, color: T.textMuted)),
                Text('${member.coins}',
                    style: AppTheme.display(26, weight: FontWeight.w700, color: T.accent)),
              ],
            ),
          ),
          Text('1 ${l.pick('ตอน', 'ep')} = ${RewardConfig.unlockCost} ${l.pick('เหรียญ', 'coins')}',
              style: AppTheme.body(11.5, color: T.textFaint)),
        ],
      ),
    );
  }

  Widget _loginCard(BuildContext context, L10n l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.accentGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.pick('เข้าสู่ระบบครั้งแรก รับ 10 เหรียญฟรี', 'Sign in — get 10 free coins'),
              style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _loginBtn(context, 'Google', Icons.g_mobiledata_rounded, AuthProvider.google)),
            const SizedBox(width: 10),
            Expanded(child: _loginBtn(context, 'LINE', Icons.chat_bubble_rounded, AuthProvider.line)),
          ]),
        ],
      ),
    );
  }

  Widget _loginBtn(BuildContext context, String label, IconData icon, AuthProvider p) {
    return GestureDetector(
      onTap: () => context.read<MemberState>().login(p),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: T.accentGradient,
          borderRadius: BorderRadius.circular(T.rButton),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: T.onAccent),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.body(13, weight: FontWeight.w700, color: T.onAccent)),
        ]),
      ),
    );
  }

  Widget _activity({
    required IconData icon,
    required String title,
    required String sub,
    required int coins,
    required String actionLabel,
    required VoidCallback? onTap,
    bool done = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: T.glass(),
      child: Row(
        children: [
          HexIcon(icon: icon, size: 40, color: done ? T.textFaint : T.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                Text(sub, style: AppTheme.body(11.5, color: T.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+$coins', style: AppTheme.display(15, weight: FontWeight.w700, color: T.accent)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: onTap == null ? const Color(0x14FFFFFF) : T.accentSoft,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: onTap == null ? T.hairline : T.accentGlow),
                  ),
                  child: Text(actionLabel,
                      style: AppTheme.body(11.5,
                          weight: FontWeight.w600,
                          color: onTap == null ? T.textFaint : T.accent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _shareReferral(BuildContext context, MemberState member, L10n l) async {
    final code = member.referralCode;
    final link = member.shareLink;
    final months = member.referralRewardMonths;
    final text = l.pick(
      'มาดูซีรีส์ฟรีกับ NetWix! 🎬\n'
          'สมัครด้วยโค้ด $code แล้วดูให้จบ 1 ตอน — ชวนครบ 3 คน ฉันได้ Pro ฟรี $months เดือน 🎁\n$link',
      'Watch series free on NetWix! 🎬\n'
          'Sign up with code $code and finish 1 episode — 3 friends unlock $months months of Pro for me 🎁\n$link',
    );
    await SharePlus.instance.share(ShareParams(text: text));
    if (!context.mounted) return;
    final got = await member.awardShare();
    if (context.mounted && got > 0) _toast(context, '+$got ${l.pick('เหรียญ', 'coins')}');
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
