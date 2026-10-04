/// Pure, unit-testable version logic for the in-app auto-updater.
///
/// ⚠️ Learned the hard way (Juntra, 2026-06-04): deciding "is there an update?"
/// with a **version-only** compare silently misses *build-only* releases
/// (same X.Y.Z, higher +build) — users get stuck on an old build forever.
/// So [isReleaseNewer] lets semver dominate and uses the **build number as a
/// tiebreaker**. Keep it that way.
library;

/// A parsed release identity: the numeric semver parts plus the +build number.
class ReleaseVersion {
  const ReleaseVersion(this.parts, this.build);

  final List<int> parts;
  final int build;

  /// Parses tags/versions like `v1.2.3`, `1.2.3`, `v1.2.3+7`, `1.2.3-beta+7`.
  /// Non-numeric noise is ignored; missing pieces default to 0.
  static ReleaseVersion parse(String raw) {
    var s = raw.trim();
    if (s.isNotEmpty && (s[0] == 'v' || s[0] == 'V')) s = s.substring(1);

    var build = 0;
    final plus = s.indexOf('+');
    if (plus >= 0) {
      build = _firstInt(s.substring(plus + 1));
      s = s.substring(0, plus);
    }
    // drop any pre-release suffix (e.g. "-beta") for the core compare
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);

    final parts = s
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList(growable: false);
    return ReleaseVersion(parts.isEmpty ? const [0] : parts, build);
  }

  static int _firstInt(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
  }
}

/// Compares two semver part lists. Returns a negative number if `a` is older,
/// 0 if equal, a positive number if `a` is newer.
int compareSemver(List<int> a, List<int> b) {
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av < bv ? -1 : 1;
  }
  return 0;
}

/// True iff `(newVer,newBuild)` is strictly newer than `(curVer,curBuild)`.
/// Semver dominates; build number breaks a tie.
bool isReleaseNewer(String curVer, int curBuild, String newVer, int newBuild) {
  final cur = ReleaseVersion.parse(curVer);
  final next = ReleaseVersion.parse(newVer);
  final cmp = compareSemver(cur.parts, next.parts);
  if (cmp != 0) return cmp < 0;
  return curBuild < newBuild;
}

/// Download percent from the bytes already on disk vs the manifest's APK size.
///
/// This is the progress source because netwix.online sits behind Cloudflare, which
/// strips `Content-Length` from `/download/apk` — without it `ota_update` never
/// reports progress and the bar sat at 0% for the whole download.
/// Null when the size is unknown (the bar animates instead of faking 0%).
/// Capped at 99: the plugin's INSTALLING/DONE event is what completes the bar.
int? downloadPercent(int receivedBytes, int totalBytes) {
  if (totalBytes <= 0 || receivedBytes < 0) return null;
  final p = (receivedBytes * 100) ~/ totalBytes;
  return p.clamp(0, 99);
}

/// Result of an update check (netwix.online release manifest), ready for the UI.
///
/// Deliberately carries no release notes: customers are not shown what changed
/// in an update (owner's call), only that a new version exists.
class UpdateInfo {
  const UpdateInfo({
    required this.available,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.tag,
    required this.apkUrl,
    required this.apkSizeBytes,
  });

  final bool available;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String tag;
  final String? apkUrl;
  final int apkSizeBytes;

  /// Human "vX.Y.Z" for display (clean semver, no build suffix).
  String get latestLabel => 'v$latestVersion';

  String get sizeLabel {
    if (apkSizeBytes <= 0) return '';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}
