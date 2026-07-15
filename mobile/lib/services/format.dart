import 'dart:math' as math;

/// Human-readable formatting helpers.
class Format {
  static String bytes(int b) {
    if (b <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return i == 0 ? '${v.toStringAsFixed(0)} ${units[i]}' : '${v.toStringAsFixed(1)} ${units[i]}';
  }

  static String speed(double bytesPerSec) =>
      bytesPerSec <= 1 ? '' : '${bytes(bytesPerSec.toInt())}/s';

  static String percent(double fraction) => '${(fraction.clamp(0, 1) * 100).toStringAsFixed(0)}%';

  /// A day-count as the nicest Thai/English unit — mirrors the web's
  /// Campaigns::human() so promo texts always match (365→"1 ปี"/"1 yr").
  static String humanDays(int days, {bool thai = true}) {
    if (days >= 365 && days % 365 == 0) {
      final n = days ~/ 365;
      return thai ? '$n ปี' : '$n yr';
    }
    if (days >= 30 && days % 30 == 0) {
      final n = days ~/ 30;
      return thai ? '$n เดือน' : '$n mo';
    }
    if (days >= 7 && days % 7 == 0) {
      final n = days ~/ 7;
      return thai ? '$n สัปดาห์' : '$n wk';
    }
    return thai ? '$days วัน' : '$days days';
  }

  /// dd/mm/yyyy in local time. Locale-independent digits on purpose: this is
  /// used for entitlement dates (Pro expiry), which must read identically
  /// whatever language the app is in.
  static String date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }

  /// A short relative time ("5 นาทีที่แล้ว" / "5m ago"), matching what the web
  /// renders for comments via diffForHumans().
  static String ago(DateTime when, {bool thai = true}) {
    final d = DateTime.now().difference(when);
    if (d.inSeconds < 60) return thai ? 'เมื่อสักครู่' : 'just now';
    if (d.inMinutes < 60) {
      return thai ? '${d.inMinutes} นาทีที่แล้ว' : '${d.inMinutes}m ago';
    }
    if (d.inHours < 24) {
      return thai ? '${d.inHours} ชั่วโมงที่แล้ว' : '${d.inHours}h ago';
    }
    if (d.inDays < 30) {
      return thai ? '${d.inDays} วันที่แล้ว' : '${d.inDays}d ago';
    }
    // Older than a month — an exact date is more useful than "13 months ago".
    return date(when);
  }

  /// mm:ss or h:mm:ss for a duration in seconds.
  static String duration(int totalSeconds) {
    final s = math.max(0, totalSeconds);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
