import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The 3D icon set drawn for NetWix (ChatGPT image sheets, cut by
/// `design/icons-src/slice.py`). One file per name in `assets/icons3d/`.
enum Ic3 {
  coins,
  checkin,
  newTitles('new_titles'),
  passport,
  share,
  friends,
  clip,
  trophy,
  gift,
  profiles,
  mylist,
  wallet,
  bell,
  update,
  account,
  crown,
  shield,
  language;

  const Ic3([this._file]);
  final String? _file;

  String get asset => 'assets/icons3d/${_file ?? name}.webp';

  /// The icon for a server reward campaign's `kind` (daily / watch / categories / share / referral).
  static Ic3 forCampaign(String kind) => switch (kind) {
        'daily' => Ic3.checkin,
        'watch' => Ic3.newTitles,
        'categories' => Ic3.passport,
        'share' => Ic3.share,
        'referral' => Ic3.friends,
        _ => Ic3.gift,
      };
}

/// A 3D icon, optionally seated on a soft glass tile with a brand glow.
class Icon3D extends StatelessWidget {
  const Icon3D(this.icon, {super.key, this.size = 44, this.tile = true, this.done = false});

  final Ic3 icon;
  final double size;

  /// Seat the icon on a rounded glass tile (list rows); false = the bare render (heroes).
  final bool tile;

  /// Finished for this period: desaturate the art and pin a check badge on it.
  final bool done;

  @override
  Widget build(BuildContext context) {
    Widget art = Image.asset(
      icon.asset,
      width: tile ? size * 0.82 : size,
      height: tile ? size * 0.82 : size,
      filterQuality: FilterQuality.medium,
      // A missing asset must never take a row down with it.
      errorBuilder: (_, _, _) => Icon(Icons.auto_awesome_rounded, color: T.accent, size: size * 0.5),
    );
    if (done) {
      art = Opacity(opacity: 0.55, child: ColorFiltered(colorFilter: _greyish, child: art));
    }
    if (!tile && !done) return art;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (tile)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.3),
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.5),
                    radius: 1.1,
                    colors: done
                        ? const [Color(0x14FFFFFF), Color(0x08FFFFFF)]
                        : const [Color(0x33FF2D55), Color(0x14B026FF)],
                  ),
                  border: Border.all(color: done ? T.hairline : const Color(0x33FF6B85)),
                ),
              ),
            ),
          art,
          if (done)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.36,
                height: size * 0.36,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: T.screen, width: 2),
                ),
                child: Icon(Icons.check_rounded, size: size * 0.24, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  static const _greyish = ColorFilter.matrix(<double>[
    0.5, 0.4, 0.1, 0, 0, //
    0.3, 0.6, 0.1, 0, 0, //
    0.3, 0.4, 0.3, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}
