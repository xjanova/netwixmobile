import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../l10n/l10n.dart';
import '../models/series.dart';
import '../services/catalog_db.dart';
import '../services/netwix_client.dart';
import '../services/rongyok_client.dart';
import '../widgets/comment_sheet.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster_image.dart';
import '../widgets/unlock_sheet.dart';
import 'playback_screen.dart';

/// 03 — Content Preview / Series Detail · รายละเอียด. Stream-only: pick a title,
/// browse episodes, tap to watch. Everything is free.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});
  final Series series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<int> _episodes = [];
  bool _loading = true;
  String? _error;

  // Netflix-style ambient preview: EP1 autoplays (looping) in the hero.
  VideoPlayerController? _preview;
  bool _previewReady = false;
  bool _previewStarted = false;
  bool _muted = false;

  // Social (netwix.online-backed; local-optimistic until live).
  bool _liked = false;
  int _likes = 0;

  Series get s => widget.series;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
      if (_likes < 0) _likes = 0;
    });
    await context.read<NetwixClient>().toggleLike(s.id); // graceful until live
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = context.read<RongYokClient>();
    final db = context.read<CatalogDb>();

    // 1) instant paint from the cached episode list
    try {
      final cached = await db.getEpisodes(s.id);
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _episodes = cached;
          s.episodesCount = cached.length;
          _loading = false;
        });
        _maybeStartPreview();
      }
    } catch (_) {/* ignore cache errors */}

    // 2) refresh from the network, then persist
    try {
      final nums = await client.fetchEpisodeNumbers(s.id);
      if (!mounted) return;
      setState(() {
        _episodes = nums;
        s.episodesCount = nums.length;
        _loading = false;
        _error = null;
      });
      _maybeStartPreview();
      unawaited(db.upsertEpisodes(s.id, nums));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_episodes.isEmpty) _error = 'โหลดรายชื่อตอนไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  void _maybeStartPreview() {
    if (!_previewStarted && _episodes.isNotEmpty) {
      _startPreview(_episodes.first);
    }
  }

  Future<void> _startPreview(int ep) async {
    if (_previewStarted) return;
    _previewStarted = true;

    final db = context.read<CatalogDb>();
    final client = context.read<RongYokClient>();
    try {
      var url = await db.freshVideoUrl(s.id, ep);
      if (url == null) {
        url = await client.getVideoUrl(s.id, ep);
        if (url != null) unawaited(db.cacheVideoUrl(s.id, ep, url));
      }
      if (url == null || !mounted) return;

      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: RongYokClient.mediaHeaders,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      await c.play();
      setState(() {
        _preview = c;
        _previewReady = true;
      });
    } catch (_) {/* preview is best-effort — fall back to the poster */}
  }

  void _toggleMute() {
    final c = _preview;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  Future<void> _play(int ep) async {
    final member = context.read<MemberState>();
    final isPro = context.read<AppState>().isPro;

    // Gate: free for first 3 / Pro / already unlocked, else prompt to unlock.
    if (!member.isEpisodeUnlocked(s.id, _episodes, ep, isPro: isPro)) {
      _preview?.pause();
      final unlocked = await showUnlockSheet(context, seriesId: s.id, episode: ep);
      if (!mounted) return;
      _preview?.play();
      if (!unlocked) return;
    }

    _preview?.pause();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackScreen(series: s, episodes: _episodes, startEpisode: ep),
    ));
    if (mounted) _preview?.play();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;

    return Scaffold(
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: Column(
          children: [
            // Fixed preview — stays put while the episode list scrolls.
            _hero(l),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: T.accent))
                  : _error != null
                      ? _errorRow(l)
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _meta(l),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                              child: SectionHeader(
                                title: l.bi('ตอนทั้งหมด', 'Episodes'),
                                trailing: '${_episodes.length} ${l.pick('ตอน', 'eps')}',
                              ),
                            ),
                            for (var i = 0; i < _episodes.length; i++)
                              _episodeRow(l, _episodes[i], i),
                          ],
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _loading || _episodes.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: AccentButton(
                label: l.bi('เล่นตอนที่ 1', 'Play EP1'),
                icon: Icons.play_arrow_rounded,
                height: 54,
                onPressed: () => _play(_episodes.first),
              ),
            ),
    );
  }

  Widget _hero(L10n l) {
    final preview = _preview;
    final showPreview = _previewReady && preview != null && preview.value.isInitialized;
    // Fixed cinematic header — fills the phone width, leaves room for the list.
    final height = (MediaQuery.of(context).size.height * 0.5).clamp(320.0, 560.0);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen-width preview (BoxFit.cover) or poster until ready.
          if (showPreview)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: preview.value.size.width,
                height: preview.value.size.height,
                child: VideoPlayer(preview),
              ),
            )
          else
            PosterImage(url: s.displayImageUrl, seed: s.id, radius: 0),

          // Fade the bottom half into the app background (from 50% down).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.transparent, T.screen],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // subtle top scrim for the status-bar controls
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Colors.transparent],
                stops: [0.0, 0.22],
              ),
            ),
          ),

          // tap the preview to open the full-screen player at EP1
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _episodes.isEmpty ? null : () => _play(_episodes.first),
              child: Align(
                alignment: const Alignment(0, -0.15),
                child: AnimatedOpacity(
                  opacity: showPreview ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: T.accentGradient,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: T.accentGlow, blurRadius: 24, spreadRadius: -4)],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: T.onAccent, size: 34),
                  ),
                ),
              ),
            ),
          ),

          // The cover poster, kept visible on the right.
          Positioned(
            right: 14,
            bottom: 34,
            child: Container(
              width: 104,
              height: 156,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: T.hairlineStrong),
                boxShadow: const [
                  BoxShadow(color: Color(0xB3000000), blurRadius: 20, offset: Offset(0, 8), spreadRadius: -6),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: PosterImage(url: s.displayImageUrl, seed: s.id, radius: 12),
            ),
          ),

          // top controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _circleBtn(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Pill(text: l.pick('ดูฟรี', 'FREE'), filled: true),
                  const Spacer(),
                  if (showPreview)
                    _circleBtn(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      _toggleMute,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(L10n l) {
    final metaText = [
      if (s.yearText.isNotEmpty) s.yearText,
      s.typeThai,
      if (_episodes.isNotEmpty) '${_episodes.length} ${l.pick('ตอน', 'eps')}',
      'HD · ${l.pick('สตรีม', 'Stream')}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.cleanTitle.isEmpty ? s.title : s.cleanTitle,
              style: AppTheme.display(23, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(metaText, style: AppTheme.body(12.5, color: T.textMuted)),
          const SizedBox(height: 12),
          _socialBar(l),
          if (s.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(s.description, style: AppTheme.body(13.5, color: T.textSecondary, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _socialBar(L10n l) {
    Widget btn(IconData icon, String label, VoidCallback onTap, {Color? color}) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: T.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: color ?? T.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: AppTheme.body(12.5, weight: FontWeight.w600, color: color ?? T.textSecondary)),
            ]),
          ),
        );

    return Row(children: [
      btn(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          _likes > 0 ? '$_likes' : l.pick('ถูกใจ', 'Like'), _toggleLike,
          color: _liked ? const Color(0xFFF2705A) : null),
      const SizedBox(width: 10),
      btn(Icons.mode_comment_outlined, l.pick('คอมเมนต์', 'Comment'),
          () => showCommentSheet(context, s.id)),
    ]);
  }

  Widget _episodeRow(L10n l, int ep, int index) {
    final member = context.watch<MemberState>();
    final isPro = context.watch<AppState>().isPro;
    final unlocked = member.isEpisodeUnlocked(s.id, _episodes, ep, isPro: isPro);
    final free = index < 3;

    return InkWell(
      onTap: () => _play(ep),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: s.displayImageUrl, seed: s.id + ep, radius: 8),
                    Center(
                      child: Icon(unlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                          size: 18, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l.pick('ตอนที่', 'EP')} $ep',
                      style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                  Text(
                    free
                        ? l.pick('ดูฟรี', 'Free')
                        : unlocked
                            ? l.pick('ปลดล็อกแล้ว', 'Unlocked')
                            : '${l.pick('ปลดล็อก', 'Unlock')} · ${member.unlockCost} ${l.pick('เหรียญ', 'coins')}',
                    style: AppTheme.body(11.5, color: unlocked ? T.textFaint : T.accent),
                  ),
                ],
              ),
            ),
            Icon(
              unlocked ? Icons.play_circle_outline_rounded : Icons.lock_outline_rounded,
              color: unlocked ? T.textMuted : T.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorRow(L10n l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
        child: Column(
          children: [
            Text(_error ?? '', style: AppTheme.body(13, color: T.textMuted)),
            const SizedBox(height: 12),
            SizedBox(
              width: 160,
              child: AccentButton(label: l.pick('ลองใหม่', 'Retry'), height: 44, onPressed: _loadEpisodes),
            ),
          ],
        ),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(color: Color(0x800D0B08), shape: BoxShape.circle),
          child: Icon(icon, color: T.textPrimary, size: 20),
        ),
      );
}
