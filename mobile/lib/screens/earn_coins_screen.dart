import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/mission.dart';
import '../services/auth_service.dart';
import '../services/format.dart';
import '../services/reward_config.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/common.dart';
import '../widgets/referral_promo_card.dart';
import 'mission_watch_screen.dart';
import 'reward_watch_screen.dart';
import 'team_screen.dart';

/// หาเหรียญ · Earn coins — the activities I defined (backend can add more).
class EarnCoinsScreen extends StatefulWidget {
  const EarnCoinsScreen({super.key, this.embedded = false});

  /// True when hosted as a bottom-nav tab (no back button).
  final bool embedded;

  @override
  State<EarnCoinsScreen> createState() => _EarnCoinsScreenState();
}

class _EarnCoinsScreenState extends State<EarnCoinsScreen> {
  bool get embedded => widget.embedded;

  @override
  void initState() {
    super.initState();
    // Server missions + live campaign rules (safe for guests — missions no-op).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final member = context.read<MemberState>();
      member.refreshMissions();
      member.refreshCampaignConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !embedded,
        title: Text(l.bi('หาเหรียญ', 'Earn coins'), style: AppTheme.display(18, weight: FontWeight.w700)),
      ),
      body: AmbientBackdrop(
        asset: 'assets/art/rewards-bg.webp',
        alignment: Alignment.bottomCenter,
        // Heavier scrim than onboarding: this screen is a dense list of cards and numbers, so the
        // art has to stay atmosphere and never become texture behind text.
        scrim: 0.62,
        opacity: 0.85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _balance(l, member),
            const SizedBox(height: 18),

            // ⭐ Headline promo: invite 3 qualified friends → 2 months Pro free.
            ReferralPromoCard(onShare: () => _shareReferral(context, member, l)),

            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TeamScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: T.hairline),
                ),
                child: Row(children: [
                  const Icon(Icons.groups_rounded, color: T.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.bi('ทีมของฉัน / สายงาน', 'My Team'),
                          style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
                      Text(l.pick('ดูลูกทีมและเหรียญปันผล', 'Downline & dividend coins'),
                          style: AppTheme.body(11.5, color: T.textMuted)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: T.textMuted),
                ]),
              ),
            ),

            if (!member.isLoggedIn) _loginCard(context, l, member),

            // ---- ภารกิจพิเศษจากเซิร์ฟเวอร์ (แอดมินกำหนด — ดูคลิปครบเวลารับเหรียญ) ----
            if (member.isLoggedIn && member.missions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                child: Text(l.bi('ภารกิจพิเศษ', 'Missions'),
                    style: AppTheme.display(16, weight: FontWeight.w700)),
              ),
              for (final m in member.missions) _missionCard(context, l, m),
            ],

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${member.coins}',
                        style: AppTheme.display(26, weight: FontWeight.w700, color: T.accent)),
                    if (member.goldCoins > 0) ...[
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('🥇 ${member.goldCoins} ${l.pick('ทอง', 'gold')}',
                            style: AppTheme.body(12.5, weight: FontWeight.w700, color: const Color(0xFFF5C542))),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text('1 ${l.pick('ตอน', 'ep')} = ${RewardConfig.unlockCost} ${l.pick('เหรียญ', 'coins')}',
              style: AppTheme.body(11.5, color: T.textFaint)),
        ],
      ),
    );
  }

  /// One server mission — tap opens the watch flow; the reward is granted
  /// server-side the moment the validated watch-time is reached.
  Widget _missionCard(BuildContext context, L10n l, MissionItem m) {
    final done = m.earned;
    final sub = [
      '${m.requiredSeconds}s',
      if (m.isDaily) l.pick('รายวัน', 'daily') else l.pick('ครั้งเดียว', 'once'),
      if (m.description != null && m.description!.isNotEmpty) m.description!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: T.glass(),
      child: Row(
        children: [
          HexIcon(
              icon: m.isYoutube ? Icons.smart_display_rounded : Icons.movie_rounded,
              size: 40,
              color: done ? T.textFaint : (m.isGold ? const Color(0xFFF5C542) : T.accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(11.5, color: T.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+${m.rewardAmount}${m.isGold ? ' 🥇' : ''}',
                  style: AppTheme.display(15,
                      weight: FontWeight.w700,
                      color: m.isGold ? const Color(0xFFF5C542) : T.accent)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: done ? null : () => _openMission(context, m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: done ? const Color(0x14FFFFFF) : T.accentSoft,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: done ? T.hairline : T.accentGlow),
                  ),
                  child: Text(
                      done
                          ? (m.isDaily ? l.pick('รับแล้ววันนี้', 'Claimed today') : l.pick('สำเร็จแล้ว', 'Done'))
                          : l.pick('ดูเลย', 'Watch'),
                      style: AppTheme.body(11.5,
                          weight: FontWeight.w600, color: done ? T.textFaint : T.accent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMission(BuildContext context, MissionItem m) async {
    final earned = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => MissionWatchScreen(mission: m)));
    if (!context.mounted) return;
    if (earned == true) _toast(context, '🎉 +${m.rewardLabel}');
    // Statuses may have changed either way (attempt persisted server-side).
    await context.read<MemberState>().refreshMissions();
  }

  Widget _loginCard(BuildContext context, L10n l, MemberState member) {
    // Headline follows the LIVE campaign (same source as the web marquee):
    // free-Pro signup window when it's on, else the classic coin bonus.
    final freeDays = member.signupFreeProDays;
    final headline = freeDays > 0
        ? l.pick('สมัครใหม่วันนี้ รับ Premium ฟรี ${Format.humanDays(freeDays)}! 🎁',
            'Sign up today — ${Format.humanDays(freeDays, thai: false)} of free Premium! 🎁')
        : l.pick('เข้าสู่ระบบครั้งแรก รับ 10 เหรียญฟรี', 'Sign in — get 10 free coins');

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
          Text(headline,
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
