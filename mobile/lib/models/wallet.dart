/// Gold wallet, VIP access and USDT top-up — the app's view of
/// `GET /api/app/wallet` (WalletController::snapshot).
///
/// Every rate, cap and balance here is **server-computed**. The app renders what
/// the snapshot says and never derives a balance locally: gold is real money, so
/// the client is not allowed an opinion about it.
library;

/// Silver→gold conversion rules + the member's gold balance.
class GoldState {
  const GoldState({
    this.goldCoins = 0,
    this.perUsdt = 0,
    this.convertEnabled = false,
    this.convertRate = 100,
    this.convertFeePct = 0,
    this.convertDailyCap = 0,
    this.convertRemainingToday,
  });

  final int goldCoins;

  /// Gold granted per 1 USDT topped up.
  final double perUsdt;

  final bool convertEnabled;

  /// Silver coins required for 1 gold.
  final int convertRate;

  /// Fee taken off the converted amount, as a percentage.
  final double convertFeePct;

  /// 0 = no cap. [convertRemainingToday] is null when uncapped.
  final int convertDailyCap;
  final int? convertRemainingToday;

  factory GoldState.fromJson(Map<String, dynamic> j) => GoldState(
        goldCoins: (j['gold_coins'] as num?)?.toInt() ?? 0,
        perUsdt: (j['per_usdt'] as num?)?.toDouble() ?? 0,
        convertEnabled: j['convert_enabled'] == true,
        convertRate: (j['convert_rate'] as num?)?.toInt() ?? 100,
        convertFeePct: (j['convert_fee_pct'] as num?)?.toDouble() ?? 0,
        convertDailyCap: (j['convert_daily_cap'] as num?)?.toInt() ?? 0,
        convertRemainingToday: (j['convert_remaining_today'] as num?)?.toInt(),
      );

  /// Gold actually received for [silver], after the fee — mirrors GoldWallet's
  /// maths for PREVIEW ONLY. The server recomputes it on convert.
  int previewGoldFor(int silver) {
    if (convertRate <= 0) return 0;
    final gross = silver ~/ convertRate;
    return (gross * (1 - convertFeePct / 100)).floor().clamp(0, gross);
  }
}

/// USDT (BEP20/BSC) top-up configuration.
class UsdtConfig {
  const UsdtConfig({
    this.enabled = false,
    this.wallet,
    this.network = 'BEP20 (BSC)',
    this.contract,
    this.minUsdt = 1,
    this.perUsdt = 0,
    this.proPriceUsdt = 0,
    this.proDays = 0,
    this.buyProGold = 0,
  });

  final bool enabled;

  /// Deposit address. Null/empty means top-up is not configured — the app must
  /// hide the flow rather than show an address-less order.
  final String? wallet;
  final String network;
  final String? contract;
  final double minUsdt;

  /// Gold per 1 USDT.
  final double perUsdt;
  final double proPriceUsdt;
  final int proDays;

  /// Gold price of Pro when buying with gold.
  final int buyProGold;

  bool get usable => enabled && (wallet?.isNotEmpty ?? false);

  factory UsdtConfig.fromJson(Map<String, dynamic> j) => UsdtConfig(
        enabled: j['enabled'] == true,
        wallet: j['wallet'] as String?,
        network: (j['network'] as String?) ?? 'BEP20 (BSC)',
        contract: j['contract'] as String?,
        minUsdt: (j['min_usdt'] as num?)?.toDouble() ?? 1,
        perUsdt: (j['per_usdt'] as num?)?.toDouble() ?? 0,
        proPriceUsdt: (j['pro_price_usdt'] as num?)?.toDouble() ?? 0,
        proDays: (j['pro_days'] as num?)?.toInt() ?? 0,
        buyProGold: (j['buy_pro_gold'] as num?)?.toInt() ?? 0,
      );
}

/// VIP-zone rules.
class VipConfig {
  const VipConfig({this.unlockCostGold = 0, this.proUnlocks = true});

  final int unlockCostGold;

  /// Whether an active Pro membership opens VIP titles without spending gold.
  final bool proUnlocks;

  factory VipConfig.fromJson(Map<String, dynamic> j) => VipConfig(
        unlockCostGold: (j['unlock_cost_gold'] as num?)?.toInt() ?? 0,
        proUnlocks: j['pro_unlocks'] != false,
      );
}

/// The whole wallet screen in one payload.
class WalletState {
  const WalletState({
    required this.gold,
    required this.usdt,
    required this.vip,
    this.membership,
  });

  final GoldState gold;
  final UsdtConfig usdt;
  final VipConfig vip;

  /// Raw `Membership::state()` — silver coins, Pro status, referral. Kept as a
  /// map so MemberState can apply it through its existing path.
  final Map<String, dynamic>? membership;

  factory WalletState.fromJson(Map<String, dynamic> j) => WalletState(
        gold: GoldState.fromJson(_map(j['gold'])),
        usdt: UsdtConfig.fromJson(_map(j['usdt'])),
        vip: VipConfig.fromJson(_map(j['vip'])),
        membership: j['membership'] is Map
            ? (j['membership'] as Map).cast<String, dynamic>()
            : null,
      );

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
}

/// Result of a wallet write (convert / buy-Pro / VIP unlock).
class WalletResult {
  const WalletResult({required this.ok, this.error, this.wallet, this.access});

  final bool ok;

  /// Server error code when [ok] is false, e.g. `insufficient`, `cap`,
  /// `disabled`, or `network` when the request never landed.
  final String? error;

  /// Refreshed wallet, when the server returned one.
  final WalletState? wallet;

  /// VIP access after an unlock: open | pro | unlocked | locked.
  final String? access;
}

/// VIP access for one title (`GET /content/{id}/vip`).
class VipAccess {
  const VipAccess({
    required this.contentId,
    required this.isVip,
    required this.access,
    required this.costGold,
  });

  final int contentId;
  final bool isVip;

  /// open | pro | unlocked | locked
  final String access;
  final int costGold;

  bool get watchable => access != 'locked';

  factory VipAccess.fromJson(Map<String, dynamic> j) => VipAccess(
        contentId: (j['content_id'] as num?)?.toInt() ?? 0,
        isVip: j['is_vip'] == true,
        access: (j['access'] as String?) ?? 'open',
        costGold: (j['cost_gold'] as num?)?.toInt() ?? 0,
      );
}

/// A USDT top-up order (`POST /usdt/order`, polled via
/// `/usdt/order/{reference}/check`).
///
/// The server identifies a deposit by its **exact amount** — it nudges each
/// order's total to a unique value and matches that on-chain. So [amountUsdt] is
/// kept as the server's own 6-decimal STRING and displayed/copied verbatim:
/// round-tripping it through a double could render 1.000001 as 1.0 and leave the
/// payment unmatchable.
class UsdtOrder {
  const UsdtOrder({
    required this.reference,
    required this.status,
    required this.purpose,
    required this.amountUsdt,
    this.baseUsdt,
    this.wallet,
    this.qr,
    this.network = 'BEP20 (BSC)',
    this.creditedGold = 0,
    this.proDays = 0,
    this.txHash,
    this.confirmations = 0,
    this.minConfirmations = 0,
    this.paidAt,
    this.expiresAt,
  });

  /// The order's identifier AND its route key (UsdtOrder::getRouteKeyName), so
  /// polling uses this string — there is no numeric id in the payload.
  final String reference;

  /// pending | paid | expired (server-owned; `expired` is derived server-side).
  final String status;

  /// gold | pro
  final String purpose;

  /// EXACT amount to send, as the server formatted it. Never re-format.
  final String amountUsdt;

  /// The pre-uniquified price, for display ("ราคา 5.00, โอน 5.000123").
  final String? baseUsdt;

  final String? wallet;

  /// What the QR should encode — the receiving address.
  final String? qr;
  final String network;

  /// Gold this order credits once paid (0 for a Pro order).
  final int creditedGold;

  /// Pro days this order grants (0 for a gold order).
  final int proDays;

  final String? txHash;
  final int confirmations;
  final int minConfirmations;
  final DateTime? paidAt;
  final DateTime? expiresAt;

  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';
  bool get isExpired => status == 'expired';

  /// Seen on-chain but not yet confirmed enough to credit.
  bool get isConfirming =>
      !isPaid && txHash != null && minConfirmations > 0 && confirmations < minConfirmations;

  factory UsdtOrder.fromJson(Map<String, dynamic> j) => UsdtOrder(
        reference: '${j['reference'] ?? ''}',
        status: (j['status'] as String?) ?? 'pending',
        purpose: (j['purpose'] as String?) ?? 'gold',
        amountUsdt: '${j['amount_usdt'] ?? ''}',
        baseUsdt: j['base_usdt'] == null ? null : '${j['base_usdt']}',
        wallet: j['wallet'] as String?,
        qr: j['qr'] as String?,
        network: (j['network'] as String?) ?? 'BEP20 (BSC)',
        creditedGold: (j['credited_gold'] as num?)?.toInt() ?? 0,
        proDays: (j['pro_days'] as num?)?.toInt() ?? 0,
        txHash: j['tx_hash'] as String?,
        confirmations: (j['confirmations'] as num?)?.toInt() ?? 0,
        minConfirmations: (j['min_confirmations'] as num?)?.toInt() ?? 0,
        paidAt: DateTime.tryParse('${j['paid_at'] ?? ''}'),
        expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}'),
      );
}
