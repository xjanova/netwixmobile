import 'package:flutter/material.dart';

import '../models/content.dart';
import '../screens/series_detail_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'poster_image.dart';

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
    return GestureDetector(
      onTap: () => openContent(context, content),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: content.displayImageUrl, seed: content.id),
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
            PosterImage(url: content.heroImageUrl, seed: content.id + 1),
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
