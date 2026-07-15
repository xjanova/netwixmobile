/// A NetWix catalog item (movie / series / vertical short-drama).
/// Replaces the old rongyok-scraped `Series` — the app now gets everything
/// from the NetWix API, so images/titles/types come straight from NetWix.
class Content {
  const Content({
    required this.id,
    required this.slug,
    required this.title,
    this.type = 'series',
    this.synopsis = '',
    this.year,
    this.maturity = '',
    this.rating = 0,
    this.matchScore = 0,
    this.isOriginal = false,
    this.isFeatured = false,
    this.posterUrl = '',
    this.backdropUrl = '',
    this.trailerYoutubeId,
    this.durationMinutes,
    this.views = 0,
    this.episodesCount = 0,
    this.genres = const [],
    this.isVip = false,
    this.vipPriceGold = 0,
    this.isAdult = false,
    this.requiresPro = false,
    this.introEndSeconds = 0,
    this.outroSeconds = 0,
  });

  final int id;
  final String slug;
  final String title;

  /// series | movie | vertical
  final String type;
  final String synopsis;
  final int? year;
  final String maturity;
  final double rating; // editorial 0-10
  final int matchScore; // % ตรงใจ
  final bool isOriginal;
  final bool isFeatured;
  final String posterUrl;
  final String backdropUrl;
  final String? trailerYoutubeId;
  final int? durationMinutes;
  final int views;
  final int episodesCount;
  final List<String> genres;

  /// VIP-zone title — needs gold to unlock (or Pro, when the admin allows it).
  final bool isVip;

  /// Per-title gold price; 0 = fall back to the config default.
  final int vipPriceGold;

  /// 18+/20+ rating.
  final bool isAdult;

  /// Watching needs an active Pro membership (adult titles do).
  final bool requiresPro;

  /// Content-level playback markers, in seconds (0 = unset). Episodes may
  /// override these; the API already resolves the effective value per episode.
  final int introEndSeconds;

  /// Credits length measured FROM THE END — trigger when
  /// `duration - position <= outroSeconds`. One value works across episodes of
  /// differing length, which is why it isn't an absolute timestamp.
  final int outroSeconds;

  bool get isVertical => type == 'vertical';
  bool get isMovie => type == 'movie';

  /// Needs some kind of purchase before it will play.
  bool get isGated => isVip || requiresPro;

  String get displayImageUrl => posterUrl.isNotEmpty ? posterUrl : backdropUrl;
  String get heroImageUrl => backdropUrl.isNotEmpty ? backdropUrl : posterUrl;

  String get typeThai => switch (type) {
        'movie' => 'ภาพยนตร์',
        'vertical' => 'ซีรีส์แนวตั้ง',
        _ => 'ซีรีส์',
      };

  String get yearText => year?.toString() ?? '';
  String get ratingText => rating > 0 ? rating.toStringAsFixed(1) : '';
  String get viewsText =>
      views >= 1000 ? '${(views / 1000.0).toStringAsFixed(1)}K' : '$views';

  factory Content.fromJson(Map<String, dynamic> j) => Content(
        id: (j['id'] as num).toInt(),
        slug: (j['slug'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        type: (j['type'] as String?) ?? 'series',
        synopsis: (j['synopsis'] as String?) ?? '',
        year: (j['year'] as num?)?.toInt(),
        maturity: (j['maturity'] as String?) ?? '',
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        matchScore: (j['match_score'] as num?)?.toInt() ?? 0,
        isOriginal: j['is_original'] == true,
        isFeatured: j['is_featured'] == true,
        posterUrl: (j['poster_url'] as String?) ?? '',
        backdropUrl: (j['backdrop_url'] as String?) ?? '',
        trailerYoutubeId: j['trailer_youtube_id'] as String?,
        durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
        views: (j['views'] as num?)?.toInt() ?? 0,
        episodesCount: (j['episodes_count'] as num?)?.toInt() ?? 0,
        isVip: j['is_vip'] == true,
        vipPriceGold: (j['vip_price_gold'] as num?)?.toInt() ?? 0,
        isAdult: j['is_adult'] == true,
        requiresPro: j['requires_pro'] == true,
        introEndSeconds: (j['intro_end_seconds'] as num?)?.toInt() ?? 0,
        outroSeconds: (j['outro_seconds'] as num?)?.toInt() ?? 0,
        genres: (j['genres'] is List)
            ? (j['genres'] as List)
                .whereType<Map>()
                .map((g) => (g['name'] as String?) ?? '')
                .where((s) => s.isNotEmpty)
                .toList()
            : const [],
      );

  Map<String, Object?> toDbMap() => {
        'id': id,
        'slug': slug,
        'title': title,
        'type': type,
        'synopsis': synopsis,
        'year': year,
        'rating': rating,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'views': views,
        'episodes_count': episodesCount,
      };

  factory Content.fromDbMap(Map<String, Object?> m) => Content(
        id: (m['id'] as num).toInt(),
        slug: (m['slug'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        type: (m['type'] as String?) ?? 'series',
        synopsis: (m['synopsis'] as String?) ?? '',
        year: (m['year'] as num?)?.toInt(),
        rating: (m['rating'] as num?)?.toDouble() ?? 0,
        posterUrl: (m['poster_url'] as String?) ?? '',
        backdropUrl: (m['backdrop_url'] as String?) ?? '',
        views: (m['views'] as num?)?.toInt() ?? 0,
        episodesCount: (m['episodes_count'] as num?)?.toInt() ?? 0,
      );
}
