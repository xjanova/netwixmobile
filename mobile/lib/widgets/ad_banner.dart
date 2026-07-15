import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_service.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Rotating ad banner. Renders nothing when the user is Pro (ad-free) or when
/// no ad is available. Everything is free to watch — this is the only place ads
/// appear, and Pro (129฿/mo) removes them.
class AdBanner extends StatelessWidget {
  const AdBanner({super.key, this.placement = 'player', this.height = 64});

  final String placement;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Ad-free for locally-purchased Pro OR a server plan (incl. referral-granted
    // free Pro), so redeeming the invite promo actually removes ads.
    if (context.watch<MemberState>().isPro) return const SizedBox.shrink();

    final ads = context.watch<AdService>();
    final ad = ads.current(placement);
    if (ad == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: ad.clickUrl == null ? null : () => _open(ad.clickUrl!),
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.hairline),
          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: CachedNetworkImage(
                key: ValueKey(ad.id),
                imageUrl: ad.imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: 6,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('โฆษณา · Ad',
                    style: AppTheme.body(9, color: Colors.white70, height: 1.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
