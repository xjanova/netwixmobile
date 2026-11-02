import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/mission.dart';
import '../models/reward_campaign.dart';
import '../services/auth_service.dart';
import '../services/format.dart';
import '../services/reward_config.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/icon3d.dart';
import '../widgets/referral_promo_card.dart';
import 'catalog_grid_screen.dart';
import 'mission_watch_screen.dart';
import 'reward_watch_screen.dart';
import 'team_screen.dart';

/// หาเหรียญ · Earn coins — the web's /missions page in the app: the shared bonus campaigns,
/// the admin's clip missions and the base earn rules, all read from the server's config.
class EarnCoinsScreen extends StatefulWidget {
  const EarnCoinsScreen({super.key, this.embedded = false});

  /// True when hosted as a bottom-nav tab (no back button).
  final bool embedded;

  @override
  State<EarnCoinsScreen> createState() => _EarnCoinsScreenState();
}

class _EarnCoinsScreenState extends State<EarnCoinsScreen> {
  bool get embedded => widget.embedded;

  /// Guards the check-in button against a double tap while the request is in flight.
  bool _checkingIn = false;

  @override
  void initState() {
    super.initState();
    // Server missions + live campaign rules (safe for guests — missions no-op).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  Future<void> _refresh() async {
    final member = context.read<MemberState>();
    await Future.wait([
      member.refreshMissions(),
      member.refreshCampaignConfig(),
      member.refreshMembership(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !embedded,
        title: Text(l.bi('ภารกิจ & เหรียญ', 'Missions & coins'), style: AppTheme.display(18, weight: FontWeight.w700)),
      ),
      body: AmbientBackdrop(
        asset: 'assets/art/rewards-bg.webp',
        alignment: Alignment.bottomCenter,
        // Heavier scrim than onboarding: this screen is a dense list of cards and numbers, so the
        // art has to stay atmosphere and never become texture behind text.
        scrim: 0.62,
        opacity: 0.85,
        child: RefreshIndicator(
          color: T.accent,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _hero(context, l, member),
              const SizedBox(height: 16),
              if (!member.isLoggedIn) _loginCard(context, l, member),

              if (member.isLoggedIn && member.campaigns.isNotEmpty) ...[
                _sectionTitle(
                  l.bi('${member.campaigns.length} แคมเปญ · ดูเพลินรับโบนัส', 'Explore & earn bonuses'),
                  l.pick('เว็บและแอปนับรวมกัน · โบนัสเพิ่มจากเหรียญปกติ · รีเซ็ตเวลาไทย',
                      'Shared with the web · Extra bonus coins · Resets in Bangkok time'),
                  trailing: _completedPill(l, member.campaigns),
                ),
                for (final campaign in member.campaigns) _campaignCard(context, l, member, campaign),
              ],

              // ---- ภารกิจพิเศษจากเซิร์ฟเวอร์ (แอดมินกำหนด — ดูคลิปครบเวลารับเหรียญ) ----
              if (member.isLoggedIn && member.missions.isNotEmpty) ...[
                _sectionTitle(l.bi('ภารกิจดูคลิปพิเศษ', 'Clip missions'),
                    l.pick('ดูคลิปครบเวลา รับเหรียญทันที', 'Watch the full clip, get coins right away')),
                for (final m in member.missions) _missionCard(context, l, m),
              ],

              _sectionTitle(l.bi('รับเหรียญพื้นฐาน', 'Everyday coins'),
                  l.pick('อัตราตามที่ตั้งไว้บนเว็บ', 'Rates set on the web')),
              _activity(
                icon: Ic3.checkin,
                title: l.bi('เช็คอินรายวัน', 'Daily check-in'),
                sub: l.pick('รับทุกวัน', 'Once per day'),
                coins: member.dailyBaseCoins,
                done: member.checkedInToday,
                actionLabel: member.checkedInToday ? l.pick('รับแล้ว', 'Claimed') : l.pick('เช็คอิน', 'Check in'),
                onTap: member.checkedInToday ? null : () => _checkIn(context, l, member),
              ),
              _activity(
                icon: Ic3.clip,
                title: l.bi('ดูคลิปรับรางวัล', 'Watch a reward clip'),
                sub: '${member.rewardWatchesToday}/${member.watchDailyCap} ${l.pick('วันนี้', 'today')} · ${RewardConfig.rewardWatchSeconds}s',
                coins: member.watchBaseCoins,
                done: !member.canRewardWatch,
                actionLabel: member.canRewardWatch ? l.pick('ดูเลย', 'Watch') : l.pick('ครบวันนี้', 'Maxed'),
                onTap: member.canRewardWatch
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RewardWatchScreen()))
                    : null,
              ),
              _activity(
                icon: Ic3.friends,
                title: l.bi('ชวนเพื่อน', 'Invite friends'),
                sub: l.pick('เพื่อนสมัครและใช้โค้ดของเรา', 'A friend signs up with your code'),
                coins: member.referralSignupCoins,
                actionLabel: l.pick('แชร์', 'Share'),
                onTap: member.isLoggedIn ? () => _shareReferral(context, member, l) : null,
              ),
              _earnRulesNote(l, member),

              const SizedBox(height: 18),
              ReferralPromoCard(onShare: () => _shareReferral(context, member, l)),
              _teamLink(context, l),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ hero

  Widget _hero(BuildContext context, L10n l, MemberState member) {
    final checked = member.checkedInToday;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A0F2A), Color(0xFF1B0B2E), Color(0xFF120A1E)],
        ),
        border: Border.all(color: const Color(0x40FF6B85)),
        boxShadow: const [
          BoxShadow(color: Color(0x55FF2D55), blurRadius: 34, offset: Offset(0, 14), spreadRadius: -18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.bi('เหรียญเงินของฉัน', 'My silver coins'),
                        style: AppTheme.body(12.5, color: T.textSecondary)),
                    const SizedBox(height: 2),
                    ShaderMask(
                      shaderCallback: (r) => T.accentGradient.createShader(r),
                      child: Text(Format.grouped(member.coins),
                          style: AppTheme.display(38, weight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _chip('🥇 ${member.goldCoins} ${l.pick('ทอง', 'gold')}', const Color(0xFFF5C542)),
                      _chip('1 ${l.pick('ตอน', 'ep')} = ${member.unlockCost} ${l.pick('เหรียญ', 'coins')}', T.textSecondary),
                    ]),
                  ],
                ),
              ),
              const Icon3D(Ic3.coins, size: 96, tile: false),
            ],
          ),
          if (member.isLoggedIn) ...[
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: checked || _checkingIn ? null : () => _checkIn(context, l, member),
                child: Ink(
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: checked ? null : T.accentGradient,
                    color: checked ? const Color(0x14FFFFFF) : null,
                    borderRadius: BorderRadius.circular(14),
                    border: checked ? Border.all(color: T.hairlineStrong) : null,
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_checkingIn)
                      const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      Icon(checked ? Icons.check_circle_rounded : Icons.event_available_rounded,
                          size: 19, color: checked ? const Color(0xFF4ADE80) : T.onAccent),
                    const SizedBox(width: 8),
                    Text(
                      checked
                          ? l.pick('เช็คอินวันนี้แล้ว · กลับมาใหม่พรุ่งนี้', 'Checked in today · back tomorrow')
                          : l.pick('เช็คอินวันนี้ รับ +${member.dailyBaseCoins} เหรียญ',
                              'Check in today · +${member.dailyBaseCoins} coins'),
                      style: AppTheme.body(13.5,
                          weight: FontWeight.w700, color: checked ? T.textSecondary : T.onAccent),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: T.hairlineStrong),
        ),
        child: Text(text, style: AppTheme.body(11.5, weight: FontWeight.w600, color: color)),
      );

  Widget _sectionTitle(String title, String sub, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppTheme.display(16.5, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, style: AppTheme.body(11.5, color: T.textMuted)),
              ]),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _completedPill(L10n l, List<RewardCampaign> items) {
    final done = items.where((c) => c.earned).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: T.accentSoft, borderRadius: BorderRadius.circular(100)),
      child: Text('$done/${items.length} ${l.pick('สำเร็จ', 'done')}',
          style: AppTheme.body(11.5, weight: FontWeight.w700, color: T.accentHi)),
    );
  }

  // ------------------------------------------------------------- campaigns

  Widget _campaignCard(BuildContext context, L10n l, MemberState member, RewardCampaign c) {
    final ratio = c.target > 0 ? (c.progress / c.target).clamp(0.0, 1.0) : 0.0;
    final period = switch (c.repeat) {
      'weekly' => l.pick('รายสัปดาห์', 'Weekly'),
      'daily' => l.pick('รายวัน', 'Daily'),
      _ => l.pick('ครั้งเดียว', 'Once'),
    };
    final action = switch (c.kind) {
      'daily' => l.pick('เช็กอินเลย', 'Check in'),
      'referral' => l.pick('ชวนเพื่อน', 'Invite'),
      'share' => l.pick('แชร์เลย', 'Share'),
      _ => l.pick('ไปสำรวจ', 'Explore'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: T.glass(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon3D(Ic3.forCampaign(c.kind), size: 54, done: c.earned),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(c.title,
                            style: AppTheme.body(15, weight: FontWeight.w700, color: T.textPrimary)),
                      ),
                      _coinBadge('+${c.coins}', muted: c.earned),
                    ]),
                    const SizedBox(height: 4),
                    Text(c.description, style: AppTheme.body(12, color: T.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _progressBar(ratio, done: c.earned),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${c.progress}/${c.target}', style: AppTheme.body(12, weight: FontWeight.w700, color: T.textSecondary)),
              Text('  ·  $period', style: AppTheme.body(12, color: T.textMuted)),
              const Spacer(),
              if (c.earned)
                Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4ADE80)),
                  const SizedBox(width: 4),
                  Text(l.pick('รับโบนัสแล้ว', 'Bonus claimed'),
                      style: AppTheme.body(12, weight: FontWeight.w600, color: const Color(0xFF4ADE80))),
                ])
              else
                _pillButton(action, () => _runCampaign(context, l, member, c)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runCampaign(BuildContext context, L10n l, MemberState member, RewardCampaign c) async {
    if (c.kind == 'daily') {
      await _checkIn(context, l, member);
    } else if (c.kind == 'share' || c.kind == 'referral') {
      await _shareReferral(context, member, l);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(l.pick('สำรวจเรื่องใหม่', 'Discover titles'))),
            body: const SafeArea(child: CatalogGridScreen()),
          ),
        ),
      );
    }
    if (!mounted) return;
    await member.refreshMissions();
  }

  Widget _progressBar(double ratio, {bool done = false}) => ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: SizedBox(
          height: 8,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: Color(0x1AFFFFFF))),
            FractionallySizedBox(
              widthFactor: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: done
                      ? const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF4ADE80)])
                      : T.accentGradient,
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _coinBadge(String text, {bool gold = false, bool muted = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          gradient: muted
              ? null
              : LinearGradient(
                  colors: gold
                      ? const [Color(0xFFFFD86B), Color(0xFFF5A524)]
                      : const [Color(0xFFFF6B85), Color(0xFFB026FF)]),
          color: muted ? const Color(0x14FFFFFF) : null,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(gold ? '$text 🥇' : '$text 🪙',
            style: AppTheme.body(12, weight: FontWeight.w800, color: muted ? T.textFaint : Colors.white)),
      );

  Widget _pillButton(String label, VoidCallback? onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: onTap == null ? null : T.accentGradient,
              color: onTap == null ? const Color(0x14FFFFFF) : null,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(label,
                style: AppTheme.body(12, weight: FontWeight.w700, color: onTap == null ? T.textFaint : T.onAccent)),
          ),
        ),
      );

  // -------------------------------------------------------------- missions

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
      decoration: T.glass(radius: 18),
      child: Row(
        children: [
          Icon3D(m.isGold ? Ic3.trophy : Ic3.clip, size: 50, done: done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(11.5, color: T.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _coinBadge('+${m.rewardAmount}', gold: m.isGold, muted: done),
              const SizedBox(height: 6),
              _pillButton(
                done
                    ? (m.isDaily ? l.pick('รับแล้ววันนี้', 'Claimed today') : l.pick('สำเร็จแล้ว', 'Done'))
                    : l.pick('ดูเลย', 'Watch'),
                done ? null : () => _openMission(context, m),
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

  // ------------------------------------------------------------ activities

  Widget _activity({
    required Ic3 icon,
    required String title,
    required String sub,
    required int coins,
    required String actionLabel,
    required VoidCallback? onTap,
    bool done = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: T.glass(radius: 18),
      child: Row(
        children: [
          Icon3D(icon, size: 46, done: done),
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
              _coinBadge('+$coins', muted: done),
              const SizedBox(height: 6),
              _pillButton(actionLabel, onTap),
            ],
          ),
        ],
      ),
    );
  }

  /// The like / comment / share rates the admin set — the same numbers the web pays.
  Widget _earnRulesNote(L10n l, MemberState member) {
    final r = member.socialEarnRules;
    String rule(String th, String en, ({int coins, int cap}) v) =>
        l.pick('$th +${v.coins} (สูงสุด ${v.cap}/วัน)', '$en +${v.coins} (max ${v.cap}/day)');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Text(
        [
          rule('กดถูกใจ', 'Like', r.like),
          rule('คอมเมนต์', 'Comment', r.comment),
          rule('แชร์', 'Share', r.share),
        ].join('  ·  '),
        style: AppTheme.body(11.5, color: T.textFaint),
      ),
    );
  }

  Widget _teamLink(BuildContext context, L10n l) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamScreen())),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: T.glass(radius: 18),
            child: Row(children: [
              const Icon3D(Ic3.profiles, size: 44),
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
      );

  // ----------------------------------------------------------------- guest

  Widget _loginCard(BuildContext context, L10n l, MemberState member) {
    // Headline follows the LIVE campaign (same source as the web marquee):
    // free-Pro signup window when it's on, else the classic coin bonus.
    final freeDays = member.signupFreeProDays;
    final bonus = member.signupBonusCoins;
    final headline = freeDays > 0
        ? l.pick('สมัครใหม่วันนี้ รับ Premium ฟรี ${Format.humanDays(freeDays)}! 🎁',
            'Sign up today — ${Format.humanDays(freeDays, thai: false)} of free Premium! 🎁')
        : l.pick('เข้าสู่ระบบครั้งแรก รับ $bonus เหรียญฟรี', 'Sign in — get $bonus free coins');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: T.accentGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon3D(Ic3.gift, size: 56, tile: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline, style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    l.pick('ภารกิจและเหรียญนับรวมกับบัญชีบนเว็บ', 'Missions and coins are shared with your web account'),
                    style: AppTheme.body(11.5, color: T.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
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

  // --------------------------------------------------------------- actions

  Future<void> _checkIn(BuildContext context, L10n l, MemberState member) async {
    if (_checkingIn) return;
    setState(() => _checkingIn = true);
    final got = await member.dailyCheckIn();
    if (!mounted) return;
    setState(() => _checkingIn = false);
    if (!context.mounted) return;
    _toast(context, got > 0 ? '+$got ${l.pick('เหรียญ', 'coins')}' : l.pick('รับรางวัลรอบนี้แล้ว', 'Already claimed'));
    await member.refreshMissions();
  }

  Future<void> _shareReferral(
    BuildContext context,
    MemberState member,
    L10n l,
  ) async {
    if (!member.isLoggedIn) return;
    final code = member.referralCode;
    final link = member.shareLink;
    final days = member.referralProDays;
    final text = l.pick(
      'มาดูซีรีส์ฟรีกับ NetWix! 🎬\n'
          'สมัครด้วยโค้ด $code${days > 0 ? ' รับ Pro ฟรี $days วัน' : ''} และรับสิทธิ์ตามแคมเปญ 🎁\n$link',
      'Watch series free on NetWix! 🎬\n'
          'Sign up with code $code${days > 0 ? ' for $days free Pro days' : ''} and campaign rewards 🎁\n$link',
    );
    final shared = await SharePlus.instance.share(ShareParams(text: text));
    if (shared.status != ShareResultStatus.success) return;
    if (!context.mounted) return;
    final got = await member.awardShare();
    if (context.mounted && got > 0) {
      _toast(context, '+$got ${l.pick('เหรียญ', 'coins')}');
    }
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
