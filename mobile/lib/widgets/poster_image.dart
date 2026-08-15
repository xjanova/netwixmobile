import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Poster/artwork image with a cinematic gradient fallback (used while loading
/// and when a title has no artwork). NetWix serves public poster/backdrop URLs,
/// so no auth header is needed.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.url,
    this.seed = 0,
    this.fit = BoxFit.cover,
    this.radius = T.rMedia,
    this.memCacheWidth = 400,
  });

  final String url;
  final int seed;
  final BoxFit fit;
  final double radius;

  /// Decode width cap. Posters render at ~118-200 logical px, so decoding the
  /// full-size artwork into memory (the default) wastes tens of MB across a
  /// grid. 400px covers 3x-density screens; pass a larger cap for hero images.
  final int memCacheWidth;

  /// Percent-encode a URL whose path still carries raw UTF-8.
  ///
  /// About 2,000 titles hotlink a cover with a Thai filename, and the sources serve those from
  /// nginx, which answers **400** to raw UTF-8 in a path. A browser encodes before it sends, so the
  /// website never saw this — the app handed the string straight to the HTTP client and got a 400,
  /// which is why so many covers fell back to the gradient (owner, 2026-08-16).
  ///
  /// The API now encodes these server-side, so this is a belt-and-braces guard: it keeps already-
  /// encoded and plain-ASCII URLs byte-identical (so the disk cache key doesn't change and nothing
  /// re-downloads), and only rewrites a URL the server hasn't fixed — an old cached response, or a
  /// build talking to an older backend.
  /// Only the path is touched — host, query and fragment are copied through verbatim, so a signed
  /// URL keeps its signature byte-for-byte. Each segment is decoded before it is re-encoded, which
  /// makes the transform idempotent: an already-correct URL comes back unchanged.
  static String _safeUrl(String url) {
    final schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return url;
    final pathStart = url.indexOf('/', schemeEnd + 3);
    if (pathStart < 0) return url;

    var end = url.length;
    for (final mark in ['?', '#']) {
      final at = url.indexOf(mark, pathStart);
      if (at >= 0 && at < end) end = at;
    }

    final path = url.substring(pathStart, end);
    if (path.codeUnits.every((c) => c < 0x80)) return url; // already ASCII — nothing to do

    try {
      final encoded = path
          .split('/')
          .map((s) => Uri.encodeComponent(Uri.decodeComponent(s)))
          .join('/');

      return url.substring(0, pathStart) + encoded + url.substring(end);
    } catch (_) {
      return url; // malformed escape — leave it to the server/CDN to reject
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: T.posterFill(seed)),
    );

    final Widget img = url.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: _safeUrl(url),
            fit: fit,
            memCacheWidth: memCacheWidth,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
            fadeInDuration: const Duration(milliseconds: 200),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(child: img),
    );
  }
}
