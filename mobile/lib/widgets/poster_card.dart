import 'package:flutter/material.dart';

import '../models/content.dart';
import '../screens/series_detail_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'poster_image.dart';
import 'pressable.dart';

void openContent(BuildContext context, Content c) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(content: c)));
}

/// Access badge for a poster: VIP (gold-unlock) or the 18+/20+ rating, or null
/// for an ordinary title.
///
/// VIP and adult are the SAME 343 titles today (adult == the VIP zone), so 18+
/// wins the label — it's the more meaningful warning — and VIP is implied by the
/// gold pip. Guests never receive these titles at all; the badge is for members.
Widget? lockBadge(Content c) {
  if (c.isAdult) {
    return Pill(
      text: c.maturity.isNotEmpty ? c.maturity : '18+',
      color: const Color(0xFFC81E45),
      filled: true,
      textColor: Colors.white,
    );
  }
  if (c.isVip) {
    return const Pill(text: '🥇 VIP', color: Colors.black54, filled: true, textColor: Colors.white);
  }
  return null;
}

/// Portrait poster card used in the vertical rail and grid.
class PortraitPosterCard extends StatelessWidget {
  const PortraitPosterCard({super.key, required this.content, this.width = 118});
  final Content content;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => openContent(context, content),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                // Two shadows, not one: a tight dark contact shadow anchors the card to the
                // background, a wide soft one gives it height. A single mid shadow is what makes
                // dark UIs look like flat stickers on a flat sheet.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(T.rMedia),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
                    BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, 9)),
                  ],
                ),
                child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: content.displayImageUrl, seed: content.id, title: content.title),
                  // Grounding scrim: the bottom pills sat on raw artwork and could land on a pale
                  // frame, and the fade also stops the poster ending in a hard edge.
                  const _PosterScrim(),
                  // Rim light — brighter along the top edge, as if lit from above. This is the cue
                  // that separates one card from the next in a dense grid.
                  _RimLight(radius: T.rMedia),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Pill(text: content.typeThai, filled: true),
                  ),
                  // Access badge, top-right so it clears the type/views pills.
                  // Without it a VIP/18+ title looked ordinary right up until
                  // playback failed.
                  if (lockBadge(content) case final badge?)
                    Positioned(right: 6, top: 6, child: badge),
                  if (content.views > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Pill(text: '${content.viewsText} 👁', color: Colors.black54, filled: true, textColor: Colors.white),
                    ),
                ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              content.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(12.5, weight: FontWeight.w600, color: T.textPrimary),
            ),
            if (content.yearText.isNotEmpty)
              Text(content.yearText, style: AppTheme.body(10.5, color: T.textFaint)),
          ],
        ),
      ),
    );
  }
}

/// Wide 16:9 featured card for the "new / popular" section.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key, required this.content});
  final Content content;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openContent(context, content),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(url: content.heroImageUrl, seed: content.id + 1, title: content.title),
            // left-dark gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(T.rMedia),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC0B0B0C), Colors.transparent],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // "ดูฟรี" would be a lie on a VIP/18+ title — those need a
                    // purchase or Pro, so badge them instead.
                    if (lockBadge(content) case final badge?)
                      badge
                    else
                      const Pill(text: 'ดูฟรี', filled: true),
                    const SizedBox(width: 6),
                    Pill(text: content.typeThai, color: Colors.black54, filled: true, textColor: Colors.white),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.display(18, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: T.accentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: T.accentGlow, blurRadius: 20, spreadRadius: -6)],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: T.onAccent, size: 26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Bottom-to-top darkening over a poster, so overlaid pills stay legible on any artwork.
class _PosterScrim extends StatelessWidget {
  const _PosterScrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xB3000000), Color(0x2E000000), Colors.transparent],
            stops: [0.0, 0.28, 0.55],
          ),
        ),
      );
}

/// Hairline edge that catches light at the top and fades by the bottom — a cheap, convincing
/// bevel. Drawn as a border rather than a stroke so it never costs a saveLayer while scrolling.
class _RimLight extends StatelessWidget {
  const _RimLight({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: const GradientBoxBorder(),
          ),
        ),
      );
}

/// A 1px border whose colour fades top→bottom.
class GradientBoxBorder extends BoxBorder {
  const GradientBoxBorder();

  @override
  BorderSide get top => BorderSide.none;
  @override
  BorderSide get bottom => BorderSide.none;
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  bool get isUniform => false;

  @override
  void paint(Canvas canvas, Rect rect,
      {TextDirection? textDirection, BoxShape shape = BoxShape.rectangle, BorderRadius? borderRadius}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x2EFFFFFF), Color(0x0AFFFFFF), Color(0x00FFFFFF)],
        stops: [0.0, 0.4, 1.0],
      ).createShader(rect);
    final rrect = (borderRadius ?? BorderRadius.zero).toRRect(rect).deflate(0.5);
    canvas.drawRRect(rrect, paint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
