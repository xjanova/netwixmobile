import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../l10n/l10n.dart';
import '../models/content.dart';
import '../models/episode.dart';
import '../services/netwix_api.dart';
import '../services/netwix_client.dart';
import '../services/reward_config.dart';
import '../widgets/comment_sheet.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster_image.dart';
import '../widgets/unlock_sheet.dart';
import 'playback_screen.dart';

/// 03 — Content Preview / Detail · รายละเอียด. Loads the title + episode list
/// from NetWix, autoplays EP1 as an ambient preview, and opens the full-screen
/// player on tap.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.content});
  final Content content;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  Content _content = const Content(id: 0, slug: '', title: '');
  List<Episode> _episodes = [];
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

  Content get c => _content;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    _load();
  }

  Future<void> _toggleLike() async {
    final becameLiked = !_liked;
    setState(() {
      _liked = becameLiked;
      _likes += becameLiked ? 1 : -1;
      if (_likes < 0) _likes = 0;
    });
    await context.read<NetwixClient>().toggleLike(c.id); // graceful until live
    // Coins only when turning a like ON (server + daily cap prevent farming).
    if (becameLiked && mounted) {
      final got = await context.read<MemberState>().awardLike();
      if (got > 0 && mounted) _coinToast(got);
    }
  }

  Future<void> _share() async {
    final l = context.read<AppState>().l;
    final text = l.pick(
      'ดู "${c.title}" ฟรีบน NetWix 🎬\nhttps://netwix.online/t/${c.slug}',
      'Watch "${c.title}" free on NetWix 🎬\nhttps://netwix.online/t/${c.slug}',
    );
    await SharePlus.instance.share(ShareParams(text: text));
    if (!mounted) return;
    final got = await context.read<MemberState>().awardShare();
    if (got > 0 && mounted) _coinToast(got);
  }

  void _coinToast(int coins) {
    if (!mounted) return;
    final l = context.read<AppState>().l;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('+$coins ${l.pick('เหรียญ', 'coins')} 🪙')),
    );
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = context.read<NetwixApi>();
    try {
      final detail = await api.fetchDetail(widget.content.slug);
      if (!mounted) return;
      if (detail == null) {
        setState(() {
          _error = 'โหลดรายละเอียดไม่สำเร็จ';
          _loading = false;
        });
        return;
      }
      setState(() {
        _content = detail.content;
        _episodes = detail.episodes;
        _loading = false;
        _error = null;
      });
      _maybeStartPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_episodes.isEmpty) _error = 'โหลดรายละเอียดไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  void _maybeStartPreview() {
    if (_previewStarted || _episodes.isEmpty) return;
    // Preview the first playable (mirrored) episode.
    final ep = _episodes.firstWhere(
      (e) => e.isMirrored && !e.isUnavailable,
      orElse: () => _episodes.first,
    );
    _startPreview(ep);
  }

  Future<void> _startPreview(Episode ep) async {
    if (_previewStarted) return;
    _previewStarted = true;

    final api = context.read<NetwixApi>();
    try {
      final src = await api.resolveSource(ep.id);
      final url = src?.url;
      if (url == null || src?.ready != true || !mounted) return;

      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(true);
      await ctrl.setVolume(_muted ? 0 : 1);
      await ctrl.play();
      setState(() {
        _preview = ctrl;
        _previewReady = true;
      });
    } catch (_) {/* preview is best-effort — fall back to the poster */}
  }

  void _toggleMute() {
    final ctrl = _preview;
    if (ctrl == null) return;
    setState(() {
      _muted = !_muted;
      ctrl.setVolume(_muted ? 0 : 1);
    });
  }

  Future<void> _play(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    final ep = _episodes[index];
    if (ep.isUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ตอนนี้ยังไม่พร้อมให้ชม')),
      );
      return;
    }

    final member = context.read<MemberState>();
    // Effective Pro = locally-purchased flag OR server plan (incl. referral-
    // granted free Pro). Either removes the coin gate.
    final isPro = context.read<AppState>().isPro || member.isPro;

    // Gate: free for first N / Pro / already unlocked, else prompt to unlock.
    if (!member.isEpisodeUnlocked(c.id, ep.id, index, isPro: isPro)) {
      _preview?.pause();
      final unlocked = await showUnlockSheet(context, seriesId: c.id, episode: ep.number);
      if (!mounted) return;
      _preview?.play();
      if (!unlocked) return;
    }

    _preview?.pause();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackScreen(content: c, episodes: _episodes, startEpisodeId: ep.id),
    ));
    if (mounted) _preview?.play();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;

    final heroH = (MediaQuery.of(context).size.height * 0.52).clamp(320.0, 560.0);

    return Scaffold(
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(l, heroH)),
            SliverToBoxAdapter(child: _meta(l)),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: T.accent)),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(child: _errorRow(l))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: SectionHeader(
                    title: l.bi('ตอนทั้งหมด', 'Episodes'),
                    trailing: '${_episodes.length} ${l.pick('ตอน', 'eps')}',
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: _episodes.length,
                itemBuilder: (_, i) => _episodeRow(l, _episodes[i], i),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
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
                onPressed: () => _play(0),
              ),
            ),
    );
  }

  /// Preview header (scrolls with the content). Full-width video/poster with a
  /// bottom fade so it blends into the content as you scroll — no Opacity around
  /// the video (that renders the Texture black).
  Widget _hero(L10n l, double height) {
    final preview = _preview;
    final showPreview = _previewReady && preview != null && preview.value.isInitialized;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
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
            PosterImage(url: c.heroImageUrl, seed: c.id, radius: 0),

          // bottom fade into the app background + top scrim
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Colors.transparent, Colors.transparent, T.screen],
                stops: [0.0, 0.2, 0.55, 1.0],
              ),
            ),
          ),

          // tap the header to open the full-screen player at EP1
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _episodes.isEmpty ? null : () => _play(0),
              child: Align(
                alignment: const Alignment(0, -0.1),
                child: showPreview
                    ? const SizedBox.shrink()
                    : const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 64),
              ),
            ),
          ),

          // cover poster on the right
          Positioned(
            right: 14,
            bottom: 26,
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
              child: PosterImage(url: c.displayImageUrl, seed: c.id, radius: 12),
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
      if (c.yearText.isNotEmpty) c.yearText,
      c.typeThai,
      if (_episodes.isNotEmpty) '${_episodes.length} ${l.pick('ตอน', 'eps')}',
      'HD · ${l.pick('สตรีม', 'Stream')}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.title, style: AppTheme.display(23, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(metaText, style: AppTheme.body(12.5, color: T.textMuted)),
          const SizedBox(height: 12),
          _socialBar(l),
          if (c.synopsis.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(c.synopsis, style: AppTheme.body(13.5, color: T.textSecondary, height: 1.5)),
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
          () => showCommentSheet(context, c.id)),
      const SizedBox(width: 10),
      btn(Icons.ios_share_rounded, l.pick('แชร์', 'Share'), _share),
    ]);
  }

  Widget _episodeRow(L10n l, Episode ep, int index) {
    final member = context.watch<MemberState>();
    final isPro = context.watch<AppState>().isPro || member.isPro;
    final unlocked = member.isEpisodeUnlocked(c.id, ep.id, index, isPro: isPro);
    final free = !RewardConfig.gatingEnabled || index < RewardConfig.freeEpisodes;

    // Sub-label: availability first, then gating status. We don't infer
    // "preparing" from is_mirrored here — wow-drama episodes play via HLS
    // without being mirrored; the player resolves the real source on tap and
    // shows "preparing" only if the source truly isn't ready yet.
    String sub;
    Color subColor;
    if (ep.isUnavailable) {
      sub = l.pick('ไม่พร้อมใช้งาน', 'Unavailable');
      subColor = T.textFaint;
    } else if (free) {
      sub = l.pick('ดูฟรี', 'Free');
      subColor = T.textFaint;
    } else if (unlocked) {
      sub = l.pick('ปลดล็อกแล้ว', 'Unlocked');
      subColor = T.textFaint;
    } else {
      sub = '${l.pick('ปลดล็อก', 'Unlock')} · ${member.unlockCost} ${l.pick('เหรียญ', 'coins')}';
      subColor = T.accent;
    }

    final playable = !ep.isUnavailable;
    final icon = ep.isUnavailable
        ? Icons.block_rounded
        : !unlocked
            ? Icons.lock_outline_rounded
            : Icons.play_circle_outline_rounded;

    return InkWell(
      onTap: playable ? () => _play(index) : null,
      child: Opacity(
        opacity: ep.isUnavailable ? 0.5 : 1,
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
                      PosterImage(
                          url: ep.thumbnailUrl ?? c.displayImageUrl, seed: c.id + ep.number, radius: 8),
                      Center(
                        child: Icon(unlocked && !ep.isUnavailable ? Icons.play_arrow_rounded : Icons.lock_rounded,
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
                    Text(ep.label,
                        style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
                    Text(sub, style: AppTheme.body(11.5, color: subColor)),
                  ],
                ),
              ),
              Icon(icon, color: unlocked && !ep.isUnavailable ? T.textMuted : T.accent, size: 20),
            ],
          ),
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
              child: AccentButton(label: l.pick('ลองใหม่', 'Retry'), height: 44, onPressed: _load),
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
