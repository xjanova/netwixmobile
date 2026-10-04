import 'package:flutter_test/flutter_test.dart';
import 'package:netwix/services/update_info.dart';

void main() {
  group('isReleaseNewer', () {
    test('newer semver is an update', () {
      expect(isReleaseNewer('1.0.0', 1, '1.0.1', 1), isTrue);
      expect(isReleaseNewer('1.0.0', 5, '1.1.0', 1), isTrue);
      expect(isReleaseNewer('1.9.9', 9, '2.0.0', 0), isTrue);
    });

    test('older or equal semver is NOT an update', () {
      expect(isReleaseNewer('1.0.1', 1, '1.0.0', 1), isFalse);
      expect(isReleaseNewer('2.0.0', 1, '1.9.9', 9), isFalse);
      expect(isReleaseNewer('1.0.0', 3, '1.0.0', 3), isFalse);
    });

    test('build number breaks a same-version tie (the Juntra bug)', () {
      // 0.1.3+7 -> 0.1.3+8 must register as an update.
      expect(isReleaseNewer('0.1.3', 7, '0.1.3', 8), isTrue);
      expect(isReleaseNewer('0.1.3', 8, '0.1.3', 7), isFalse);
    });

    test('tolerates v-prefix and +build in the tag', () {
      final p = ReleaseVersion.parse('v1.2.3+9');
      expect(p.parts, [1, 2, 3]);
      expect(p.build, 9);
      expect(isReleaseNewer('1.2.3', 8, 'v1.2.3+9', 9), isTrue);
    });

    test('handles missing/short parts', () {
      expect(compareSemver([1, 0], [1, 0, 0]), 0);
      expect(compareSemver([1], [1, 0, 1]), -1);
    });
  });

  // The update bar used to sit at 0% for the whole download: Cloudflare strips
  // Content-Length, so the plugin never reported progress. The app now divides the
  // bytes on disk by the manifest's APK size.
  group('downloadPercent', () {
    const apk = 62240328; // the real v1.6.1 APK size from /api/app/version

    test('counts bytes on disk against the manifest size', () {
      expect(downloadPercent(0, apk), 0);
      expect(downloadPercent(apk ~/ 4, apk), 25);
      expect(downloadPercent(apk ~/ 2, apk), 50);
    });

    test('stays below 100 until the installer takes over', () {
      expect(downloadPercent(apk, apk), 99);
      expect(downloadPercent(apk + 4096, apk), 99); // size drifted: never overflows the bar
    });

    test('unknown size is null (animated bar), not a frozen 0%', () {
      expect(downloadPercent(1024, 0), isNull);
      expect(downloadPercent(1024, -1), isNull);
      expect(downloadPercent(-1, apk), isNull);
    });
  });
}
