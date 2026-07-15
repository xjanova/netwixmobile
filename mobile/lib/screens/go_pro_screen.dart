import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/wallet.dart';
import '../services/format.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/login_sheet.dart';
import 'wallet_screen.dart';

/// 05 — Go Pro · สมัคร Pro. Pro = **ad-free** viewing (all content is free either
/// way; Pro just removes ads) plus VIP-zone access when the admin enables it.
///
/// Everything priced here is server-driven (`GET /api/app/wallet`): the gold cost,
/// the USDT price and the Pro duration all come from admin config. This screen
/// used to show hardcoded ฿129/฿990 and grant Pro with a local `setPro(true)` —
/// no payment, no server — which also unlocked every episode for free.
class GoProScreen extends StatefulWidget {
  const GoProScreen({super.key});

  @override
  State<GoProScreen> createState() => _GoProScreenState();
}

class _GoProScreenState extends State<GoProScreen> {
  WalletState? _wallet;
  bool _loading = true;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final member = context.read<MemberState>();
    if (!member.isLoggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final w = await context.read<NetwixApi>().fetchWallet();
    if (!mounted) return;
    setState(() {
      _wallet = w;
      _loading = false;
    });
  }

  /// Buy Pro with gold. Confirms first — this spends a real balance.
  Future<void> _buyWithGold() async {
    if (_buying) return;
    final l = context.read<AppState>().l;
    final cost = _wallet?.usdt.buyProGold ?? 0;
    final days = _wallet?.usdt.proDays ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: T.surface,
        title: Text(l.pick('ซื้อ Pro ด้วยเหรียญทอง', 'Buy Pro with gold'),
            style: AppTheme.display(16, weight: FontWeight.w700)),
        content: Text(
          l.pick('ใช้ $cost เหรียญทอง แลก Pro ${Format.humanDays(days)}',
              'Spend $cost gold for ${Format.humanDays(days)} of Pro'),
          style: AppTheme.body(13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l.pick('ยกเลิก', 'Cancel'), style: AppTheme.body(13, color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l.pick('ยืนยัน', 'Confirm'), style: AppTheme.body(13, color: T.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _buying = true);
    final res = await context.read<NetwixApi>().buyProWithGold();
    if (!mounted) return;
    setState(() {
      _buying = false;
      if (res.wallet != null) _wallet = res.wallet;
    });

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(res.error, l))),
      );
      return;
    }

    // Pro is server state now — pull it through so the UI reflects the purchase.
    if (res.wallet?.membership != null) {
      context.read<MemberState>().applyMembershipState(res.wallet!.membership!);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.pick('เปิดใช้งาน Pro แล้ว 🎉', 'Pro activated 🎉')),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  String _errorText(String? code, L10n l) => switch (code) {
        'insufficient' => l.pick('เหรียญทองไม่พอ', 'Not enough gold'),
        'disabled' => l.pick('ยังไม่เปิดให้ซื้อด้วยเหรียญทอง', 'Buying with gold is not enabled'),
        'network' => l.pick('เชื่อมต่อไม่ได้ ลองใหม่อีกครั้ง', 'Connection failed — try again'),
        _ => l.pick('ทำรายการไม่สำเร็จ ลองใหม่อีกครั้ง', 'Purchase failed — try again'),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();
    final isPro = member.isPro;

    final benefits = [
      l.bi('ไม่มีโฆษณาระหว่างดู', 'No ads while watching'),
      l.bi('ดูฟรีทุกเรื่องเหมือนเดิม', 'Everything still free to watch'),
      l.bi('รับชมลื่นไหล ไม่มีสะดุด', 'Smooth, uninterrupted viewing'),
      l.bi('สนับสนุนผู้พัฒนา', 'Support the developer'),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.1,
            colors: [Color(0x33F5A623), Colors.transparent],
            stops: [0, 0.5],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: T.textSecondary),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Center(child: Floating(child: const GemCrest(size: 84, icon: Icons.star_rounded))),
                    const SizedBox(height: 18),
                    Center(
                      child: Text('NetWix Pro', style: AppTheme.display(24, weight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        isPro
                            ? _proUntilText(member, l)
                            : l.bi('รับชมแบบไม่มีโฆษณา', 'Watch ad-free'),
                        style: AppTheme.body(13.5, color: isPro ? T.accent : T.textMuted),
                      ),
                    ),
                    const SizedBox(height: 26),
                    for (final b in benefits) _benefit(b),
                    const SizedBox(height: 24),
                    if (!isPro) ..._plans(l, member),
                  ],
                ),
              ),
              if (!isPro && !member.isLoggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: AccentButton(
                    label: l.bi('เข้าสู่ระบบเพื่อสมัคร', 'Sign in to subscribe'),
                    icon: Icons.login_rounded,
                    onPressed: () async {
                      await showLoginSheet(context);
                      if (mounted) _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _proUntilText(MemberState m, L10n l) {
    final until = m.proUntil;
    if (until == null) return l.pick('เป็นสมาชิก Pro แล้ว', 'You are Pro');
    return l.pick('เป็นสมาชิก Pro ถึง ${Format.date(until)}',
        'Pro until ${Format.date(until)}');
  }

  /// The real purchase paths. Both are admin-configured server-side; whichever is
  /// switched off simply doesn't render, rather than showing a price we'd fail to
  /// honour.
  List<Widget> _plans(L10n l, MemberState member) {
    if (!member.isLoggedIn) {
      return [
        Text(
          l.pick('เข้าสู่ระบบเพื่อดูราคาและสมัคร Pro', 'Sign in to see pricing and subscribe'),
          textAlign: TextAlign.center,
          style: AppTheme.body(13, color: T.textMuted),
        ),
      ];
    }

    if (_loading) {
      return [const Center(child: CircularProgressIndicator(color: T.accent))];
    }

    final w = _wallet;
    if (w == null) {
      return [
        Center(
          child: TextButton(
            onPressed: _load,
            child: Text(l.pick('โหลดราคาไม่สำเร็จ · ลองใหม่', 'Could not load pricing · Retry'),
                style: AppTheme.body(13, color: T.accent)),
          ),
        ),
      ];
    }

    final goldCost = w.usdt.buyProGold;
    final days = w.usdt.proDays;
    final out = <Widget>[];

    if (goldCost > 0) {
      final have = w.gold.goldCoins;
      out.add(_payCard(
        l,
        primary: true,
        title: l.pick('ซื้อด้วยเหรียญทอง', 'Pay with gold'),
        price: '🥇 $goldCost',
        per: days > 0 ? '/ ${Format.humanDays(days)}' : '',
        subtitle: l.pick('มีอยู่ $have เหรียญทอง', 'You have $have gold'),
        enabled: !_buying && have >= goldCost,
        trailingHint: have < goldCost ? l.pick('เหรียญทองไม่พอ', 'Not enough gold') : null,
        onTap: _buyWithGold,
      ));
    }

    if (w.usdt.usable && w.usdt.proPriceUsdt > 0) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 12));
      out.add(_payCard(
        l,
        primary: goldCost <= 0,
        title: l.pick('จ่ายด้วย USDT', 'Pay with USDT'),
        price: '${w.usdt.proPriceUsdt} USDT',
        per: days > 0 ? '/ ${Format.humanDays(days)}' : '',
        subtitle: w.usdt.network,
        enabled: !_buying,
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const WalletScreen(initialTab: WalletTab.usdtPro),
          ));
          if (mounted) _load();
        },
      ));
    }

    if (out.isEmpty) {
      out.add(Text(
        l.pick('ยังไม่เปิดให้สมัคร Pro ในแอปตอนนี้', 'Pro is not purchasable in the app right now'),
        textAlign: TextAlign.center,
        style: AppTheme.body(13, color: T.textMuted),
      ));
    }
    return out;
  }

  Widget _benefit(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: T.accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 15, color: T.accent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppTheme.body(14, color: T.textSecondary))),
          ],
        ),
      );

  Widget _payCard(
    L10n l, {
    required bool primary,
    required String title,
    required String price,
    required String per,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
    String? trailingHint,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primary ? T.accentSoft : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(T.rCard),
            border: Border.all(color: primary ? T.accentGlow : T.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTheme.body(15, weight: FontWeight.w700, color: T.textPrimary)),
                    const SizedBox(height: 4),
                    Text(trailingHint ?? subtitle,
                        style: AppTheme.body(11.5,
                            color: trailingHint != null ? T.accent : T.textFaint)),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                      text: price,
                      style: AppTheme.display(20, weight: FontWeight.w700, color: T.textPrimary)),
                  if (per.isNotEmpty)
                    TextSpan(text: ' $per', style: AppTheme.body(12, color: T.textMuted)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
