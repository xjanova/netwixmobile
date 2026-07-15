/// A pre-roll ad campaign, as the server picked it for this title + viewer
/// (`GET /api/app/content/{id}/ad`, mirroring `AdCampaign::toPlayerPayload()`).
///
/// Targeting, scheduling and hide_for_pro are all decided SERVER-side — if the
/// app receives an ad, it shows it. The only client-side decision is [frequency],
/// which is inherently per-device.
class PrerollAd {
  const PrerollAd({
    required this.id,
    required this.mediaType,
    this.src,
    this.youtube,
    this.caption,
    this.linkUrl,
    this.skippable = true,
    this.skipAfter = 5,
    this.imageSeconds = 5,
    this.frequency = 'always',
  });

  final int id;

  /// image | video
  final String mediaType;

  /// Resolved image or direct-video URL. Null when the creative is a YouTube
  /// link — [youtube] carries the id instead.
  final String? src;

  /// YouTube video id when the creative is a YouTube link.
  final String? youtube;

  final String? caption;

  /// Optional destination opened when the viewer taps the ad.
  final String? linkUrl;

  /// Whether a skip button appears at all. When false the ad must play out.
  final bool skippable;

  /// Seconds before the skip button becomes active.
  final int skipAfter;

  /// How long an image creative stays up (server floors this at 3).
  final int imageSeconds;

  /// always | session | daily — how often this campaign may be shown per device.
  final String frequency;

  bool get isImage => mediaType == 'image';
  bool get isYoutube => (youtube?.isNotEmpty ?? false);

  /// Nothing to render — treat as "no ad" rather than showing a blank overlay.
  bool get isEmpty => !isYoutube && (src == null || src!.isEmpty);

  static PrerollAd? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final ad = PrerollAd(
      id: (j['id'] as num?)?.toInt() ?? 0,
      mediaType: (j['media_type'] as String?) ?? 'image',
      src: j['src'] as String?,
      youtube: j['youtube'] as String?,
      caption: j['caption'] as String?,
      linkUrl: j['link_url'] as String?,
      skippable: j['skippable'] != false,
      skipAfter: (j['skip_after'] as num?)?.toInt() ?? 5,
      imageSeconds: (j['image_seconds'] as num?)?.toInt() ?? 5,
      frequency: (j['frequency'] as String?) ?? 'always',
    );
    return ad.isEmpty ? null : ad;
  }
}
