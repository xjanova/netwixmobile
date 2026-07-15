import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/wallet.dart';
import '../services/format.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Which flow to open on.
enum WalletTab { wallet, usdtGold, usdtPro }

/// Gold wallet · กระเป๋าเหรียญทอง — mirrors the web `/account` wallet card:
/// balances, silver→gold convert, and USDT (BEP20) top-up.
///
/// The server owns every number here. The app never computes a balance it then
/// trusts: convert previews are labelled as previews, and the authoritative
/// figures always come back from the server's snapshot after each write.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.initialTab = WalletTab.wallet});

  final WalletTab initialTab;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _silverCtrl = TextEditingController();
  final _usdtCtrl = TextEditingController();

  WalletState? _wallet;
  bool _loading = true;
  bool _busy = false;

  UsdtOrder? _order;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialTab == WalletTab.usdtPro) {
      // Opened straight from Go Pro — start the Pro order once prices are in.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startProOrderWhenReady());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _silverCtrl.dispose();
    _usdtCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final w = await context.read<NetwixApi>().fetchWallet();
    if (!mounted) return;
    setState(() {
      _wallet = w;
      _loading = false;
    });
    if (w?.membership != null) {
      context.read<MemberState>().applyMembershipState(w!.membership!);
    }
  }

  Future<void> _startProOrderWhenReady() async {
    while (mounted && _loading) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted) return;
    if (_wallet?.usdt.usable == true && (_wallet?.usdt.proPriceUsdt ?? 0) > 0) {
      await _createOrder(purpose: 'pro');
    }
  }

  // ------------------------------------------------------------- convert

  Future<void> _convert() async {
    if (_busy) return;
    final l = context.read<AppState>().l;
    final w = _wallet;
    if (w == null) return;

    final silver = int.tryParse(_silverCtrl.text.trim()) ?? 0;
    if (silver <= 0) return;

    final gold = w.gold.previewGoldFor(silver);
    if (gold <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.pick('เหรียญเงินน้อยเกินไป (${w.gold.convertRate} เงิน = 1 ทอง)',
            'Too little silver (${w.gold.convertRate} silver = 1 gold)')),
      ));
      return;
    }

    final ok = await _confirm(
      l,
      title: l.pick('แปลงเป็นเหรียญทอง', 'Convert to gold'),
      body: l.pick('แปลง $silver เหรียญเงิน → ประมาณ $gold เหรียญทอง',
          'Convert $silver silver → about $gold gold'),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    // The API takes the GOLD amount wanted, not the silver spent.
    final res = await context.read<NetwixApi>().convertGold(gold);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.wallet != null) _wallet = res.wallet;
    });

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_convertError(res.error, l))),
      );
      return;
    }
    _silverCtrl.clear();
    if (res.wallet?.membership != null) {
      context.read<MemberState>().applyMembershipState(res.wallet!.membership!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.pick('แปลงเป็นเหรียญทองแล้ว 🥇', 'Converted to gold 🥇')),
      ));
    }
  }

  String _convertError(String? code, L10n l) => switch (code) {
        'insufficient' => l.pick('เหรียญเงินไม่พอ', 'Not enough silver'),
        'cap' => l.pick('เกินโควตาแปลงของวันนี้แล้ว', 'Daily convert limit reached'),
        'disabled' => l.pick('ปิดการแปลงเหรียญชั่วคราว', 'Converting is disabled right now'),
        'network' => l.pick('เชื่อมต่อไม่ได้ ลองใหม่อีกครั้ง', 'Connection failed — try again'),
        _ => l.pick('แปลงไม่สำเร็จ ลองใหม่อีกครั้ง', 'Convert failed — try again'),
      };

  // ---------------------------------------------------------------- usdt

  Future<void> _createOrder({required String purpose}) async {
    if (_busy) return;
    final l = context.read<AppState>().l;
    final w = _wallet;
    if (w == null) return;

    double? usdt;
    if (purpose == 'gold') {
      usdt = double.tryParse(_usdtCtrl.text.trim());
      if (usdt == null || usdt < w.usdt.minUsdt) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.pick('ขั้นต่ำ ${w.usdt.minUsdt} USDT', 'Minimum ${w.usdt.minUsdt} USDT')),
        ));
        return;
      }
    }

    setState(() => _busy = true);
    final o = await context.read<NetwixApi>().createUsdtOrder(purpose: purpose, usdt: usdt);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _order = o;
    });

    if (o == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.pick('สร้างรายการไม่สำเร็จ', 'Could not create the order')),
      ));
      return;
    }
    _startPolling();
  }

  /// Poll while an order is open. The server verifies against the chain on each
  /// call, so this is the only way the app learns a deposit landed.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) async {
      final ref = _order?.reference;
      if (ref == null || ref.isEmpty) return;
      final o = await context.read<NetwixApi>().checkUsdtOrder(ref);
      if (!mounted || o == null) return;
      setState(() => _order = o);

      if (o.isPaid || o.isExpired) {
        _poll?.cancel();
        if (o.isPaid) {
          await _load(); // balances/Pro moved — pull the fresh snapshot
          if (!mounted) return;
          final l = context.read<AppState>().l;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(o.purpose == 'pro'
                ? l.pick('ชำระเงินสำเร็จ — เปิดใช้งาน Pro แล้ว 🎉', 'Paid — Pro activated 🎉')
                : l.pick('ชำระเงินสำเร็จ — เติมเหรียญทองแล้ว 🥇', 'Paid — gold credited 🥇')),
          ));
        }
      }
    });
  }

  Future<bool?> _confirm(L10n l, {required String title, required String body}) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: T.surface,
        title: Text(title, style: AppTheme.display(16, weight: FontWeight.w700)),
        content: Text(body, style: AppTheme.body(13.5, color: T.textSecondary)),
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
  }

  void _copy(String value, String toast) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      backgroundColor: T.screen,
      appBar: AppBar(
        backgroundColor: T.screen,
        elevation: 0,
        title: Text(l.bi('กระเป๋าเหรียญทอง', 'Gold wallet'),
            style: AppTheme.display(17, weight: FontWeight.w700)),
      ),
      body: !member.isLoggedIn
          ? Center(
              child: Text(l.pick('เข้าสู่ระบบเพื่อใช้กระเป๋าเหรียญ', 'Sign in to use your wallet'),
                  style: AppTheme.body(13, color: T.textMuted)),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator(color: T.accent))
              : _wallet == null
                  ? Center(
                      child: TextButton(
                        onPressed: _load,
                        child: Text(l.pick('โหลดไม่สำเร็จ · ลองใหม่', 'Failed to load · Retry'),
                            style: AppTheme.body(13, color: T.accent)),
                      ),
                    )
                  : RefreshIndicator(
                      color: T.accent,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        children: [
                          _balances(l, member),
                          const SizedBox(height: 18),
                          if (_wallet!.gold.convertEnabled) ...[
                            _convertCard(l, member),
                            const SizedBox(height: 18),
                          ],
                          if (_wallet!.usdt.usable) _usdtCard(l),
                          if (_order != null) ...[
                            const SizedBox(height: 18),
                            _orderCard(l),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _balances(L10n l, MemberState member) {
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.pick('เหรียญเงิน', 'Silver'), style: AppTheme.body(12, color: T.textMuted)),
                const SizedBox(height: 4),
                Text('🪙 ${member.coins}',
                    style: AppTheme.display(20, weight: FontWeight.w700)),
              ],
            ),
          ),
          Container(width: 1, height: 38, color: T.hairline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l.pick('เหรียญทอง', 'Gold'), style: AppTheme.body(12, color: T.textMuted)),
                const SizedBox(height: 4),
                Text('🥇 ${_wallet!.gold.goldCoins}',
                    style: AppTheme.display(20, weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _convertCard(L10n l, MemberState member) {
    final g = _wallet!.gold;
    final silver = int.tryParse(_silverCtrl.text.trim()) ?? 0;
    final preview = g.previewGoldFor(silver);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.bi('แปลงเหรียญเงิน → ทอง', 'Convert silver → gold'),
              style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 6),
          Text(
            [
              l.pick('${g.convertRate} เงิน = 1 ทอง', '${g.convertRate} silver = 1 gold'),
              if (g.convertFeePct > 0)
                l.pick('ค่าธรรมเนียม ${g.convertFeePct}%', 'fee ${g.convertFeePct}%'),
              if (g.convertRemainingToday != null)
                l.pick('วันนี้เหลือ ${g.convertRemainingToday} ทอง',
                    '${g.convertRemainingToday} gold left today'),
            ].join(' · '),
            style: AppTheme.body(11.5, color: T.textFaint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _silverCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: AppTheme.body(14, color: T.textPrimary),
            cursorColor: T.accent,
            decoration: InputDecoration(
              hintText: l.pick('จำนวนเหรียญเงิน', 'Silver amount'),
              hintStyle: AppTheme.body(13.5, color: T.textMuted),
              filled: true,
              fillColor: const Color(0x10FFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(T.rButton),
                borderSide: const BorderSide(color: T.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(T.rButton),
                borderSide: const BorderSide(color: T.hairline),
              ),
            ),
          ),
          if (silver > 0) ...[
            const SizedBox(height: 8),
            Text(
              l.pick('จะได้ประมาณ 🥇 $preview (ยอดจริงคำนวณโดยเซิร์ฟเวอร์)',
                  'You get about 🥇 $preview (server confirms the final amount)'),
              style: AppTheme.body(12, color: T.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          AccentButton(
            label: l.bi('แปลงเป็นเหรียญทอง', 'Convert to gold'),
            icon: Icons.swap_horiz_rounded,
            enabled: !_busy && silver > 0 && silver <= member.coins,
            onPressed: _convert,
          ),
        ],
      ),
    );
  }

  Widget _usdtCard(L10n l) {
    final u = _wallet!.usdt;
    final usdt = double.tryParse(_usdtCtrl.text.trim()) ?? 0;
    final goldPreview = (usdt * u.perUsdt).floor();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.bi('เติมด้วย USDT', 'Top up with USDT'),
              style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 6),
          Text(
            '${u.network} · ${l.pick('ขั้นต่ำ', 'min')} ${u.minUsdt} USDT · 1 USDT = 🥇 ${u.perUsdt}',
            style: AppTheme.body(11.5, color: T.textFaint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usdtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: AppTheme.body(14, color: T.textPrimary),
            cursorColor: T.accent,
            decoration: InputDecoration(
              hintText: l.pick('จำนวน USDT', 'USDT amount'),
              hintStyle: AppTheme.body(13.5, color: T.textMuted),
              filled: true,
              fillColor: const Color(0x10FFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(T.rButton),
                borderSide: const BorderSide(color: T.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(T.rButton),
                borderSide: const BorderSide(color: T.hairline),
              ),
            ),
          ),
          if (usdt > 0) ...[
            const SizedBox(height: 8),
            Text(l.pick('จะได้ประมาณ 🥇 $goldPreview', 'You get about 🥇 $goldPreview'),
                style: AppTheme.body(12, color: T.textSecondary)),
          ],
          const SizedBox(height: 12),
          AccentButton(
            label: l.bi('สร้างรายการเติมเงิน', 'Create top-up order'),
            icon: Icons.account_balance_wallet_rounded,
            enabled: !_busy && usdt >= u.minUsdt,
            onPressed: () => _createOrder(purpose: 'gold'),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(L10n l) {
    final o = _order!;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.purpose == 'pro'
                      ? l.bi('ชำระค่า Pro', 'Pay for Pro')
                      : l.bi('เติมเหรียญทอง', 'Top up gold'),
                  style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary),
                ),
              ),
              Pill(
                text: switch (o.status) {
                  'paid' => l.pick('ชำระแล้ว', 'Paid'),
                  'expired' => l.pick('หมดอายุ', 'Expired'),
                  _ => l.pick('รอชำระ', 'Pending'),
                },
                filled: o.isPaid,
                color: o.isPaid ? T.accent : T.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // The server matches the deposit by its EXACT amount — surface it as
          // the server sent it and make it one tap to copy.
          _copyRow(
            l,
            label: l.pick('โอนเป็นจำนวนนี้เท่านั้น', 'Send exactly this amount'),
            value: '${o.amountUsdt} USDT',
            copyValue: o.amountUsdt,
            toast: l.pick('คัดลอกจำนวนแล้ว', 'Amount copied'),
            emphasise: true,
          ),
          const SizedBox(height: 10),
          _copyRow(
            l,
            label: '${l.pick('ที่อยู่กระเป๋า', 'Wallet address')} · ${o.network}',
            value: o.wallet ?? '-',
            copyValue: o.wallet ?? '',
            toast: l.pick('คัดลอกที่อยู่แล้ว', 'Address copied'),
          ),

          if (o.isPending) ...[
            const SizedBox(height: 12),
            Text(
              l.pick(
                  'โอนจำนวนให้ตรงทุกทศนิยม ระบบใช้ยอดนี้ระบุการโอนของคุณ',
                  'Send the exact amount — the system identifies your payment by it'),
              style: AppTheme.body(11.5, color: T.textFaint),
            ),
            if (o.expiresAt != null) ...[
              const SizedBox(height: 4),
              Text(l.pick('หมดอายุ ${Format.date(o.expiresAt!)}', 'Expires ${Format.date(o.expiresAt!)}'),
                  style: AppTheme.body(11.5, color: T.textFaint)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: T.accent),
                ),
                const SizedBox(width: 10),
                Text(
                  o.isConfirming
                      ? l.pick('ยืนยันบนเชน ${o.confirmations}/${o.minConfirmations}',
                          'Confirming on-chain ${o.confirmations}/${o.minConfirmations}')
                      : l.pick('กำลังรอการโอน…', 'Waiting for your transfer…'),
                  style: AppTheme.body(12, color: T.textSecondary),
                ),
              ],
            ),
          ],

          if (o.isExpired) ...[
            const SizedBox(height: 10),
            Text(l.pick('รายการนี้หมดอายุแล้ว สร้างรายการใหม่ได้', 'This order expired — create a new one'),
                style: AppTheme.body(12, color: T.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _copyRow(
    L10n l, {
    required String label,
    required String value,
    required String copyValue,
    required String toast,
    bool emphasise = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(11.5, color: T.textMuted)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: copyValue.isEmpty ? null : () => _copy(copyValue, toast),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: emphasise ? T.accentSoft : const Color(0x10FFFFFF),
              borderRadius: BorderRadius.circular(T.rButton),
              border: Border.all(color: emphasise ? T.accentGlow : T.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: AppTheme.body(emphasise ? 15 : 12.5,
                        weight: emphasise ? FontWeight.w700 : FontWeight.w400,
                        color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_rounded, size: 15, color: T.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
