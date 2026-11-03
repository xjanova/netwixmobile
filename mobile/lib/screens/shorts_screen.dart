import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/content.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/floating_nav.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_image.dart';
import '../widgets/social_rail.dart';
import 'playback_screen.dart';

/// ดูสั้น — the vertical dramas as a full-screen swipe feed: one title per page, swipe up for the
/// next. "ดูตอนแรก" starts episode 1 straight away; locked titles (VIP / 18+ / Pro) go through the
/// detail page so its unlock flow runs first.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key, required this.active});

  /// Whether the tab is showing. The feed loads the first time it becomes active, so the app's
  /// launch doesn't pay for a tab nobody opened.
  final bool active;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final _pager = PageController();
  final List<Content> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadMore();
  }

  @override
  void didUpdateWidget(ShortsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && _items.isEmpty && !_loading) _loadMore();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final res = await context.read<NetwixApi>().fetchTitlesPage(type: 'vertical', page: _page + 1, per: 20);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // fetchTitlesPage swallows errors into an empty page, which reads the same as "offline".
      // First page: show the retry state. Later pages: keep the cursor, so the next swipe retries.
      if (res.items.isEmpty && !res.hasMore) {
        if (_items.isEmpty) _failed = true;
        return;
      }
      _page++;
      final seen = _items.map((c) => c.id).toSet();
      _items.addAll(res.items.where((c) => seen.add(c.id)));
      _hasMore = res.hasMore;
    });
  }

  Future<void> _retry() async {
    _hasMore = true;
    await _loadMore();
  }

  bool _locked(Content c) => c.isVip || c.isAdult || c.requiresPro;

  Future<void> _play(Content c) async {
    if (_opening) return;
    if (_locked(c)) {
      openContent(context, c);
      return;
    }
    setState(() => _opening = true);
    final detail = await context.read<NetwixApi>().fetchDetail(c.slug);
    if (!mounted) return;
    setState(() => _opening = false);
    final eps = detail?.episodes ?? const [];
    if (eps.isEmpty) {
      // No episode list (offline / not mirrored yet): the detail page explains the state.
      openContent(context, c);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackScreen(content: c, episodes: eps, startEpisodeId: eps.first.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;

    if (_items.isEmpty) {
      return Center(
        child: _failed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 40, color: T.textFaint),
                const SizedBox(height: 12),
                Text(l.pick('โหลดละครสั้นไม่ได้ ตรวจสอบอินเทอร์เน็ต', 'Could not load shorts — check your connection'),
                    style: AppTheme.body(13, color: T.textMuted)),
                TextButton(
                  onPressed: _retry,
                  child: Text(l.pick('ลองใหม่', 'Retry'), style: AppTheme.body(13, color: T.accent)),
                ),
              ])
            : const CircularProgressIndicator(color: T.accent),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pager,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          onPageChanged: (i) {
            if (i >= _items.length - 4) _loadMore();
          },
          itemBuilder: (_, i) => _slide(l, _items[i]),
        ),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Column(children: [
              Text(l.pick('ละครสั้น', 'Short dramas'),
                  style: AppTheme.body(16, weight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 5),
              Container(
                width: 22,
                height: 3,
                decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(3)),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _slide(L10n l, Content c) {
    final locked = _locked(c);
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterImage(
          url: c.displayImageUrl,
          seed: c.id,
          radius: 0,
          memCacheWidth: 1080,
          title: c.title,
          healContentId: c.id,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB30B0712), Color(0x000B0712), Color(0x000B0712), Color(0xF00B0712)],
              stops: [0, 0.18, 0.48, 0.86],
            ),
          ),
        ),
        // Side actions: like · comment · share (same rows as the web), then details.
        Positioned(
          right: 12,
          bottom: kNavClearance + 96,
          child: Column(children: [
            SocialRail(content: c, gap: 16),
            const SizedBox(height: 16),
            _action(Icons.info_outline_rounded, l.pick('รายละเอียด', 'Details'), () => openContent(context, c)),
          ]),
        ),
        // Title block.
        Positioned(
          left: 18,
          right: 84,
          bottom: kNavClearance + 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xD9FF2D55), borderRadius: BorderRadius.circular(100)),
                child: Text(
                  [
                    l.pick('ละครสั้น', 'Short drama'),
                    if (c.episodesCount > 0) l.pick('${c.episodesCount} ตอน', '${c.episodesCount} eps'),
                    if (locked) (c.isAdult ? (c.maturity.isNotEmpty ? c.maturity : '18+') : 'VIP'),
                  ].join(' · '),
                  style: AppTheme.body(11, weight: FontWeight.w600, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(22, weight: FontWeight.w700, color: Colors.white)),
              if (c.synopsis.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(c.synopsis.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(12.5, color: T.textSecondary)),
              ],
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _play(c),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    gradient: T.accentGradient,
                    borderRadius: BorderRadius.circular(T.rButton),
                    boxShadow: const [BoxShadow(color: T.accentGlow, blurRadius: 22, offset: Offset(0, 10), spreadRadius: -10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_opening)
                      const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      Icon(locked ? Icons.lock_open_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(locked ? l.pick('ดูรายละเอียด', 'View details') : l.pick('ดูตอนแรก', 'Watch episode 1'),
                        style: AppTheme.body(14, weight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Text(l.pick('ปัดขึ้นเพื่อดูเรื่องถัดไป', 'Swipe up for the next one'),
                  style: AppTheme.body(11, color: T.textFaint)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    final glyph = Icon(icon, size: 24, color: Colors.white);
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: Color(0x800B0712), shape: BoxShape.circle),
          child: Center(child: glyph),
        ),
        const SizedBox(height: 3),
        Text(label, style: AppTheme.body(11, color: Colors.white)),
      ]),
    );
  }
}
