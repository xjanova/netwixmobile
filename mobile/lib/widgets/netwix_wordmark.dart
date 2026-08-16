import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The NetWix lockup: the play mark beside the wordmark.
///
/// This replaces a 208 KB baked PNG whose type was set in a font the app doesn't use, whose "i"
/// dot sat off its stem, and which carried a permanent purple halo — the halo in particular gave
/// away that it was exported art rather than part of the interface. Composing the lockup from the
/// mark asset plus live text fixes all of that at once: the type is the app's own Kanit at every
/// size, it stays crisp on any density instead of resampling, and it re-tints with the theme.
///
/// [height] drives everything else, so callers size it the way they sized the old image.
class NetwixWordmark extends StatelessWidget {
  const NetwixWordmark({super.key, this.height = 28, this.opacity = 1.0});

  final double height;

  /// For the player watermark, which sits over video and must never fight the picture.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // The mark reads a touch small next to cap-height letterforms, so it runs slightly taller
    // than the text — the usual optical correction for a glyph paired with a symbol.
    final markSize = height * 1.06;
    final textSize = height * 0.74;

    return Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/brand/netwix-icon.png',
            height: markSize,
            width: markSize,
            filterQuality: FilterQuality.medium,
          ),
          SizedBox(width: height * 0.18),
          // Tight tracking keeps the lockup compact; the gradient runs crimson→violet across the
          // word so the mark and the type read as one object rather than two stacked brands.
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [T.textPrimary, T.textPrimary, T.purpleHi],
              stops: [0.0, 0.55, 1.0],
            ).createShader(r),
            child: Text(
              'netwix',
              style: AppTheme.display(
                textSize,
                weight: FontWeight.w800,
                color: Colors.white,
              ).copyWith(letterSpacing: -textSize * 0.035, height: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
