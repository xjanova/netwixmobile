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

/// Why an update attempt failed. Every failure used to read "อัปเดตไม่สำเร็จ
/// ลองใหม่อีกครั้ง", and trying again never helps when the cause is a declined
/// prompt, a signature mismatch or a full disk — the viewer just kept tapping.
enum UpdateFailure {
  /// "Install unknown apps" was declined, or Android's install prompt was cancelled.
  declined,

  /// The installed app was signed by someone else (a build from a computer, another
  /// store): Android will not install over it until it is uninstalled.
  signatureMismatch,

  /// The installed build is newer than the release.
  downgrade,
  storage,

  /// The device or its maker (e.g. MIUI) blocks apps from installing updates themselves.
  restricted,
  network,
  corrupt,
  alreadyRunning,
  cancelled,
  unknown;

  /// Whether downloading through the browser gets past it — the system installer
  /// path works where an app-driven install session is blocked.
  bool get offerBrowser =>
      this == signatureMismatch || this == restricted || this == unknown;
}

/// Classifies a failed `ota_update` event from its status name and platform message.
///
/// The message is read first because the names can't all be trusted: ota_update
/// 7.1.0's Dart enum lists ALREADY_RUNNING_ERROR before INSTALLATION_ERROR while its
/// Java enum has them the other way round, so an install failure arrives in Dart
/// named ALREADY_RUNNING_ERROR. The other statuses line up.
UpdateFailure classifyUpdateFailure(String statusName, String? message) {
  final m = (message ?? '').toUpperCase();
  if (m.contains('UPDATE_INCOMPATIBLE') || m.contains('SIGNATURES DO NOT MATCH')) {
    return UpdateFailure.signatureMismatch;
  }
  if (m.contains('VERSION_DOWNGRADE')) return UpdateFailure.downgrade;
  if (m.contains('INSUFFICIENT_STORAGE') || m.contains('NO SPACE LEFT') || m.contains('ENOSPC')) {
    return UpdateFailure.storage;
  }
  if (m.contains('USER_RESTRICTED')) return UpdateFailure.restricted;
  if (m.contains('ALREADY RUNNING')) return UpdateFailure.alreadyRunning;
  // "INSTALL_FAILED_ABORTED: User rejected permissions" — both the unknown-sources
  // prompt and the "Do you want to update this app?" prompt end this way.
  if (m.contains('ABORTED') || m.contains('REJECTED')) return UpdateFailure.declined;
  if (m.contains('INSTALL_PARSE_FAILED') || m.contains('INVALID_APK')) return UpdateFailure.corrupt;

  switch (statusName) {
    case 'PERMISSION_NOT_GRANTED_ERROR':
      return UpdateFailure.declined;
    case 'CANCELED':
      return UpdateFailure.cancelled;
    case 'CHECKSUM_ERROR':
      return UpdateFailure.corrupt;
    case 'DOWNLOAD_ERROR':
      return UpdateFailure.network;
  }
  return UpdateFailure.unknown;
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
