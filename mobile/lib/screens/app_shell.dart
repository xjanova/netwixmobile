import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/update_sheet.dart';
import 'catalog_grid_screen.dart';
import 'earn_coins_screen.dart';
import 'home_screen.dart';
import 'menu_screen.dart';

/// Root shell: bottom tab bar hosting Home / Explore / Menu.
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
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              HomeScreen(onOpenExplore: () => setState(() => _index = 1)),
              const CatalogGridScreen(),
              const EarnCoinsScreen(embedded: true),
              const MenuScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          _NavItem(Icons.home_rounded, l.pick('หน้าแรก', 'Home')),
          _NavItem(Icons.travel_explore_rounded, l.pick('สำรวจ', 'Explore')),
          _NavItem(Icons.monetization_on_rounded, l.pick('หาเหรียญ', 'Coins')),
          _NavItem(Icons.menu_rounded, l.pick('เมนู', 'Menu')),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Was a flat warm-dark fill (0E0B07) on a cool near-black theme — subtly off-brand and
        // completely flat. A short vertical gradient plus a lifted top hairline reads as a bar
        // sitting ABOVE the content rather than a strip painted onto it.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF21A1428), Color(0xFA0B0712)],
        ),
        border: Border(top: BorderSide(color: T.hairlineStrong)),
        boxShadow: [
          BoxShadow(color: Color(0x8C000000), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
      height: 66 + MediaQuery.of(context).viewPadding.bottom,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: _navTile(items[i], i == index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navTile(_NavItem item, bool active) {
    // Animated so switching tabs has a beat to it. Nothing here moved before — the icon simply
    // swapped colour, which is the flattest possible way to show state.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Accent bloom behind the active tab — the depth cue that tells you which tab you
              // are on from the corner of your eye, without adding another line to the bar.
              AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 240),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [T.accent.withValues(alpha: 0.34), Colors.transparent],
                    ),
                  ),
                ),
              ),
              HexBox(
                size: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active ? T.accent.withValues(alpha: 0.22) : Colors.transparent,
                  ),
                  child: Icon(item.icon,
                      size: 15, color: active ? T.accent : const Color(0xFF6B6280)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: AppTheme.body(9,
                weight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? T.textPrimary : T.textInactive),
            child: Text(item.label),
          ),
          const SizedBox(height: 3),
          // A short accent underline anchors the active tab to the bar's top edge.
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            height: 2,
            width: active ? 16 : 0,
            decoration: BoxDecoration(
              color: T.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
