import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/format.dart';
import '../services/settings_store.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/login_sheet.dart';
import 'earn_coins_screen.dart';
import 'go_pro_screen.dart';
import 'my_list_screen.dart';
import 'wallet_screen.dart';
import 'whats_new_screen.dart';

/// 07 — Menu / Settings · เมนู. Bilingual rows (Thai bold + English muted).
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.l;
    final member = context.watch<MemberState>();
    final effectivePro = member.isPro;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Text(l.bi('เมนู', 'Menu'), style: AppTheme.display(21, weight: FontWeight.w700)),
        const SizedBox(height: 16),
        _accountCard(context, app),
        const SizedBox(height: 12),
        _coinsRow(context, l),
        if (member.isLoggedIn && !effectivePro) ...[
          const SizedBox(height: 12),
          _referralPromoRow(context, l, member),
        ],
        const SizedBox(height: 16),
        _languageRow(context, app),
        const SizedBox(height: 8),
        _row(context, Icons.bookmark_rounded, 'รายการของฉัน', 'My List',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyListScreen()))),
        if (member.isLoggedIn)
          _row(context, Icons.account_balance_wallet_rounded, 'กระเป๋าเหรียญทอง', 'Gold wallet',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const WalletScreen()))),
        _row(context, Icons.notifications_rounded, 'การแจ้งเตือน', 'Notifications',
            onTap: () => _soon(context, l)),
        _row(context, Icons.system_update_rounded, 'อัปเดต', 'Updates',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatsNewScreen()))),
        _row(context, Icons.info_rounded, 'เกี่ยวกับ', 'About', onTap: () => _about(context, l)),
        const SizedBox(height: 20),
        if (!effectivePro) _upgradeBanner(context, l) else _proActiveBanner(l, member),
      ],
    );
  }

  Widget _referralPromoRow(BuildContext context, L10n l, MemberState member) {
    final done = member.referralQualified.clamp(0, member.referralTarget);
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EarnCoinsScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x33FF2D55), Color(0x22B026FF)],
          ),
          borderRadius: BorderRadius.circular(T.rCard),
          border: Border.all(color: T.accentGlow),
        ),
        child: Row(
          children: [
            const HexIcon(icon: Icons.workspace_premium_rounded, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.pick('ชวนครบ ${member.referralTarget} คน รับ Pro ฟรี ${member.referralRewardMonths} เดือน',
                        'Invite ${member.referralTarget} — ${member.referralRewardMonths} months Pro free'),
                    style: AppTheme.body(13.5, weight: FontWeight.w700, color: T.textPrimary),
                  ),
                  Text(l.pick('ชวนแล้ว $done/${member.referralTarget} คน', '$done/${member.referralTarget} invited'),
                      style: AppTheme.body(11.5, color: T.accent)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: T.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(BuildContext context, AppState app) {
    final l = app.l;
    final member = context.watch<MemberState>();

    if (!member.isLoggedIn) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const HexAvatar(size: 46, child: Icon(Icons.person_outline_rounded, color: T.accentHi, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.pick('ยังไม่ได้เข้าสู่ระบบ', 'Not signed in'),
                        style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary)),
                    Text(
                        member.signupFreeProDays > 0
                            ? l.pick(
                                'สมัครใหม่รับ Premium ฟรี ${Format.humanDays(member.signupFreeProDays)}! 🎁',
                                'Sign up — free Premium for ${Format.humanDays(member.signupFreeProDays, thai: false)}! 🎁')
                            : l.pick('เข้าสู่ระบบครั้งแรก รับ 10 เหรียญฟรี', 'Sign in — 10 free coins'),
                        style: AppTheme.body(11.5, color: T.accent)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => showLoginSheet(context),
              child: Container(
                height: 46,
                decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.login_rounded, size: 18, color: T.onAccent),
                  const SizedBox(width: 8),
                  Text(l.pick('เข้าสู่ระบบ', 'Sign in'),
                      style: AppTheme.body(14, weight: FontWeight.w700, color: T.onAccent)),
                ]),
              ),
            ),
          ],
        ),
      );
    }

    final m = member.member!;
    final pro = member.isPro;
    return GlassCard(
      child: Row(
        children: [
          const HexAvatar(size: 52, child: Icon(Icons.person, color: T.accentHi, size: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: AppTheme.body(15, weight: FontWeight.w700, color: T.textPrimary)),
                Text('${m.provider.toUpperCase()} · ${pro ? l.pick('แผน Pro', 'Pro') : l.pick('แผนฟรี', 'Free')}',
                    style: AppTheme.body(12, color: T.textMuted)),
              ],
            ),
          ),
          if (pro) const Pill(text: 'PRO', filled: true),
          IconButton(
            onPressed: () => member.logout(),
            icon: const Icon(Icons.logout_rounded, size: 18, color: T.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _coinsRow(BuildContext context, L10n l) {
    final member = context.watch<MemberState>();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EarnCoinsScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: T.accentSoft, borderRadius: BorderRadius.circular(T.rCard)),
        child: Row(
          children: [
            const HexIcon(icon: Icons.monetization_on_rounded, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l.bi('เหรียญของฉัน', 'My coins'),
                  style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
            ),
            Text('${member.coins}',
                style: AppTheme.display(18, weight: FontWeight.w700, color: T.accent)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(100)),
              child: Text(l.pick('หาเหรียญ', 'Earn'),
                  style: AppTheme.body(11.5, weight: FontWeight.w700, color: T.onAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageRow(BuildContext context, AppState app) {
    final l = app.l;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(T.rCard),
      ),
      child: Row(
        children: [
          const HexIcon(icon: Icons.translate_rounded, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l.bi('ภาษา', 'Language'),
                style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
          ),
          _segToggle(context, app),
        ],
      ),
    );
  }

  Widget _segToggle(BuildContext context, AppState app) {
    Widget seg(String label, bool active, AppLang lang) => GestureDetector(
          onTap: () => app.setLang(lang),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: active ? T.accentGradient : null,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(label,
                style: AppTheme.body(12.5,
                    weight: FontWeight.w700, color: active ? T.onAccent : T.textMuted)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x14000000),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: T.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('ไทย', app.lang == AppLang.th, AppLang.th),
        seg('EN', app.lang == AppLang.en, AppLang.en),
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, String th, String en, {VoidCallback? onTap, String? value}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.rCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            HexIcon(icon: icon, size: 34, color: T.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(th, style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                  Text(en, style: AppTheme.body(11, color: T.textFaint)),
                ],
              ),
            ),
            if (value != null) Text(value, style: AppTheme.body(12.5, color: T.textMuted)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: T.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _upgradeBanner(BuildContext context, L10n l) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoProScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rCard)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.pick('อัปเกรดเป็น Pro', 'Go Pro'),
                      style: AppTheme.display(16, weight: FontWeight.w700, color: T.onAccent)),
                  Text(l.pick('รับชมแบบไม่มีโฆษณา · ฿129/เดือน', 'Ad-free viewing · ฿129/mo'),
                      style: AppTheme.body(12, color: Color(0xCC2A1C05))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: T.onAccent),
          ],
        ),
      ),
    );
  }

  Widget _proActiveBanner(L10n l, MemberState member) {
    final until = member.proUntil;
    String two(int n) => n.toString().padLeft(2, '0');
    final untilText = until == null ? null : '${two(until.day)}/${two(until.month)}/${until.year}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.accentGlow),
      ),
      child: Row(
        children: [
          const HexIcon(icon: Icons.verified_rounded, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.bi('กำลังรับชมแบบไม่มีโฆษณา', 'Watching ad-free'),
                    style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                if (untilText != null)
                  Text(l.pick('Pro ถึง $untilText', 'Pro until $untilText'),
                      style: AppTheme.body(11.5, color: T.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _soon(BuildContext context, L10n l) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pick('จะมาในเวอร์ชันถัดไป', 'Coming soon'))),
      );

  // Custom About dialog — deliberately NOT showAboutDialog, which injects a
  // "View licenses" button (the open-source license page) we don't want users
  // to see.
  void _about(BuildContext context, L10n l) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: T.screen,
          title: Text('NetWix', style: AppTheme.display(18, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.pick('ดูฟรี · สตรีมมิ่ง', 'Free streaming'),
                  style: AppTheme.body(12.5, color: T.textMuted)),
              const SizedBox(height: 12),
              Text(
                l.pick(
                  'สำหรับการรับชมส่วนตัวเท่านั้น ทุกเรื่องดูฟรี · Pro 129฿ เพื่อรับชมแบบไม่มีโฆษณา',
                  'For personal viewing only. Everything is free · Pro 129฿ for ad-free.',
                ),
                style: AppTheme.body(12.5, color: T.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.pick('ปิด', 'Close'), style: AppTheme.body(13, color: T.accent)),
            ),
          ],
        ),
      );
}
