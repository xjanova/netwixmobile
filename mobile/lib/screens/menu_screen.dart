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
import '../state/notification_state.dart';
import '../widgets/common.dart';
import '../widgets/icon3d.dart';
import '../widgets/login_sheet.dart';
import 'account_settings_screen.dart';
import 'earn_coins_screen.dart';
import 'go_pro_screen.dart';
import 'legal_screen.dart';
import 'my_list_screen.dart';
import 'notifications_screen.dart';
import 'profiles_screen.dart';
import 'wallet_screen.dart';
import 'whats_new_screen.dart';
import 'resolve_assist_screen.dart';

/// 07 — Menu / Settings · เมนู. Grouped frosted sections, 3D icons, and every number
/// (Pro price, sign-up bonus, referral reward) read from the web's live membership config.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.l;
    final member = context.watch<MemberState>();
    final effectivePro = member.isPro;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(l.bi('เมนู', 'Menu'), style: AppTheme.display(21, weight: FontWeight.w700)),
        const SizedBox(height: 16),
        _accountCard(context, app),
        const SizedBox(height: 12),
        _coinsRow(context, l),
        if (member.isLoggedIn && !effectivePro && member.inviterProDays > 0) ...[
          const SizedBox(height: 12),
          _referralPromoRow(context, l, member),
        ],
        const SizedBox(height: 14),
        if (!effectivePro) _upgradeBanner(context, l, member) else _proActiveBanner(l, member),
        _groupTitle(l.pick('บัญชีและการรับชม', 'Account & watching')),
        _group([
          if (member.isLoggedIn)
            _row(context, Ic3.account, 'ข้อมูลบัญชี', 'Account details',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AccountSettingsScreen()))),
          if (member.isLoggedIn)
            _row(context, Ic3.profiles, 'โปรไฟล์', 'Profiles',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ProfilesScreen()))),
          _row(context, Ic3.mylist, 'รายการของฉัน', 'My List',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MyListScreen()))),
          if (member.isLoggedIn)
            _row(context, Ic3.wallet, 'กระเป๋าเหรียญทอง', 'Gold wallet',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const WalletScreen()))),
          _row(context, Ic3.trophy, 'ภารกิจ & เหรียญ', 'Missions & coins',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const EarnCoinsScreen()))),
        ]),
        _groupTitle(l.pick('แอป', 'App')),
        _group([
          _languageRow(context, app),
          _notificationsRow(context),
          _row(context, Ic3.update, 'อัปเดต', 'Updates',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatsNewScreen()))),
          if (member.isLoggedIn)
            _row(context, Ic3.clip, 'ช่วยหลังบ้านขอลิงก์', 'Help admin resolve a link',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResolveAssistScreen()))),
        ]),
        _groupTitle(l.pick('ข้อกำหนด', 'Legal')),
        _group([
          _row(context, Ic3.shield, 'ข้อตกลงการใช้งาน', 'Terms of Service',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LegalScreen(doc: 'terms')))),
          _row(context, Ic3.shield, 'นโยบายความเป็นส่วนตัว', 'Privacy Policy',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LegalScreen(doc: 'privacy')))),
          _row(context, Ic3.gift, 'เกี่ยวกับ', 'About', onTap: () => _about(context, l, member)),
        ]),
        if (member.isLoggedIn) ...[
          const SizedBox(height: 28),
          _dangerZone(context, l),
        ],
      ],
    );
  }

  Widget _groupTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
        child: Text(text, style: AppTheme.body(12.5, weight: FontWeight.w700, color: T.textMuted)),
      );

  /// One frosted card holding a run of rows, separated by hairlines.
  Widget _group(List<Widget> rows) => Container(
        decoration: T.glass(radius: 20),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, indent: 66, color: T.hairline),
              rows[i],
            ],
          ]),
        ),
      );

  /// การแจ้งเตือน row with the unread badge.
  Widget _notificationsRow(BuildContext context) {
    final unread = context.watch<NotificationState>().unreadCount;
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        child: Row(
          children: [
            const Icon3D(Ic3.bell, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('การแจ้งเตือน',
                      style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                  Text('Notifications', style: AppTheme.body(11, color: T.textFaint)),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    gradient: T.accentGradient, borderRadius: BorderRadius.circular(100)),
                child: Text(unread > 99 ? '99+' : '$unread',
                    style: AppTheme.body(11, weight: FontWeight.w700, color: T.onAccent)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: T.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  /// โซนอันตราย — permanent account deletion, behind a typed confirmation.
  Widget _dangerZone(BuildContext context, L10n l) {
    const danger = Color(0xFFFF6B81);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14E5484D),
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: const Color(0x33E5484D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.pick('โซนอันตราย', 'Danger zone'),
              style: AppTheme.body(13, weight: FontWeight.w700, color: danger)),
          const SizedBox(height: 6),
          Text(
            l.pick(
                'ลบบัญชีและข้อมูลทั้งหมดอย่างถาวร — ประวัติดู เหรียญ Pro และโปรไฟล์จะหายทั้งหมด กู้คืนไม่ได้',
                'Permanently delete your account and all data — history, coins, Pro and profiles. Cannot be undone.'),
            style: AppTheme.body(12, color: T.textMuted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmDeleteAccount(context, l),
            style: OutlinedButton.styleFrom(
              foregroundColor: danger,
              side: const BorderSide(color: Color(0x66E5484D)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(l.pick('ลบบัญชีของฉัน', 'Delete my account'),
                style: AppTheme.body(13, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, L10n l) async {
    final member = context.read<MemberState>();
    final controller = TextEditingController();
    const keyword = 'DELETE';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // Only the button's enabled state lives here — the controller is
        // created (and disposed) by the enclosing method, so it survives
        // rebuilds and never leaks.
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: T.screen,
          title: Text(l.pick('ลบบัญชีถาวร?', 'Delete account forever?'),
              style: AppTheme.display(17, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.pick(
                    'ข้อมูลทั้งหมดจะถูกลบทันทีและกู้คืนไม่ได้ พิมพ์ $keyword เพื่อยืนยัน',
                    'All data is erased immediately and cannot be recovered. Type $keyword to confirm.'),
                style: AppTheme.body(13, color: T.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppTheme.body(14, color: T.textPrimary),
                decoration: const InputDecoration(hintText: keyword),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.pick('ยกเลิก', 'Cancel'), style: AppTheme.body(13, color: T.textMuted)),
            ),
            TextButton(
              onPressed: controller.text.trim() == keyword
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: Text(l.pick('ลบถาวร', 'Delete forever'),
                  style: AppTheme.body(13,
                      weight: FontWeight.w700,
                      color: controller.text.trim() == keyword
                          ? const Color(0xFFFF6B81)
                          : T.textFaint)),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !context.mounted) return;

    // Show progress while the server wipes the account.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: T.accent)),
    );
    final ok = await member.deleteAccount();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? l.pick('ลบบัญชีเรียบร้อยแล้ว ขอบคุณที่ใช้บริการ NetWix', 'Account deleted. Thank you for using NetWix')
          : l.pick('ลบบัญชีไม่สำเร็จ กรุณาลองใหม่หรือติดต่อทีมงาน', 'Could not delete the account — please retry or contact support')),
    ));
  }

  /// The web's actual referral rule: each friend who redeems your code gives you Pro days
  /// (`referrer_pro_days`) and coins (`referrer_coins`) — no invented multi-friend target.
  Widget _referralPromoRow(BuildContext context, L10n l, MemberState member) {
    final done = member.referralQualified;
    final coins = member.referralSignupCoins;
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EarnCoinsScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x33FF2D55), Color(0x22B026FF)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: T.accentGlow),
        ),
        child: Row(
          children: [
            const Icon3D(Ic3.friends, size: 46, tile: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.pick('ชวนเพื่อน 1 คน รับ Pro ฟรี ${Format.humanDays(member.inviterProDays)}',
                        'Invite a friend — ${Format.humanDays(member.inviterProDays, thai: false)} of Pro free'),
                    style: AppTheme.body(13.5, weight: FontWeight.w700, color: T.textPrimary),
                  ),
                  Text(
                      coins > 0
                          ? l.pick('+$coins เหรียญต่อเพื่อน · ชวนแล้ว $done คน', '+$coins coins per friend · $done invited')
                          : l.pick('ชวนแล้ว $done คน', '$done invited'),
                      style: AppTheme.body(11.5, color: T.accentHi)),
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
        radius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon3D(Ic3.gift, size: 52, tile: false),
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
                            : l.pick('เข้าสู่ระบบครั้งแรก รับ ${member.signupBonusCoins} เหรียญฟรี',
                                'Sign in — ${member.signupBonusCoins} free coins'),
                        style: AppTheme.body(11.5, color: T.accentHi)),
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
                  Text(l.pick('เข้าสู่ระบบ / สมัครฟรี', 'Sign in / Sign up free'),
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
      radius: 20,
      child: Row(
        children: [
          const HexAvatar(size: 52, child: Icon(Icons.person, color: T.accentHi, size: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(15, weight: FontWeight.w700, color: T.textPrimary)),
                Text('${m.provider.toUpperCase()} · ${pro ? l.pick('แผน Pro', 'Pro') : l.pick('แผนฟรี', 'Free')}',
                    style: AppTheme.body(12, color: T.textMuted)),
              ],
            ),
          ),
          if (pro) const Pill(text: 'PRO', filled: true),
          IconButton(
            tooltip: l.pick('ออกจากระบบ', 'Sign out'),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: T.accentSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33FF6B85)),
        ),
        child: Row(
          children: [
            const Icon3D(Ic3.coins, size: 44, tile: false),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l.bi('เหรียญของฉัน', 'My coins'),
                  style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
            ),
            Text(Format.grouped(member.coins),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const Icon3D(Ic3.language, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ภาษา', style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                Text('Language', style: AppTheme.body(11, color: T.textFaint)),
              ],
            ),
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

  Widget _row(BuildContext context, Ic3 icon, String th, String en, {VoidCallback? onTap, String? value}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        child: Row(
          children: [
            Icon3D(icon, size: 40),
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

  Widget _upgradeBanner(BuildContext context, L10n l, MemberState member) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoProScreen())),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        decoration: BoxDecoration(
          gradient: T.accentGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: T.accentGlow, blurRadius: 26, offset: Offset(0, 12), spreadRadius: -12)],
        ),
        child: Row(
          children: [
            const Icon3D(Ic3.crown, size: 56, tile: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.pick('อัปเกรดเป็น Pro', 'Go Pro'),
                      style: AppTheme.display(16, weight: FontWeight.w700, color: T.onAccent)),
                  Text(
                      l.pick('รับชมแบบไม่มีโฆษณา · ฿${member.proPriceThb}/เดือน',
                          'Ad-free viewing · ฿${member.proPriceThb}/mo'),
                      style: AppTheme.body(12, color: const Color(0xE6FFFFFF))),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: BoxDecoration(
        color: T.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: T.accentGlow),
      ),
      child: Row(
        children: [
          const Icon3D(Ic3.crown, size: 52, tile: false),
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

  // Custom About dialog — deliberately NOT showAboutDialog, which injects a
  // "View licenses" button (the open-source license page) we don't want users
  // to see.
  void _about(BuildContext context, L10n l, MemberState member) => showDialog<void>(
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
                  'สำหรับการรับชมส่วนตัวเท่านั้น · Pro ${member.proPriceThb}฿ เพื่อรับชมแบบไม่มีโฆษณา',
                  'For personal viewing only · Pro ${member.proPriceThb}฿ for ad-free.',
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
