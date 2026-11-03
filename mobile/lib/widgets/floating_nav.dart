import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Space a tab's scrolling content must leave at the bottom so its last row clears the floating bar.
const double kNavClearance = 104;

class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The bottom bar: a frosted glass capsule floating above the content, with a raised gradient
/// button in the middle slot. Content scrolls underneath it (the shell uses `extendBody`).
///
/// The widget is taller than the capsule so the raised button stays tappable: the empty strip
/// above the capsule hits nothing and lets touches through to the page behind it.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
    required this.centerIndex,
  });

  final List<FloatingNavItem> items;
  final int index;
  final int centerIndex;
  final ValueChanged<int> onTap;

  static const double _barHeight = 70;
  static const double _lift = 30;
  static const double _centerSize = 60;

  void _tap(int i) {
    if (i != index) HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return SizedBox(
      height: _barHeight + _lift + 14 + bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: 14 + bottom,
            height: _barHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(color: Color(0xE6000000), blurRadius: 40, offset: Offset(0, 20), spreadRadius: -14),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xC71A122A),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: i == centerIndex
                                ? _centerLabel(items[i], i == index)
                                : _tab(items[i], i == index, () => _tap(i)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The raised centre button sits over the capsule's middle slot.
          Positioned(
            bottom: 14 + bottom + _barHeight - _centerSize / 2 - 2,
            left: 0,
            right: 0,
            child: Center(child: _centerButton(items[centerIndex], centerIndex == index)),
          ),
        ],
      ),
    );
  }

  Widget _tab(FloatingNavItem item, bool active, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x52FF2D55), Color(0x52B026FF)],
                    )
                  : null,
              border: Border.all(color: active ? const Color(0x66FF6B85) : Colors.transparent),
              boxShadow: active ? const [BoxShadow(color: Color(0x59FF2D55), blurRadius: 18)] : const [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? item.activeIcon : item.icon,
                    size: 24, color: active ? Colors.white : const Color(0xFF9A91B0)),
                const SizedBox(height: 2),
                Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: AppTheme.body(11,
                        weight: FontWeight.w600, color: active ? Colors.white : const Color(0xFF9A91B0))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The label under the raised button; the button itself is drawn above the capsule.
  Widget _centerLabel(FloatingNavItem item, bool active) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(centerIndex),
      child: Align(
        alignment: const Alignment(0, 0.72),
        child: Text(item.label,
            style: AppTheme.body(11, weight: FontWeight.w600, color: active ? Colors.white : const Color(0xFF9A91B0))),
      ),
    );
  }

  Widget _centerButton(FloatingNavItem item, bool active) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _tap(centerIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: _centerSize,
          height: _centerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: T.accentGradient,
            border: Border.all(color: T.screen, width: 4),
            boxShadow: [
              BoxShadow(color: T.accent.withValues(alpha: active ? 0.85 : 0.5), blurRadius: 26, offset: const Offset(0, 10)),
              if (active) const BoxShadow(color: Color(0x8CFF6B85), spreadRadius: 3),
            ],
          ),
          child: Icon(active ? item.activeIcon : item.icon, size: 30, color: Colors.white),
        ),
      ),
    );
  }
}
