import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../main.dart' show routeObserver;
import '../models/content.dart';
import '../services/catalog_db.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/catalog_state.dart';
import '../state/member_state.dart';
import '../state/notification_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../services/format.dart';
import '../widgets/common.dart';
import '../widgets/floating_nav.dart';
import '../widgets/icon3d.dart';
import '../widgets/netwix_wordmark.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_image.dart';
import '../widgets/promo_banner_carousel.dart';
import 'notifications_screen.dart';
import 'playback_screen.dart';

/// 02 — Home / Discover · หน้าแรก.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenExplore});
  final VoidCallback? onOpenExplore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  List<ResumeItem> _continue = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CatalogState>().load();
        _loadContinue();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Returning from the player → refresh "Continue watching".
  @override
  void didPopNext() => _loadContinue();

  Future<void> _loadContinue() async {
    // Signed in → the server's watch-progress (same as the web, syncs across
    // devices). Guest → the on-device resume list.
    final loggedIn = context.read<MemberState>().isLoggedIn;
    final api = context.read<NetwixApi>();
    final db = context.read<CatalogDb>();
    if (loggedIn) {
      final prog = await api.fetchProgress();
      if (prog.isNotEmpty) {
        final items = prog.map((p) {
          final dur = p.percent > 0 ? (p.positionSeconds * 100 / p.percent).round() : 0;
          return ResumeItem(p.content, p.episodeId ?? 0, 0, p.positionSeconds, dur);
        }).toList();
        if (mounted) setState(() => _continue = items);
        return;
      }
    }
    try {
      final items = await db.continueWatching(limit: 12);
      if (mounted) setState(() => _continue = items);
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final catalog = context.watch<CatalogState>();
    final hero = catalog.hero ?? (catalog.featured.isNotEmpty ? catalog.featured.first : null);

    return RefreshIndicator(
      color: T.accent,
      backgroundColor: T.screen,
      onRefresh: () async {
        await catalog.load(force: true);
        await _loadContinue();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: kNavClearance),
        children: [
          if (hero != null)
            _hero(l, hero)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(children: [_greeting(l), const SizedBox(height: 16), _searchField(l)]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips(catalog),
                const SizedBox(height: 18),
                // Admin-controlled promo banners (campaigns like "สมัครใหม่รับฟรีโปร").
                const PromoBannerCarousel(),
                if (_continue.isNotEmpty) ...[
                  _continueSection(l),
                  const SizedBox(height: 24),
                ],
                if (catalog.loading && catalog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator(color: T.accent)),
                  )
                else if (catalog.error != null && catalog.isEmpty)
                  _errorBox(l, catalog)
                else ...[
                  // When a category chip is active (e.g. อนิเมะ), lead with that category's
                  // newest titles — every category gets its own มาใหม่ rail, like ทั้งหมด.
                  if (!catalog.current.isAll)
                    _rail(
                      l,
                      '${l.pick('มาใหม่', 'New arrivals')} 🔥 · ${catalog.current.label(l.isTh)}',
                      catalog.newestInCurrent,
                      badge: catalog.current.id == 'vertical'
                          ? const Pill(text: 'ดูฟรี', filled: true)
                          : const Pill(text: 'NEW', filled: true),
                      loading: catalog.filterLoading,
                    ),
                  // มาใหม่ + ดาวเยอะ lead the page (computed from the full catalogue).
                  if (catalog.current.isAll) ...[
                    if (catalog.newest.isNotEmpty)
                      _rail(l, l.pick('มาใหม่ 🔥', 'New arrivals 🔥'), catalog.newest,
                          badge: const Pill(text: 'NEW', filled: true)),
                    if (catalog.topRated.isNotEmpty)
                      _rail(l, l.pick('เรตติ้งสูง ⭐', 'Top rated ⭐'), catalog.topRated),
                  ],
                  // The web's curated home rails (trending + genres, incl. anime). The first one is
                  // the web's trending list, so it gets the numbered top-10 treatment.
                  for (final (i, r) in catalog.rails.indexed)
                    if (r.items.isNotEmpty)
                      i == 0 && catalog.current.isAll ? _rankedRail(l, r.title, r.items) : _rail(l, r.title, r.items),
                  // Fallback when the backend sent no rails (offline / older API).
                  if (catalog.rails.isEmpty && catalog.current.isAll)
                    _rail(l, l.bi('ยอดนิยม', 'Popular'), catalog.featured),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full-bleed billboard for the web's featured title, with the app bar laid over it.
  Widget _hero(L10n l, Content c) {
    final unread = context.watch<NotificationState>().unreadCount;
    final member = context.watch<MemberState>();
    final meta = [
      c.typeThai,
      if (c.genres.isNotEmpty) c.genres.first,
      if (c.type != 'movie' && c.episodesCount > 0) '${c.episodesCount} ตอน',
      if (c.yearText.isNotEmpty) c.yearText,
    ].join(' · ');
    return SizedBox(
      height: 470,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => openContent(context, c),
            child: PosterImage(
              url: c.heroImageUrl,
              seed: c.id,
              radius: 0,
              memCacheWidth: 1080,
              title: c.title,
              healContentId: c.id,
            ),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xBF0B0712), Color(0x000B0712), Color(0x000B0712), Color(0xD90B0712), T.screen],
                  stops: [0, 0.22, 0.45, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                const NetwixWordmark(height: 24),
                const Spacer(),
                if (member.isLoggedIn) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: const Color(0x9E140E20),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Row(children: [
                      const Icon3D(Ic3.coins, size: 22, tile: false),
                      const SizedBox(width: 4),
                      Text(Format.grouped(member.coins),
                          style: AppTheme.body(12.5, weight: FontWeight.w600, color: T.textPrimary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                ],
                _roundButton(Icons.search_rounded, l.pick('ค้นหา', 'Search'), widget.onOpenExplore),
                const SizedBox(width: 8),
                _roundButton(
                  Icons.notifications_none_rounded,
                  l.pick('การแจ้งเตือน', 'Notifications'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                  dot: unread > 0,
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(100)),
                    child: Text(l.pick('แนะนำวันนี้', 'Featured'),
                        style: AppTheme.body(11, weight: FontWeight.w600, color: T.onAccent)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(meta,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.body(12, color: T.textSecondary)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(c.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.display(26, weight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _heroButton(
                      icon: Icons.play_arrow_rounded,
                      label: l.pick('ดูเลย', 'Watch'),
                      primary: true,
                      busy: _openingHero,
                      onTap: () => _watchHero(c),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroButton(
                      icon: Icons.info_outline_rounded,
                      label: l.pick('รายละเอียด', 'Details'),
                      onTap: () => openContent(context, c),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _openingHero = false;

  /// Straight into episode 1 for an open title; locked ones (VIP / 18+ / Pro) and titles without an
  /// episode list go through the detail page, which runs the unlock flow.
  Future<void> _watchHero(Content c) async {
    if (_openingHero) return;
    if (c.isVip || c.isAdult || c.requiresPro) {
      openContent(context, c);
      return;
    }
    setState(() => _openingHero = true);
    final detail = await context.read<NetwixApi>().fetchDetail(c.slug);
    if (!mounted) return;
    setState(() => _openingHero = false);
    final eps = detail?.episodes ?? const [];
    if (eps.isEmpty) {
      openContent(context, c);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackScreen(content: c, episodes: eps, startEpisodeId: eps.first.id),
    ));
  }

  Widget _roundButton(IconData icon, String label, VoidCallback? onTap, {bool dot = false}) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0x9E140E20),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: 20, color: T.textPrimary),
            if (dot)
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: T.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1A1228), width: 1.5),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _heroButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    bool busy = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: primary ? T.accentGradient : null,
          color: primary ? null : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(T.rButton),
          border: primary ? null : Border.all(color: const Color(0x29FFFFFF)),
          boxShadow: primary
              ? const [BoxShadow(color: T.accentGlow, blurRadius: 26, offset: Offset(0, 12), spreadRadius: -10)]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else
            Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.body(14.5, weight: primary ? FontWeight.w600 : FontWeight.w500, color: Colors.white)),
        ]),
      ),
    );
  }

  /// Top-10 rail: a big outlined rank number tucked behind each poster.
  Widget _rankedRail(L10n l, String title, List<Content> items) {
    final numberStyle = AppTheme.display(92, weight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          trailing: l.pick('ทั้งหมด ›', 'See all ›'),
          onTrailingTap: widget.onOpenExplore,
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 10),
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final c = items[i];
              return GestureDetector(
                onTap: () => openContent(context, c),
                child: SizedBox(
                  width: i == 9 ? 170 : 148,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        bottom: -10,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: numberStyle.fontFamily,
                            fontFamilyFallback: numberStyle.fontFamilyFallback,
                            fontSize: 92,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 2.4
                              ..color = T.accent,
                            shadows: const [Shadow(color: Color(0x73FF2D55), blurRadius: 22)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 8,
                        width: 104,
                        child: PosterImage(
                          url: c.displayImageUrl,
                          seed: c.id,
                          radius: 12,
                          title: c.title,
                          healContentId: c.id,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _greeting(L10n l) {
    final unread = context.watch<NotificationState>().unreadCount;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.bi('สวัสดี', 'Hello'), style: AppTheme.body(12, color: T.textMuted)),
              Text(l.pick('ยินดีต้อนรับสู่ NetWix', 'Welcome to NetWix'),
                  style: AppTheme.display(20, weight: FontWeight.w700)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const HexAvatar(
                  size: 44,
                  child: Icon(Icons.notifications_rounded, color: T.accentHi, size: 20)),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                        gradient: T.accentGradient,
                        borderRadius: BorderRadius.circular(100)),
                    child: Text(unread > 9 ? '9+' : '$unread',
                        style: AppTheme.body(9.5, weight: FontWeight.w800, color: T.onAccent)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchField(L10n l) {
    return GestureDetector(
      onTap: widget.onOpenExplore,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0x10FFFFFF),
          borderRadius: BorderRadius.circular(T.rPill),
          border: Border.all(color: T.hairline),
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, size: 18, color: T.textMuted),
          const SizedBox(width: 10),
          Text(l.bi('ค้นหาซีรีส์ หนัง อนิเมะ', 'Search series, movies, anime…'),
              style: AppTheme.body(13.5, color: T.textMuted)),
        ]),
      ),
    );
  }

  Widget _chips(CatalogState catalog) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final cat in catalog.categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(catalog, cat),
            ),
        ],
      ),
    );
  }

  Widget _chip(CatalogState catalog, CatalogCategory cat) {
    final active = catalog.current.id == cat.id;
    final label = context.read<AppState>().l.isTh ? cat.th : cat.en;
    return GestureDetector(
      onTap: () => catalog.setCategory(cat),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: active ? T.accentGradient : null,
          color: active ? null : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(T.rPill),
          border: Border.all(color: active ? Colors.transparent : T.hairline),
        ),
        child: Text(label,
            style: AppTheme.body(12.5,
                weight: FontWeight.w600, color: active ? T.onAccent : T.textSecondary)),
      ),
    );
  }

  /// A horizontal poster rail with a header + "See all ›" → Explore.
  Widget _rail(L10n l, String title, List<Content> items, {Widget? badge, bool loading = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          badge: badge,
          trailing: l.pick('ทั้งหมด ›', 'See all ›'),
          onTrailingTap: widget.onOpenExplore,
        ),
        SizedBox(
          height: 208,
          child: loading && items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: T.accent))
              : items.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l.pick('ยังไม่มีรายการ', 'Nothing here yet'),
                          style: AppTheme.body(12.5, color: T.textMuted)),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length.clamp(0, 18),
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => PortraitPosterCard(content: items[i]),
                    ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _continueSection(L10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l.bi('ดูต่อ', 'Continue watching')),
        SizedBox(
          height: 134,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _continue.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _continueCard(l, _continue[i]),
          ),
        ),
      ],
    );
  }

  Widget _continueCard(L10n l, ResumeItem it) {
    final title = it.content.title;
    return GestureDetector(
      onTap: () => _openContinue(it),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(T.rMedia),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(
                        url: it.content.heroImageUrl,
                        seed: it.content.id,
                        radius: 0,
                        title: it.content.title,
                        healContentId: it.content.id),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 34),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: it.progress.clamp(0, 1).toDouble(),
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(T.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(12.5, weight: FontWeight.w600, color: T.textPrimary)),
            Text('${l.pick('ตอนที่', 'EP')} ${it.episodeNumber}',
                style: AppTheme.body(10.5, color: T.textFaint)),
          ],
        ),
      ),
    );
  }

  Future<void> _openContinue(ResumeItem it) async {
    final api = context.read<NetwixApi>();
    final detail = await api.fetchDetail(it.content.slug);
    if (!mounted) return;
    final eps = detail?.episodes ?? const [];
    if (eps.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          PlaybackScreen(content: it.content, episodes: eps, startEpisodeId: it.episodeId),
    ));
  }

  Widget _errorBox(L10n l, CatalogState catalog) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: T.textFaint),
          const SizedBox(height: 12),
          Text(catalog.error ?? '', textAlign: TextAlign.center, style: AppTheme.body(13, color: T.textMuted)),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: AccentButton(
              label: l.pick('ลองใหม่', 'Retry'),
              height: 46,
              onPressed: () => catalog.load(force: true),
            ),
          ),
        ],
      ),
    );
  }
}
