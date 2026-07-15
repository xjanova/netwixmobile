import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/l10n.dart';
import '../models/content.dart';
import '../models/episode.dart';
import '../services/catalog_db.dart';
import '../services/format.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../widgets/end_card.dart';
import '../widgets/login_sheet.dart';
import '../widgets/unlock_sheet.dart';
import 'go_pro_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ad_banner.dart';
import '../widgets/poster_image.dart';

/// 08 — Playback · เล่นซีรีส์.
///
/// Full-screen, immersive, **TikTok-style vertical feed**: one episode per page,
/// swipe up = next episode, swipe down = previous. Each episode's stream is
/// resolved from NetWix (`/episodes/{id}/source`) — a fresh signed CDN mp4 or an
/// HLS proxy, resolved server-side, that plays from any IP. Adjacent episodes
/// are pre-resolved + pre-initialised
/// so swiping plays instantly. Only the current page plays; neighbours stay
/// paused & ready. Keeps resume (seek + checkpoint) and the free-user ad overlay.
class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({
    super.key,
    required this.content,
    required this.episodes,
    required this.startEpisodeId,
  });

  final Content content;
  final List<Episode> episodes;
  final int startEpisodeId;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  late final PageController _pageController;
  late int _current;

  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _loading = {};
  final Set<int> _failed = {};
  final Set<int> _preparing = {}; // episode genuinely still mirroring (202, no error)
  final Set<int> _retried = {}; // one retry per episode
  final Map<int, String> _errMsg = {};

  /// Server-side refusals keyed by episode index: `pro_required` / `vip_required`
  /// (403 paywalls) or `no_source` (404). Distinct from `_locked`, which is the
  /// client-side coin/free-episode gate. These used to be folded into
  /// `_preparing`, so a paywall read as "still being mirrored" and the viewer
  /// waited for content that was never going to unlock on its own.
  final Map<int, String> _denied = {};

  // ---- playback markers (web parity: watchPlayer.marks/enterOutro/showEndCard)
  /// Intro-skip button is showing for the current episode.
  bool _showSkip = false;

  /// Outro marker already fired for this episode — guards against a double
  /// countdown/card, and stops the real-end fallback re-firing after it.
  bool _outroFired = false;

  /// End-of-series card is up (rate + comment).
  bool _finished = false;

  /// "ตอนต่อไปกำลังจะเริ่ม" countdown, in seconds; null = not counting.
  int? _nextIn;
  Timer? _nextTimer;

  /// Countdown length before auto-advancing at the credits marker.
  static const _nextCountdownSeconds = 10;

  /// "ข้ามอัตโนมัติ" preference, read once and toggled from the skip control.
  bool _autoSkipIntro = false;

  NetwixApi? _api;
  CatalogDb? _db;
  MemberState? _member;
  bool _isPro = false;

  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _advancing = false;
  bool _fullscreen = false; // landscape + fit-to-frame (for horizontal titles)

  // Player chrome (top bar / rail / ad / scrubber) auto-hides after a few idle
  // seconds of playback and reappears on tap — so a landscape movie plays truly
  // full-frame with nothing but the video (+ the persistent logo) on screen.
  bool _chrome = true;
  DateTime _lastInteract = DateTime.fromMillisecondsSinceEpoch(0);

  Content get c => widget.content;
  List<Episode> get eps => widget.episodes;

  @override
  void initState() {
    super.initState();
    final start = eps.indexWhere((e) => e.id == widget.startEpisodeId);
    _current = (start < 0 ? 0 : start).clamp(0, eps.length - 1);
    _pageController = PageController(initialPage: _current);
    _lastInteract = DateTime.now();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api == null) {
      _api = context.read<NetwixApi>();
      _db = context.read<CatalogDb>();
      _member = context.read<MemberState>();
      _isPro = _member!.isPro;
      _autoSkipIntro = context.read<AppState>().autoSkipIntro;
      // Count the watch once per opened title (deduped server-side).
      unawaited(_api!.recordView(c.id));
      _ensure(_current);
      _ensure(_current + 1);
      _ensure(_current - 1);
    }
  }

  @override
  void dispose() {
    _saveResume(_current);
    _nextTimer?.cancel();
    for (final ctrl in _controllers.values) {
      ctrl.removeListener(_onTick);
      ctrl.dispose();
    }
    _pageController.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ------------------------------------------------------- controller window

  bool _locked(int index) {
    if (index < 0 || index >= eps.length) return false;
    final m = _member;
    if (m == null) return false;
    final ep = eps[index];
    return !m.isEpisodeUnlocked(c.id, ep.id, index, isPro: _isPro);
  }

  Future<void> _unlockAt(int index) async {
    final ok = await showUnlockSheet(context, seriesId: c.id, episode: eps[index].number);
    if (!ok || !mounted) return;
    setState(() {});
    await _ensure(index);
    if (index == _current) {
      final ctrl = _controllers[index];
      ctrl
        ?..addListener(_onTick)
        ..play();
    }
  }

  void _openGoPro() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoProScreen()));
  }

  /// Spend gold to open a VIP title. Confirms first (this costs real money) and
  /// re-resolves the stream on success.
  Future<void> _unlockVipAt(int index) async {
    final api = _api;
    if (api == null) return;
    if (!(_member?.isLoggedIn ?? false)) {
      await showLoginSheet(context);
      if (!mounted || !(_member?.isLoggedIn ?? false)) return;
    }

    final l = context.read<AppState>().l;
    final access = await api.fetchVipAccess(c.id);
    if (!mounted) return;

    // Already open (Pro or previously unlocked) — just retry the stream.
    if (access != null && access.watchable) {
      await _ensure(index);
      return;
    }

    final cost = access?.costGold ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: T.surface,
        title: Text(l.pick('ปลดล็อกโซน VIP', 'Unlock VIP'),
            style: AppTheme.display(16, weight: FontWeight.w700)),
        content: Text(
          l.pick('ใช้ $cost เหรียญทองเพื่อปลดล็อก "${c.title}" ถาวร',
              'Spend $cost gold to unlock "${c.title}" permanently'),
          style: AppTheme.body(13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l.pick('ยกเลิก', 'Cancel'), style: AppTheme.body(13, color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l.pick('ปลดล็อก', 'Unlock'), style: AppTheme.body(13, color: T.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final res = await api.unlockVip(c.id);
    if (!mounted) return;

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_vipErrorText(res.error, l)),
      ));
      return;
    }

    // Balances moved — refresh the member so the coin UI doesn't go stale.
    if (res.wallet?.membership != null) {
      _member?.applyMembershipState(res.wallet!.membership!);
    }
    await _ensure(index);
    if (mounted && index == _current) {
      _controllers[index]
        ?..addListener(_onTick)
        ..play();
    }
  }

  String _vipErrorText(String? code, L10n l) => switch (code) {
        'insufficient' => l.pick('เหรียญทองไม่พอ', 'Not enough gold'),
        'network' => l.pick('เชื่อมต่อไม่ได้ ลองใหม่อีกครั้ง', 'Connection failed — try again'),
        _ => l.pick('ปลดล็อกไม่สำเร็จ ลองใหม่อีกครั้ง', 'Unlock failed — try again'),
      };

  Future<void> _ensure(int index) async {
    if (index < 0 || index >= eps.length) return;
    if (_locked(index)) return; // don't stream a locked episode
    if (_controllers.containsKey(index) || _loading.contains(index)) return;
    final ep = eps[index];
    if (ep.isUnavailable) return; // rendered as an "unavailable" page

    _loading.add(index);
    _failed.remove(index);
    _preparing.remove(index);
    _denied.remove(index);

    try {
      final src = await _api!.resolveSource(ep.id);
      if (!mounted) return;
      if (src == null) {
        _loading.remove(index);
        _errMsg[index] = 'เชื่อมต่อไม่ได้ (ตอน ${ep.number})';
        _failed.add(index);
        setState(() {});
        return;
      }
      if (!src.ready || src.url == null) {
        _loading.remove(index);
        if (src.error != null) {
          // A paywall or a dead source — say so, don't pretend it's mirroring.
          _denied[index] = src.error!;
        } else {
          // Genuinely not mirrored yet.
          _preparing.add(index);
        }
        setState(() {});
        return;
      }

      // Plain networkUrl handles both the mirrored MP4 and the HLS proxy on
      // ExoPlayer. No custom httpHeaders (a User-Agent triggered "Source error"
      // on release builds).
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(src.url!));
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(false);
      final resume = await _db!.getResume(c.id, ep.id);
      if (resume != null && resume > 5 && resume < ctrl.value.duration.inSeconds - 10) {
        await ctrl.seekTo(Duration(seconds: resume));
      }
      _controllers[index] = ctrl;
      _loading.remove(index);
      if (index == _current) {
        ctrl.addListener(_onTick);
        await ctrl.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _loading.remove(index);
      if (!_retried.contains(index)) {
        _retried.add(index);
        if (mounted) {
          await _ensure(index);
          return;
        }
      }
      _errMsg[index] = e.toString();
      _failed.add(index);
      if (mounted) setState(() {});
    }
  }

  void _disposeFarFrom(int center) {
    final far = _controllers.keys.where((i) => (i - center).abs() > 1).toList();
    for (final i in far) {
      _saveResume(i);
      final ctrl = _controllers.remove(i);
      ctrl?.removeListener(_onTick);
      ctrl?.dispose();
    }
  }

  void _onPageChanged(int index) {
    final prev = _controllers[_current];
    if (prev != null) {
      prev.removeListener(_onTick);
      prev.pause();
      _saveResume(_current);
    }
    _current = index;
    _advancing = false;
    _resetMarks();

    final cur = _controllers[index];
    if (cur != null) {
      cur.addListener(_onTick);
      cur.seekTo(cur.value.position); // nudge so the listener fires
      cur.play();
    } else {
      _ensure(index);
    }
    _ensure(index + 1);
    _ensure(index - 1);
    _disposeFarFrom(index);
    // New episode → show the controls again briefly.
    _lastInteract = DateTime.now();
    _chrome = true;
    setState(() {});
  }

  void _onTick() {
    final ctrl = _controllers[_current];
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final now = DateTime.now();
    if (ctrl.value.isPlaying && now.difference(_lastResumeSave).inSeconds >= 5) {
      _lastResumeSave = now;
      _saveResume(_current);
    }

    _marks(ctrl);

    // autoplay-next → swipe to the next episode. Stays as the FALLBACK for a
    // title with no outro marker (and if the marker somehow never fired);
    // `_outroFired` keeps it from racing the countdown/end-card.
    if (!_advancing &&
        !_outroFired &&
        !_finished &&
        ctrl.value.duration > Duration.zero &&
        ctrl.value.position >= ctrl.value.duration &&
        !ctrl.value.isPlaying &&
        _current < eps.length - 1) {
      _advancing = true;
      _pageController.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }

    // Real end with no marker: last episode of a multi-episode title → end card.
    if (!_outroFired &&
        !_finished &&
        ctrl.value.duration > Duration.zero &&
        ctrl.value.position >= ctrl.value.duration &&
        !ctrl.value.isPlaying &&
        _current >= eps.length - 1 &&
        eps.length > 1) {
      _showEndCard();
    }

    // Auto-hide the controls after a few idle seconds of playback (web parity).
    if (_chrome &&
        ctrl.value.isPlaying &&
        now.difference(_lastInteract) > const Duration(seconds: 3)) {
      _chrome = false;
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------ playback markers

  /// Runs every tick. Mirrors the web's `marks()`:
  ///  - inside the intro window → offer "ข้ามอินโทร" (auto-skip if the user opted in)
  ///  - within `outroSeconds` of the end → `_enterOutro()` once
  ///
  /// Uses the LIVE video duration, not `duration_minutes` metadata, because the
  /// outro marker is measured from the end and metadata is often rounded/absent.
  void _marks(VideoPlayerController ctrl) {
    final ep = eps[_current];
    final t = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;

    final introEnd = ep.introEndSeconds;
    final wantSkip = introEnd > 1 && t >= 1 && t < introEnd;
    if (wantSkip != _showSkip) _showSkip = wantSkip;

    if (wantSkip && _autoSkipIntro) {
      _skipIntro();
      return;
    }

    final outro = ep.outroSeconds;
    if (!_outroFired && outro > 0 && dur > 0 && t > 5 && (dur - t) <= outro) {
      _enterOutro();
    }
  }

  void _skipIntro() {
    final ctrl = _controllers[_current];
    final introEnd = eps[_current].introEndSeconds;
    if (ctrl == null || introEnd <= 0) return;
    ctrl.seekTo(Duration(seconds: introEnd));
    _showSkip = false;
  }

  /// Credits reached on the current episode. Last episode → the rate/comment
  /// card; otherwise → the next-episode countdown. Firing HERE rather than at
  /// the true end is the whole point: the viewer is still watching, instead of
  /// having already closed the app during the credits.
  void _enterOutro() {
    _outroFired = true;
    final isLast = _current >= eps.length - 1;
    if (isLast) {
      // Movies qualify too when they carry an outro marker (web parity).
      if (eps.length > 1 || eps[_current].outroSeconds > 0) {
        _showEndCard();
      }
    } else {
      _startNextCountdown();
    }
  }

  void _showEndCard() {
    if (_finished) return;
    _outroFired = true;
    _finished = true;
    _cancelNext();
    if (mounted) setState(() {});
  }

  void _startNextCountdown() {
    _nextTimer?.cancel();
    _nextIn = _nextCountdownSeconds;
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = (_nextIn ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        _nextIn = null;
        _playNextNow();
      } else {
        setState(() => _nextIn = left);
      }
    });
    if (mounted) setState(() {});
  }

  void _cancelNext() {
    _nextTimer?.cancel();
    _nextTimer = null;
    if (_nextIn != null) {
      _nextIn = null;
      if (mounted) setState(() {});
    }
  }

  void _playNextNow() {
    _cancelNext();
    if (_advancing || _current >= eps.length - 1) return;
    _advancing = true;
    _pageController.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  /// Reset per-episode marker state — the web does this in `load()`.
  void _resetMarks() {
    _outroFired = false;
    _showSkip = false;
    _finished = false;
    _cancelNext();
  }

  void _saveResume(int index) {
    final ctrl = _controllers[index];
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final ep = eps[index];
    final pos = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;
    _db?.saveResume(c.id, ep.id, ep.number, pos, dur);

    // Mirror to the server so "continue watching" follows the member across
    // devices. Only for a meaningful mid-episode position (matches the local
    // guard that drops trivial/near-finished resumes), and only when signed in.
    final meaningful = pos >= 5 && (dur <= 0 || pos <= dur - 10);
    if (meaningful && _member?.isLoggedIn == true) {
      _api?.saveProgress(
        contentId: c.id,
        episodeId: ep.id,
        positionSeconds: pos,
        durationSeconds: dur > 0 ? dur : null,
      );
    }
  }

  void _togglePlay() {
    final ctrl = _controllers[_current];
    if (ctrl == null) return;
    final willPlay = !ctrl.value.isPlaying;
    willPlay ? ctrl.play() : ctrl.pause();
    // Keep the controls up while paused; they auto-hide again once it resumes.
    _lastInteract = DateTime.now();
    setState(() => _chrome = true);
  }

  /// Tap on the video toggles the controls (and never pauses) — so a horizontal
  /// movie can play full-frame with nothing covering it. Play/pause is the
  /// centre button.
  void _onVideoTap() {
    setState(() {
      _chrome = !_chrome;
      if (_chrome) _lastInteract = DateTime.now();
    });
  }

  /// Fullscreen = rotate to landscape + show the whole frame (contain) instead
  /// of the vertical cover-crop. Tap again to return to the portrait feed.
  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    SystemChrome.setPreferredOrientations(_fullscreen
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]);
  }

  void _openEpisodeSheet() {
    final l = context.read<AppState>().l;
    // Vertical short-dramas get portrait clip covers; horizontal titles get
    // wider thumbnails. Either way each cell shows the episode's own artwork.
    final vertical = c.isVertical;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.screen,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(l.bi('ตอนทั้งหมด', 'Episodes'),
                        style: AppTheme.display(16, weight: FontWeight.w700)),
                    const Spacer(),
                    Text('${eps.length} ${l.pick('ตอน', 'eps')}',
                        style: AppTheme.body(12.5, color: T.textMuted)),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: vertical ? 4 : 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: vertical ? 0.62 : 1.45,
                  ),
                  itemCount: eps.length,
                  itemBuilder: (_, i) {
                    final active = i == _current;
                    final ep = eps[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _pageController.jumpToPage(i);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // The clip cover — episode thumbnail, falling back to
                            // the title artwork.
                            PosterImage(
                              url: ep.thumbnailUrl ?? c.displayImageUrl,
                              seed: c.id + ep.number,
                              radius: 10,
                            ),
                            // Scrim so the label stays readable over any artwork.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x00000000), Color(0xD9000000)],
                                  stops: [0.45, 1.0],
                                ),
                              ),
                            ),
                            if (ep.isUnavailable)
                              Container(
                                color: const Color(0x99000000),
                                alignment: Alignment.center,
                                child: const Icon(Icons.block_rounded, color: Colors.white70, size: 20),
                              ),
                            Positioned(
                              left: 7,
                              bottom: 6,
                              child: Text('${l.pick('ตอน', 'EP')} ${ep.number}',
                                  style: AppTheme.display(12, weight: FontWeight.w700, color: Colors.white)),
                            ),
                            if (active) ...[
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: T.accent, width: 2),
                                  ),
                                ),
                              ),
                              const Positioned(
                                right: 6,
                                top: 6,
                                child: Icon(Icons.play_circle_fill_rounded, color: T.accent, size: 18),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>(); // rebuild lock overlays after unlock/login
    _isPro = member.isPro;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: eps.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, index) => _EpisodePage(
              controller: _controllers[index],
              failed: _failed.contains(index),
              preparing: _preparing.contains(index),
              deniedReason: _denied[index],
              errorText: _errMsg[index],
              locked: _locked(index),
              episode: eps[index],
              unlockCost: _member?.unlockCost ?? 5,
              fullscreen: _fullscreen,
              onUnlock: () => _unlockAt(index),
              onGoPro: _openGoPro,
              onUnlockVip: () => _unlockVipAt(index),
              onTapVideo: index == _current ? _onVideoTap : null,
              onRetry: () => _ensure(index),
              l: l,
            ),
          ),

          // Persistent NetWix logo — sits below where the chrome would be and
          // stays on even after the controls auto-hide, so a clean fullscreen
          // movie shows nothing but the video + our mark (like the web).
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, top: 52),
                child: _watermark(),
              ),
            ),
          ),

          // Everything else = the auto-hiding chrome. Fades out when idle and
          // stops intercepting taps so a tap anywhere brings it back.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  children: [
                    // top bar (back + title + fullscreen)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              _circleBtn(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.display(15,
                                            weight: FontWeight.w700, color: Colors.white)),
                                    Text('${l.pick('ตอนที่', 'EP')} ${eps[_current].number} · ${_current + 1}/${eps.length}',
                                        style: AppTheme.body(11.5, color: Colors.white70)),
                                  ],
                                ),
                              ),
                              // Fullscreen (landscape) is only meaningful for
                              // horizontal titles; vertical short-dramas already
                              // fill the portrait screen.
                              if (!c.isVertical)
                                _circleBtn(
                                  _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                  _toggleFullscreen,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // centre play / pause
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlay,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: const BoxDecoration(
                              color: Color(0x59000000), shape: BoxShape.circle),
                          child: Icon(
                            (_controllers[_current]?.value.isPlaying ?? false)
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),

                    // right action rail (episodes) — portrait only
                    if (!_fullscreen)
                      Positioned(
                        right: 10,
                        bottom: 130,
                        child: _railBtn(Icons.grid_view_rounded, l.pick('ตอน', 'Eps'), _openEpisodeSheet),
                      ),

                    // bottom: ad (free users, portrait only) + scrubber
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_fullscreen) const AdBanner(placement: 'player', height: 56),
                            _scrubber(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Skip-intro pill — above the scrubber, only inside the intro window.
          if (_showSkip && !_finished && _nextIn == null)
            Positioned(right: 14, bottom: 96, child: SafeArea(child: _skipIntroControl(l))),

          // "ตอนต่อไปกำลังจะเริ่ม" countdown at the credits marker.
          if (_nextIn != null && !_finished)
            Positioned(right: 14, bottom: 96, child: SafeArea(child: _nextUpCard(l))),

          // End-of-series card: rate + comment, at the credits marker or the
          // real end of the last episode.
          if (_finished) Positioned.fill(child: EndCard(content: c, l: l, onClose: _closeEndCard)),
        ],
      ),
    );
  }

  void _closeEndCard() {
    setState(() => _finished = false);
  }

  Widget _skipIntroControl(L10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            _skipIntro();
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(T.rButton),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fast_forward_rounded, size: 17, color: Colors.black),
              const SizedBox(width: 6),
              Text(l.pick('ข้ามอินโทร', 'Skip intro'),
                  style: AppTheme.display(13.5, weight: FontWeight.w700, color: Colors.black)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final v = !_autoSkipIntro;
            setState(() => _autoSkipIntro = v);
            await context.read<AppState>().setAutoSkipIntro(v);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(T.rButton),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_autoSkipIntro ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(l.pick('ข้ามอัตโนมัติ', 'Auto-skip'),
                  style: AppTheme.body(11.5, color: Colors.white)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _nextUpCard(L10n l) {
    final next = _current + 1 < eps.length ? eps[_current + 1] : null;
    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.hairlineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.pick('ตอนต่อไปกำลังจะเริ่ม · $_nextIn', 'Next episode in $_nextIn'),
              style: AppTheme.body(12.5, weight: FontWeight.w700, color: Colors.white)),
          if (next != null) ...[
            const SizedBox(height: 2),
            Text(next.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(11.5, color: T.textMuted)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            GestureDetector(
              onTap: _playNextNow,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                child: Text(l.pick('เล่นเลย', 'Play now'),
                    style: AppTheme.display(12.5, weight: FontWeight.w700, color: T.onAccent)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _cancelNext,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(l.pick('ยกเลิก', 'Cancel'),
                    style: AppTheme.body(12.5, color: T.textMuted)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _scrubber() {
    final ctrl = _controllers[_current];
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox(height: 24);
    }
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          Text(Format.duration(pos.inSeconds),
              style: AppTheme.body(10.5, color: Colors.white70)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                activeTrackColor: T.accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: T.accentHi,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              ),
              child: Slider(
                value: dur.inMilliseconds == 0
                    ? 0
                    : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                max: dur.inMilliseconds.toDouble().clamp(1, double.infinity),
                onChanged: (v) => ctrl.seekTo(Duration(milliseconds: v.toInt())),
              ),
            ),
          ),
          Text(Format.duration(dur.inSeconds),
              style: AppTheme.body(10.5, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _railBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Color(0x33000000), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(label, style: AppTheme.body(10, color: Colors.white70)),
            ],
          ],
        ),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(color: Color(0x55000000), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  /// Always-on NetWix wordmark, top-left — the app twin of the web's
  /// `partials/player-watermark`. Bigger over vertical clips (which fill the
  /// frame) so it still reads as ours. Never intercepts taps.
  Widget _watermark() => IgnorePointer(
        child: Opacity(
          opacity: 0.9,
          child: Image.asset(
            'assets/brand/netwix-wordmark.png',
            height: c.isVertical ? 30 : 22,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
}

/// One full-screen page in the vertical feed.
class _EpisodePage extends StatelessWidget {
  const _EpisodePage({
    required this.controller,
    required this.failed,
    required this.preparing,
    required this.deniedReason,
    required this.errorText,
    required this.locked,
    required this.episode,
    required this.unlockCost,
    required this.fullscreen,
    required this.onUnlock,
    required this.onGoPro,
    required this.onUnlockVip,
    required this.onTapVideo,
    required this.onRetry,
    required this.l,
  });

  final VideoPlayerController? controller;
  final bool failed;
  final bool preparing;

  /// Server refusal code (`pro_required` / `vip_required` / `no_source`), or null.
  final String? deniedReason;
  final String? errorText;
  final bool locked;
  final Episode episode;
  final int unlockCost;

  /// Landscape-locked fullscreen mode (else the portrait TikTok feed).
  final bool fullscreen;
  final VoidCallback onUnlock;

  /// Paywall CTAs for a server refusal. Null hides the button (the message still
  /// tells the viewer what's actually wrong).
  final VoidCallback? onGoPro;
  final VoidCallback? onUnlockVip;
  final VoidCallback? onTapVideo;
  final VoidCallback onRetry;
  final L10n l;

  /// Fill the portrait feed for vertical clips (cover), but show the WHOLE
  /// frame for landscape movies/series so nothing is cropped — both in the
  /// portrait feed and in landscape fullscreen (which letterboxes verticals).
  BoxFit _fitFor(VideoPlayerController? ctrl) {
    final landscape =
        ctrl != null && ctrl.value.isInitialized && ctrl.value.aspectRatio > 1.05;
    return (fullscreen || landscape) ? BoxFit.contain : BoxFit.cover;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final fit = _fitFor(ctrl);

    if (locked) {
      return _StatusPage(
        icon: Icons.lock_rounded,
        title: '${l.pick('ตอนที่', 'EP')} ${episode.number} ${l.pick('ถูกล็อก', 'locked')}',
        subtitle: l.pick('ดูฟรี 3 ตอนแรก · ตอนถัดไปใช้เหรียญ', 'First 3 free · unlock with coins'),
        action: GestureDetector(
          onTap: onUnlock,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
                gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_open_rounded, color: T.onAccent, size: 18),
              const SizedBox(width: 8),
              Text('${l.pick('ปลดล็อก', 'Unlock')} · $unlockCost ${l.pick('เหรียญ', 'coins')}',
                  style: AppTheme.display(14, weight: FontWeight.w700, color: T.onAccent)),
            ]),
          ),
        ),
      );
    }

    if (episode.isUnavailable) {
      return _StatusPage(
        icon: Icons.block_rounded,
        title: '${l.pick('ตอนที่', 'EP')} ${episode.number}',
        subtitle: l.pick('ตอนนี้ยังไม่พร้อมให้ชม', 'This episode is unavailable'),
      );
    }

    // The server refused this stream — a paywall or a dead source. Each needs its
    // own message: telling someone to "check back soon" for content that needs a
    // purchase (or is gone for good) just makes them wait for nothing.
    if (deniedReason != null) {
      switch (deniedReason) {
        case 'pro_required':
          return _StatusPage(
            icon: Icons.workspace_premium_rounded,
            title: l.pick('เฉพาะสมาชิก Pro', 'Pro members only'),
            subtitle: l.pick(
                'เรื่องนี้เรต 18+ ต้องเป็นสมาชิก Pro จึงจะรับชมได้', 'This 18+ title requires a Pro membership'),
            action: onGoPro == null
                ? null
                : GestureDetector(
                    onTap: onGoPro,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                          gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                      child: Text(l.pick('สมัคร Pro', 'Get Pro'),
                          style: AppTheme.display(14, weight: FontWeight.w700, color: T.onAccent)),
                    ),
                  ),
          );
        case 'vip_required':
          return _StatusPage(
            icon: Icons.diamond_rounded,
            title: l.pick('โซน VIP', 'VIP zone'),
            subtitle: l.pick('ปลดล็อกเรื่องนี้ด้วยเหรียญทอง', 'Unlock this title with gold coins'),
            action: onUnlockVip == null
                ? null
                : GestureDetector(
                    onTap: onUnlockVip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                          gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🥇', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Text(l.pick('ปลดล็อก VIP', 'Unlock VIP'),
                            style: AppTheme.display(14, weight: FontWeight.w700, color: T.onAccent)),
                      ]),
                    ),
                  ),
          );
        default: // no_source — gone upstream; retrying will never help.
          return _StatusPage(
            icon: Icons.block_rounded,
            title: '${l.pick('ตอนที่', 'EP')} ${episode.number}',
            subtitle: l.pick('ตอนนี้ไม่มีให้รับชมแล้ว', 'This episode is no longer available'),
          );
      }
    }

    if (preparing) {
      return _StatusPage(
        icon: Icons.hourglass_bottom_rounded,
        title: l.pick('กำลังเตรียมตอนนี้', 'Preparing this episode'),
        subtitle: l.pick('ระบบกำลังเตรียมไฟล์ ลองใหม่อีกครั้งภายหลัง', 'Being mirrored — check back soon'),
        action: TextButton(
          onPressed: onRetry,
          child: Text(l.pick('ลองใหม่', 'Retry'), style: AppTheme.body(13, color: T.accent)),
        ),
      );
    }

    return GestureDetector(
      onTap: onTapVideo,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ctrl != null && ctrl.value.isInitialized)
              FittedBox(
                fit: fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: ctrl.value.size.width,
                  height: ctrl.value.size.height,
                  child: VideoPlayer(ctrl),
                ),
              )
            else if (failed)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.pick('เล่นวิดีโอไม่สำเร็จ', 'Playback failed'),
                          style: AppTheme.body(14, weight: FontWeight.w600, color: Colors.white)),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(errorText!,
                            textAlign: TextAlign.center,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(11, color: Colors.white54)),
                      ],
                      TextButton(
                        onPressed: onRetry,
                        child: Text(l.pick('ลองใหม่', 'Retry'),
                            style: AppTheme.body(13, color: T.accent)),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: T.accent)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen centred status card (locked / unavailable / preparing).
class _StatusPage extends StatelessWidget {
  const _StatusPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0B0B0C)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: T.accent, size: 56),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: AppTheme.display(18, weight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(subtitle,
                    textAlign: TextAlign.center,
                    style: AppTheme.body(12.5, color: Colors.white70)),
              ),
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
