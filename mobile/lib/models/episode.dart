/// One episode of a NetWix title. The playable stream is resolved separately
/// via `NetwixApi.resolveSource(episode.id)` (mirrored MP4 or HLS proxy).
class Episode {
  const Episode({
    required this.id,
    required this.number,
    this.contentId = 0,
    this.seasonId,
    this.title = '',
    this.description = '',
    this.durationMinutes,
    this.thumbnailUrl,
    this.isMirrored = false,
    this.isUnavailable = false,
    this.sort = 0,
    this.introEndSeconds = 0,
    this.outroSeconds = 0,
  });

  final int id;
  final int number;
  final int contentId;
  final int? seasonId;
  final String title;
  final String description;
  final int? durationMinutes;
  final String? thumbnailUrl;

  /// Legacy hint from the API; NOT used for UI decisions — the player is the
  /// source of truth via `resolveSource().ready`. (Left here so the field still
  /// deserializes; wow-drama/rongyok both report false yet play fine.)
  final bool isMirrored;

  /// Source removed upstream — never playable. Shown as "unavailable".
  final bool isUnavailable;
  final int sort;

  /// Effective playback markers in seconds (0 = unset), already merged with the
  /// title's defaults server-side — a NULL marker on an episode means "inherit
  /// the content value", and EpisodeResource resolves that before sending.
  ///
  /// [introEndSeconds] is ABSOLUTE from the start (seek here to skip the intro).
  /// [outroSeconds] is the credits length measured FROM THE END.
  final int introEndSeconds;
  final int outroSeconds;

  String get label => title.isNotEmpty ? title : 'ตอนที่ $number';

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: (j['id'] as num).toInt(),
        number: (j['number'] as num?)?.toInt() ?? 0,
        contentId: (j['content_id'] as num?)?.toInt() ?? 0,
        seasonId: (j['season_id'] as num?)?.toInt(),
        title: (j['title'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
        thumbnailUrl: j['thumbnail_url'] as String?,
        isMirrored: j['is_mirrored'] == true,
        isUnavailable: j['is_unavailable'] == true,
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        introEndSeconds: (j['intro_end_seconds'] as num?)?.toInt() ?? 0,
        outroSeconds: (j['outro_seconds'] as num?)?.toInt() ?? 0,
      );
}
