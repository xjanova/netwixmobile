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
import '../widgets/unlock_sheet.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ad_banner.dart';

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
  final Set<int> _preparing = {}; // episode not mirrored yet (ready:false)
  final Set<int> _retried = {}; // one retry per episode
  final Map<int, String> _errMsg = {};

  NetwixApi? _api;
  CatalogDb? _db;
  MemberState? _member;
  bool _isPro = false;

  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _advancing = false;

  Content get c => widget.content;
  List<Episode> get eps => widget.episodes;

  @override
  void initState() {
    super.initState();
    final start = eps.indexWhere((e) => e.id == widget.startEpisodeId);
    _current = (start < 0 ? 0 : start).clamp(0, eps.length - 1);
    _pageController = PageController(initialPage: _current);
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
      _isPro = context.read<AppState>().isPro;
      _ensure(_current);
      _ensure(_current + 1);
      _ensure(_current - 1);
    }
  }

  @override
  void dispose() {
    _saveResume(_current);
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

  Future<void> _ensure(int index) async {
    if (index < 0 || index >= eps.length) return;
    if (_locked(index)) return; // don't stream a locked episode
    if (_controllers.containsKey(index) || _loading.contains(index)) return;
    final ep = eps[index];
    if (ep.isUnavailable) return; // rendered as an "unavailable" page

    _loading.add(index);
    _failed.remove(index);
    _preparing.remove(index);

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
        // NetWix hasn't mirrored this episode yet — show "preparing".
        _loading.remove(index);
        _preparing.add(index);
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

    // autoplay-next → swipe to the next episode
    if (!_advancing &&
        ctrl.value.duration > Duration.zero &&
        ctrl.value.position >= ctrl.value.duration &&
        !ctrl.value.isPlaying &&
        _current < eps.length - 1) {
      _advancing = true;
      _pageController.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
    if (mounted) setState(() {});
  }

  void _saveResume(int index) {
    final ctrl = _controllers[index];
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final ep = eps[index];
    _db?.saveResume(
        c.id, ep.id, ep.number, ctrl.value.position.inSeconds, ctrl.value.duration.inSeconds);
  }

  void _togglePlay() {
    final ctrl = _controllers[_current];
    if (ctrl == null) return;
    setState(() => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play());
  }

  void _openEpisodeSheet() {
    final l = context.read<AppState>().l;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.screen,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.bi('ตอนทั้งหมด', 'Episodes'),
                  style: AppTheme.display(16, weight: FontWeight.w700)),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4),
                itemCount: eps.length,
                itemBuilder: (_, i) {
                  final active = i == _current;
                  final ep = eps[i];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      _pageController.jumpToPage(i);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: active ? T.accentGradient : null,
                        color: active ? null : const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? Colors.transparent : T.hairline),
                      ),
                      child: Text('${ep.number}',
                          style: AppTheme.display(14,
                              weight: FontWeight.w700,
                              color: active
                                  ? T.onAccent
                                  : ep.isUnavailable
                                      ? T.textFaint
                                      : T.textSecondary)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    _isPro = context.watch<AppState>().isPro;
    context.watch<MemberState>(); // rebuild lock overlays after unlock/login
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
              errorText: _errMsg[index],
              locked: _locked(index),
              episode: eps[index],
              unlockCost: _member?.unlockCost ?? 5,
              onUnlock: () => _unlockAt(index),
              onTapVideo: index == _current ? _togglePlay : null,
              onRetry: () => _ensure(index),
              l: l,
            ),
          ),
          // top bar (back + title)
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
                  ],
                ),
              ),
            ),
          ),
          // right action rail (episodes list)
          Positioned(
            right: 10,
            bottom: 130,
            child: Column(
              children: [
                _railBtn(Icons.grid_view_rounded, l.pick('ตอน', 'Eps'), _openEpisodeSheet),
                const SizedBox(height: 18),
                _railBtn(
                  _controllers[_current]?.value.isPlaying ?? false
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  '',
                  _togglePlay,
                ),
              ],
            ),
          ),
          // bottom: ad (free users) + scrubber
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AdBanner(placement: 'player', height: 56),
                  _scrubber(),
                ],
              ),
            ),
          ),
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
}

/// One full-screen page in the vertical feed.
class _EpisodePage extends StatelessWidget {
  const _EpisodePage({
    required this.controller,
    required this.failed,
    required this.preparing,
    required this.errorText,
    required this.locked,
    required this.episode,
    required this.unlockCost,
    required this.onUnlock,
    required this.onTapVideo,
    required this.onRetry,
    required this.l,
  });

  final VideoPlayerController? controller;
  final bool failed;
  final bool preparing;
  final String? errorText;
  final bool locked;
  final Episode episode;
  final int unlockCost;
  final VoidCallback onUnlock;
  final VoidCallback? onTapVideo;
  final VoidCallback onRetry;
  final L10n l;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;

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
                fit: BoxFit.cover,
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

            // paused indicator (only for the active, tappable page)
            if (onTapVideo != null && ctrl != null && ctrl.value.isInitialized && !ctrl.value.isPlaying)
              const Center(
                child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 74),
              ),
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
