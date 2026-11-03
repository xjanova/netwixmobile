import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_navigation.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/floating_nav.dart';
import '../widgets/update_sheet.dart';
import 'catalog_grid_screen.dart';
import 'earn_coins_screen.dart';
import 'home_screen.dart';
import 'menu_screen.dart';
import 'shorts_screen.dart';

/// Root shell: the floating tab bar hosting Home / Explore / Shorts / Coins / Profile.
/// Runs a silent auto-update check on first launch.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptUpdate(context);
    });
  }

  /// Back on a non-Home tab returns to Home; back on Home leaves the app WITHOUT closing it.
  ///
  /// The default would be SystemNavigator.pop() → the Activity finishes → Android discards the
  /// task, so re-opening cold-starts at the intro screen and the viewer loses their place. Handing
  /// the press to moveTaskToBack backgrounds the app exactly like the Home button, so it resumes
  /// where it was.
  Future<void> _onBack(bool didPop, Object? _) async {
    if (didPop) return;
    if (_index != 0) {
      setState(() => _index = 0);

      return;
    }
    // If the platform hook is unavailable (iOS, or an install predating the channel), fall back to
    // the framework's own behaviour rather than trapping the user on the screen.
    if (!await AppNavigation.moveTaskToBack() && mounted) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: _buildShell(context, l),
    );
  }

  Widget _buildShell(BuildContext context, L10n l) {
    return Scaffold(
      // The bar floats: pages scroll underneath it and leave kNavClearance at their end.
      extendBody: true,
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              HomeScreen(onOpenExplore: () => setState(() => _index = 1)),
              const CatalogGridScreen(),
              ShortsScreen(active: _index == 2),
              const EarnCoinsScreen(embedded: true),
              const MenuScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: FloatingNavBar(
        index: _index,
        centerIndex: 2,
        onTap: (i) => setState(() => _index = i),
        items: [
          FloatingNavItem(
              icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: l.pick('หน้าแรก', 'Home')),
          FloatingNavItem(
              icon: Icons.search_rounded, activeIcon: Icons.manage_search_rounded, label: l.pick('สำรวจ', 'Explore')),
          FloatingNavItem(
              icon: Icons.play_arrow_rounded, activeIcon: Icons.play_arrow_rounded, label: l.pick('ดูสั้น', 'Shorts')),
          FloatingNavItem(icon: Icons.toll_outlined, activeIcon: Icons.toll_rounded, label: l.pick('เหรียญ', 'Coins')),
          FloatingNavItem(
              icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: l.pick('โปรไฟล์', 'Profile')),
        ],
      ),
    );
  }
}
