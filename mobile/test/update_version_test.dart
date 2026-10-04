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

  // Every failure used to say "try again". The messages below are what ota_update
  // actually reported on an Android 14 emulator updating v1.6.1 → v1.6.2.
  group('classifyUpdateFailure', () {
    test('a declined prompt is not a broken update', () {
      // Cancel on "install unknown apps" or on "Do you want to update this app?".
      // ota_update's Dart enum swaps INSTALLATION_ERROR and ALREADY_RUNNING_ERROR,
      // so an install failure arrives named ALREADY_RUNNING_ERROR.
      expect(
          classifyUpdateFailure('ALREADY_RUNNING_ERROR', 'INSTALL_FAILED_ABORTED: User rejected permissions'),
          UpdateFailure.declined);
      expect(classifyUpdateFailure('PERMISSION_NOT_GRANTED_ERROR', 'Permission not granted'),
          UpdateFailure.declined);
    });

    test('an app from another source must be reinstalled, so retrying cannot help', () {
      final f = classifyUpdateFailure('ALREADY_RUNNING_ERROR',
          'INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.netwix.app signatures do not match newer version; ignoring!');
      expect(f, UpdateFailure.signatureMismatch);
      expect(f.offerBrowser, isTrue);
    });

    test('a download still running is named for what it is', () {
      // The swap again: the real ALREADY_RUNNING_ERROR arrives as INSTALLATION_ERROR.
      expect(classifyUpdateFailure('INSTALLATION_ERROR', 'Another download (call) is already running'),
          UpdateFailure.alreadyRunning);
    });

    test('install-side causes read from the message', () {
      expect(classifyUpdateFailure('ALREADY_RUNNING_ERROR', 'INSTALL_FAILED_VERSION_DOWNGRADE'),
          UpdateFailure.downgrade);
      expect(classifyUpdateFailure('ALREADY_RUNNING_ERROR', 'INSTALL_FAILED_INSUFFICIENT_STORAGE'),
          UpdateFailure.storage);
      expect(classifyUpdateFailure('DOWNLOAD_ERROR', 'write failed: ENOSPC (No space left on device)'),
          UpdateFailure.storage);
      expect(classifyUpdateFailure('ALREADY_RUNNING_ERROR', 'INSTALL_FAILED_USER_RESTRICTED: Install canceled by user'),
          UpdateFailure.restricted);
      expect(classifyUpdateFailure('ALREADY_RUNNING_ERROR', 'INSTALL_PARSE_FAILED_NOT_APK'), UpdateFailure.corrupt);
    });

    test('statuses that line up fall back to the name', () {
      expect(classifyUpdateFailure('DOWNLOAD_ERROR', 'Http request finished with status 502'), UpdateFailure.network);
      expect(classifyUpdateFailure('CHECKSUM_ERROR', 'Checksum verification failed'), UpdateFailure.corrupt);
      expect(classifyUpdateFailure('CANCELED', 'Call was canceled using cancel()'), UpdateFailure.cancelled);
      expect(classifyUpdateFailure('INTERNAL_ERROR', null), UpdateFailure.unknown);
    });

    test('the browser is offered only where it gets past the failure', () {
      expect(UpdateFailure.restricted.offerBrowser, isTrue);
      expect(UpdateFailure.unknown.offerBrowser, isTrue);
      expect(UpdateFailure.declined.offerBrowser, isFalse);
      expect(UpdateFailure.network.offerBrowser, isFalse);
    });
  });
}
