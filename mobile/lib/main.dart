import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'screens/intro_screen.dart';
import 'services/account_store.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/auto_updater.dart';
import 'services/catalog_db.dart';
import 'services/cover_healer.dart';
import 'services/debug_reporter.dart';
import 'services/netwix_api.dart';
import 'services/push_service.dart';
import 'services/settings_store.dart';
import 'services/telemetry.dart';
import 'state/app_state.dart';
import 'state/catalog_state.dart';
import 'state/member_state.dart';
import 'state/notification_state.dart';
import 'theme/app_theme.dart';

/// Lets screens refresh when a pushed route (e.g. the player) pops back —
/// used by Home to reload "Continue watching".
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Diagnostics → netwix.online (/api/app/debug). Configure with the running
  // version, then forward framework + async errors so on-device failures
  // (sign-in especially) can be analysed server-side. Never carries secrets.
  try {
    final info = await PackageInfo.fromPlatform();
    DebugReporter.instance.configure(appVersion: info.version);
  } catch (_) {/* version is best-effort */}
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    priorOnError?.call(details);
    unawaited(debugReport('flutter.error',
        level: 'error',
        message: details.exceptionAsString(),
        context: {'library': details.library ?? ''}));
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    unawaited(debugReport('uncaught', level: 'error', message: error.toString()));
    return false;
  };
  unawaited(debugReport('app.launch'));

  // Content + playback both come from NetWix now (netwix.online/api/app/*).
  // NetWix resolves each episode's stream server-side on demand (a fresh signed
  // CDN mp4 for rongyok, an HLS proxy for wow-drama), so it plays from any IP —
  // fixing the stale/expired links that broke playback when the app scraped
  // rongyok directly. Playback uses the platform-default video_player backend
  // (ExoPlayer on Android); the fvp/ffmpeg backend tried in 1.0.9 broke ALL
  // playback and was removed.

  // Cap the in-memory image cache: poster grids decode a LOT of images and the
  // Flutter default (100MB) lets a long browse session balloon the heap on
  // low-RAM devices. Disk cache (cached_network_image) is unaffected.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20; // 64MB

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  final settings = await SettingsStore.load();
  // Drop the old device-local "Pro" bool — it was self-granted and bypassed both
  // ads and the episode paywall. Pro now comes from the server only.
  await settings.clearLegacyProFlag();
  final api = NetwixApi();
  // Broken/missing covers get reported from the cards that fail to show them.
  CoverHealer.instance.configure(api);
  final db = await CatalogDb.open();
  final accountStore = await AccountStore.load();
  final adFrequency = await AdFrequency.load();
  final memberState = MemberState(accountStore, api, AuthService(api))..init();
  final notifications = NotificationState(api, settings)..start();

  // Anonymous device statistics (disclosed in the privacy policy) — after the
  // token is applied so a signed-in launch links the install to the account.
  unawaited(Telemetry.report(api, settings));

  // FCM push — best-effort; the in-app inbox still works without it.
  unawaited(PushService.init(settings, notifications));

  runApp(HiveApp(
    settings: settings,
    api: api,
    db: db,
    memberState: memberState,
    adFrequency: adFrequency,
    notifications: notifications,
  ));
}

class HiveApp extends StatelessWidget {
  const HiveApp({
    super.key,
    required this.settings,
    required this.api,
    required this.db,
    required this.memberState,
    required this.adFrequency,
    required this.notifications,
  });

  final SettingsStore settings;
  final NetwixApi api;
  final CatalogDb db;
  final MemberState memberState;
  final AdFrequency adFrequency;
  final NotificationState notifications;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(settings)),
        ChangeNotifierProvider(create: (_) => CatalogState(api, db)),
        ChangeNotifierProvider.value(value: memberState),
        ChangeNotifierProvider.value(value: notifications),
        Provider<AdFrequency>.value(value: adFrequency),
        Provider<NetwixApi>.value(value: api),
        Provider<CatalogDb>(create: (_) => db),
        Provider<AutoUpdater>(create: (_) => AutoUpdater()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'NetWix',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          navigatorObservers: [routeObserver],
          home: const IntroScreen(),
        ),
      ),
    );
  }
}
