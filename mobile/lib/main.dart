import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/intro_screen.dart';
import 'services/account_store.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/auto_updater.dart';
import 'services/catalog_db.dart';
import 'services/netwix_api.dart';
import 'services/netwix_client.dart';
import 'services/settings_store.dart';
import 'state/app_state.dart';
import 'state/catalog_state.dart';
import 'state/member_state.dart';
import 'theme/app_theme.dart';

/// Lets screens refresh when a pushed route (e.g. the player) pops back —
/// used by Home to reload "Continue watching".
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Content + playback both come from NetWix now (netwix.online/api/app/*).
  // NetWix resolves each episode's stream server-side on demand (a fresh signed
  // CDN mp4 for rongyok, an HLS proxy for wow-drama), so it plays from any IP —
  // fixing the stale/expired links that broke playback when the app scraped
  // rongyok directly. Playback uses the platform-default video_player backend
  // (ExoPlayer on Android); the fvp/ffmpeg backend tried in 1.0.9 broke ALL
  // playback and was removed.

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  final settings = await SettingsStore.load();
  final api = NetwixApi();
  final db = await CatalogDb.open();
  final accountStore = await AccountStore.load();
  final netwix = NetwixClient();
  final memberState = MemberState(accountStore, netwix, AuthService(netwix))..init();

  runApp(HiveApp(
      settings: settings, api: api, db: db, netwix: netwix, memberState: memberState));
}

class HiveApp extends StatelessWidget {
  const HiveApp({
    super.key,
    required this.settings,
    required this.api,
    required this.db,
    required this.netwix,
    required this.memberState,
  });

  final SettingsStore settings;
  final NetwixApi api;
  final CatalogDb db;
  final NetwixClient netwix;
  final MemberState memberState;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(settings)),
        ChangeNotifierProvider(create: (_) => CatalogState(api, db)),
        ChangeNotifierProvider.value(value: memberState),
        // Ad delivery (main.thaiprompt.online). Starts fetching+rotating now;
        // a silent no-op until the ad backend goes live.
        ChangeNotifierProvider(create: (_) => AdService()..start(placements: const ['player', 'home'])),
        Provider<NetwixApi>.value(value: api),
        Provider<CatalogDb>(create: (_) => db),
        Provider<NetwixClient>.value(value: netwix),
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
