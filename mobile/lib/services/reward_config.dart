/// Coin economy + episode gating. These are the **client defaults**; once
/// netwix.online is live it can override them via `GET /api/config`.
///
/// Model: first [freeEpisodes] episodes of each series are free (with ads);
/// further episodes unlock with coins ([unlockCost] each). Pro (129฿/mo) is
/// ad-free AND unlocks everything without spending coins. Coins are earned via
/// the activities below.
class RewardConfig {
  RewardConfig._();

  /// Master switch for the coin-lock. While false, EVERY episode is free
  /// (playback isn't gated) — the coin/earn UI still works, nothing is locked.
  /// Flip to true to enable the "3 free then pay coins" model.
  static const bool gatingEnabled = false;

  static const int freeEpisodes = 3; // ดูฟรี 3 ตอนแรก (เมื่อ gatingEnabled)
  static const int unlockCost = 5; // เหรียญ/ตอน

  // ---- ways to earn coins (I define these; backend can override) ----
  static const int firstLoginBonus = 10; // ล็อกอินครั้งแรกด้วยบัญชี
  static const int dailyCheckin = 2; // เช็คอินรายวัน
  static const int rewardWatchCoins = 3; // ดูคลิปรับรางวัลจบ 1 คลิป
  static const int rewardWatchSeconds = 30; // ต้องดูอย่างน้อย (วินาที)
  static const int rewardWatchDailyMax = 5; // จำกัดต่อวัน
  static const int referralSignupBonus = 15; // เพื่อนสมัครผ่านโค้ดเรา
  static const int watchFiveDaily = 5; // ดูครบ 5 ตอนใน 1 วัน

  // ---- โปรชวนเพื่อน → Pro ฟรี (server-authoritative; client แค่แสดงผล) ----
  // ชวนเพื่อนที่ "ครบเงื่อนไข" (สมัคร + ยืนยัน + ดูจบ ≥1 ตอน) ให้ครบ
  // [referralTarget] คน → ปลดล็อก Pro ฟรี [referralRewardMonths] เดือน (ครั้งเดียว).
  // การนับ + การให้สิทธิ์ทำที่เซิร์ฟเวอร์เท่านั้น แอปไม่ตัดสินใจเอง (กันโกง).
  static const int referralTarget = 3;
  static const int referralRewardMonths = 2;

  // ---- ไลก์ / คอมเมนต์ / แชร์ → เหรียญ (best-effort local; server reconciles) ----
  // มี cap ต่อวันกันสแปมกดวน ๆ; เหรียญจริงเซิร์ฟเวอร์เป็นผู้ตัดสิน.
  static const int likeCoins = 1;
  static const int likeDailyMax = 5;
  static const int commentCoins = 2;
  static const int commentDailyMax = 3;
  static const int shareCoins = 1;
  static const int shareDailyMax = 3;
}

/// A coin-earning activity shown on the "หาเหรียญ" screen.
class RewardActivity {
  const RewardActivity({
    required this.key,
    required this.titleTh,
    required this.titleEn,
    required this.coins,
    required this.icon,
    this.perDayMax,
  });

  final String key;
  final String titleTh;
  final String titleEn;
  final int coins;
  final int icon; // IconData codepoint (kept int to avoid importing material here)
  final int? perDayMax;
}
