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
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_image.dart';
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

    return RefreshIndicator(
      color: T.accent,
      backgroundColor: T.screen,
      onRefresh: () async {
        await catalog.load(force: true);
        await _loadContinue();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _greeting(l),
          const SizedBox(height: 16),
          _searchField(l),
          const SizedBox(height: 16),
          _chips(catalog),
          const SizedBox(height: 20),
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
            // When a category chip is active (e.g. อนิเมะ), lead with that set.
            if (!catalog.current.isAll)
              _rail(
                l,
                catalog.current.label(l.isTh),
                catalog.visible,
                badge: catalog.current.id == 'vertical'
                    ? const Pill(text: 'ดูฟรี', filled: true)
                    : null,
                loading: catalog.filterLoading,
              ),
            // The web's curated home rails (trending + genres, incl. anime).
            for (final r in catalog.rails)
              if (r.items.isNotEmpty) _rail(l, r.title, r.items),
            // Fallback when the backend sent no rails (offline / older API).
            if (catalog.rails.isEmpty && catalog.current.isAll)
              _rail(l, l.bi('ยอดนิยม', 'Popular'), catalog.featured),
          ],
        ],
      ),
    );
  }

  Widget _greeting(L10n l) {
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
        const HexAvatar(size: 44, child: Icon(Icons.person, color: T.accentHi, size: 20)),
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
                    PosterImage(url: it.content.heroImageUrl, seed: it.content.id, radius: 0),
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
