import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A full-bleed atmospheric layer behind a screen's content.
///
/// The app was built entirely from flat fills, which is the single biggest reason it read as
/// machine-assembled: real products put something behind the interface so it has air and depth.
/// These are generated brand-palette gradients (near-black with crimson/violet haze), deliberately
/// low-contrast so they never compete with poster artwork or text.
///
/// The image sits UNDER a scrim tuned per screen, so type contrast is guaranteed by the scrim
/// rather than by hoping the artwork happens to be dark where the words land.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.asset,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.opacity = 1.0,
    this.scrim = 0.45,
  });

  /// e.g. 'assets/art/onboarding-bg.webp'
  final String asset;
  final Widget child;
  final Alignment alignment;

  /// Dims the art itself. Use below 1 where content is dense.
  final double opacity;

  /// Black wash over the art. This is what protects legibility — raise it, don't dim the art,
  /// when text sits on top.
  final double scrim;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: T.screenBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: opacity,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: alignment,
                // The art is a smooth gradient, so a low-res decode is invisible and keeps a
                // full-screen image off the raster cache budget.
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
          if (scrim > 0)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: scrim)),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
