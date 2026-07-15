/// A viewing profile on the account (`GET /api/app/profiles`).
///
/// The app had no profile concept at all — it used a single read-only
/// `defaultProfile()`, so kids mode existed on the web but never on mobile.
///
/// [isKids] is enforced SERVER-side: selecting a profile binds it to this
/// device's token, and MaturityScope filters adult titles from there. The flag
/// here is for display only — the app is not the thing keeping kids out.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.avatarColor,
    this.avatarUrl,
    this.initial = '?',
    this.isKids = false,
  });

  final int id;
  final String name;

  /// `#rrggbb` tint for the initial tile.
  final String? avatarColor;

  /// Uploaded avatar, when there is one. Null → show the coloured initial tile.
  final String? avatarUrl;

  final String initial;
  final bool isKids;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        avatarColor: j['avatar_color'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        initial: (j['initial'] as String?)?.isNotEmpty == true
            ? j['initial'] as String
            : ((j['name'] as String?)?.trim().isNotEmpty == true
                ? (j['name'] as String).trim().substring(0, 1)
                : '?'),
        isKids: j['is_kids'] == true,
      );
}

/// The profiles screen in one payload.
class ProfileList {
  const ProfileList({
    this.items = const [],
    this.activeId,
    this.max = 5,
    this.palette = const [],
    this.canCreate = true,
  });

  final List<Profile> items;
  final int? activeId;

  /// Server-enforced ceiling (5, same as the web).
  final int max;

  /// Colour choices the web offers when creating a profile.
  final List<String> palette;

  /// False once [max] is reached — the server rejects the create either way.
  final bool canCreate;

  factory ProfileList.fromJson(Map<String, dynamic> j) => ProfileList(
        items: (j['items'] is List)
            ? (j['items'] as List)
                .whereType<Map>()
                .map((m) => Profile.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
        activeId: (j['active_id'] as num?)?.toInt(),
        max: (j['max'] as num?)?.toInt() ?? 5,
        palette: (j['palette'] is List)
            ? (j['palette'] as List).whereType<String>().toList()
            : const [],
        canCreate: j['can_create'] != false,
      );
}
