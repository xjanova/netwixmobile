import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'netwix_api.dart';
import 'update_info.dart';

/// Progress of an in-flight update install.
class UpdateProgress {
  const UpdateProgress(this.phase, {this.percent, this.failure});
  final UpdatePhase phase;
  final int? percent;

  /// Set with [UpdatePhase.error]: what went wrong, so the sheet can say what to do.
  final UpdateFailure? failure;
}

enum UpdatePhase { downloading, installing, done, error }

/// In-app self-update: reads the latest release manifest from netwix.online,
/// compares versions, and (on Android) downloads + installs the APK via
/// `ota_update`.
///
/// Distribution is sideloaded (NOT Play Store), so we use `ota_update` rather
/// than `in_app_update`. Both the version check (`/api/app/version`) and the APK
/// download (`/download/apk`) go entirely through our own domain — the app never
/// contacts or reveals where the binary is actually built. Because every release
/// keeps the same `applicationId` and signing key, Android installs the new APK
/// over the old one and **user data is preserved**.
class AutoUpdater {
  AutoUpdater({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json'},
            ));

  /// Version manifest on our own API (`https://netwix.online/api/app/version`).
  static String get versionApi => '${NetwixApi.baseUrl}/version';

  /// Where the APK is downloaded from — a fixed route on our own domain that
  /// mirrors + streams the latest build. Kept as our canonical origin (not a
  /// server-supplied link) so the download target can never point off-domain.
  /// `?src=update` marks this as an in-app self-update so the web excludes it from
  /// the website APK-download count (an update is not a new download).
  static String get apkDownloadUrl => '${NetwixApi.origin}/download/apk?src=update';

  final Dio _dio;

  /// Library-global guard so two concurrent checks can't fire two network calls
  /// and stack two update sheets (learned from Juntra's double-tap bug).
  static bool _checkInFlight = false;

  /// Asks our API for the latest release and reports whether it's newer than the
  /// running build. Returns null on any network/parse failure (callers show a
  /// generic message — never a raw exception, and never anything off-domain).
  Future<UpdateInfo?> checkForUpdate() async {
    if (_checkInFlight) return null;
    _checkInFlight = true;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final curVer = pkg.version; // e.g. "1.0.0"
      final curBuild = int.tryParse(pkg.buildNumber) ?? 0;

      final resp = await _dio.get<Map<String, dynamic>>(versionApi);
      final body = resp.data;
      // Envelope: {success, data}. A null `data` means "no release / up to date".
      final data = (body != null &&
              body['success'] == true &&
              body['data'] is Map)
          ? (body['data'] as Map).cast<String, dynamic>()
          : null;
      if (data == null) return null;

      final tag = (data['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty) return null;

      final parsed = ReleaseVersion.parse(tag);
      final latestVersion = parsed.parts.join('.');
      final latestBuild = parsed.build;
      // `notes` is ignored on purpose — release details are never shown to customers.
      final apkSize = (data['size'] as num?)?.toInt() ?? 0;

      final available =
          isReleaseNewer(curVer, curBuild, latestVersion, latestBuild);

      return UpdateInfo(
        available: available,
        currentVersion: curVer,
        currentBuild: curBuild,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        tag: tag,
        // Always our own domain — see [apkDownloadUrl].
        apkUrl: available ? apkDownloadUrl : null,
        apkSizeBytes: apkSize,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('checkForUpdate failed: $e');
      return null;
    } finally {
      _checkInFlight = false;
    }
  }

  /// Downloads and installs the APK, streaming progress.
  ///
  /// `ota_update` only reports download progress when the response carries
  /// `Content-Length`, and Cloudflare strips it from `/download/apk` — so the bar
  /// sat at 0% for the whole download. We therefore also watch the file the plugin
  /// is writing and divide by the manifest's exact APK size ([downloadPercent]).
  /// When the plugin does report a percent, it wins and the polling stops.
  ///
  /// Status handling is intentionally forgiving: we categorise by the enum's
  /// *name* (contains "ERROR"/"DONE") so a future plugin version that adds a new
  /// [OtaStatus] can't break the compile or silently mis-route (Juntra lesson).
  Stream<UpdateProgress> downloadAndInstall(UpdateInfo info) {
    final url = info.apkUrl;
    if (url == null) {
      return Stream.value(
          const UpdateProgress(UpdatePhase.error, failure: UpdateFailure.unknown));
    }

    final filename = 'netwix-${info.latestVersion}.apk';
    late final StreamController<UpdateProgress> out;
    StreamSubscription<OtaEvent>? ota;
    Timer? poll;
    // Set when the sheet stops listening. `out.isClosed` would NOT flip on a cancel,
    // so start() checks this after its awaits — or it would still arm the timer.
    var cancelled = false;
    // Once Android has the APK there is nothing left to cancel.
    var installing = false;

    void emit(UpdateProgress p) {
      if (!cancelled && !out.isClosed) out.add(p);
    }

    void stopPolling() {
      poll?.cancel();
      poll = null;
    }

    void fail(UpdateFailure failure) {
      stopPolling();
      emit(UpdateProgress(UpdatePhase.error, failure: failure));
    }

    Future<void> start() async {
      // ota_update writes to <dataDir>/files/ota_update/<filename>; on Android that
      // `files` dir is path_provider's application-support directory.
      File? apk;
      try {
        final dir = await getApplicationSupportDirectory();
        apk = File('${dir.path}/ota_update/$filename');
        // A partial file from an earlier attempt would read as instant progress.
        if (await apk.exists()) await apk.delete();
      } catch (e) {
        if (kDebugMode) debugPrint('update progress file: $e');
        apk = null; // no file progress — the bar animates instead
      }
      if (cancelled) return; // sheet closed while we resolved the path

      final file = apk;
      if (file != null && info.apkSizeBytes > 0) {
        var last = -1;
        var reading = false;
        poll = Timer.periodic(const Duration(milliseconds: 400), (_) async {
          if (reading) return;
          reading = true;
          try {
            if (await file.exists()) {
              final pct = downloadPercent(await file.length(), info.apkSizeBytes);
              // `poll != null`: installing may have started while we awaited the read.
              if (pct != null && pct > last && poll != null) {
                last = pct;
                emit(UpdateProgress(UpdatePhase.downloading, percent: pct));
              }
            }
          } catch (_) {
            // the plugin replaced the file mid-read — the next tick reads it again
          } finally {
            reading = false;
          }
        });
      }

      try {
        ota = OtaUpdate()
            .execute(url, destinationFilename: filename, usePackageInstaller: true)
            .listen(
          (event) {
            final name = event.status.name; // e.g. "DOWNLOADING"
            if (name == 'DOWNLOADING') {
              final pct = int.tryParse(event.value ?? '');
              if (pct != null) {
                stopPolling(); // the plugin has an exact count — use it
                emit(UpdateProgress(UpdatePhase.downloading, percent: pct));
              }
            } else if (name == 'INSTALLING') {
              installing = true;
              stopPolling();
              emit(const UpdateProgress(UpdatePhase.installing));
            } else if (name.contains('DONE')) {
              stopPolling();
              emit(const UpdateProgress(UpdatePhase.done));
            } else if (name.contains('ERROR') || name == 'CANCELED') {
              if (kDebugMode) debugPrint('update failed: $name ${event.value}');
              fail(classifyUpdateFailure(name, event.value));
            }
          },
          onError: (Object e) {
            if (kDebugMode) debugPrint('downloadAndInstall stream error: $e');
            fail(UpdateFailure.unknown);
          },
          onDone: () {
            stopPolling();
            if (!out.isClosed) out.close();
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('downloadAndInstall failed: $e');
        fail(UpdateFailure.unknown);
      }
    }

    out = StreamController<UpdateProgress>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        cancelled = true;
        stopPolling();
        await ota?.cancel();
        // Dropping our listener does not stop the plugin's download: it kept running
        // unseen, and every new attempt failed with "already running" until it finished
        // and an install prompt popped up from nowhere. Stop it so a retry starts clean.
        if (!installing) {
          try {
            await OtaUpdate().cancel();
          } catch (e) {
            if (kDebugMode) debugPrint('cancel update download: $e');
          }
        }
      },
    );
    return out.stream;
  }
}
