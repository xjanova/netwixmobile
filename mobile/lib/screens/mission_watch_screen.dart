import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/mission.dart';
import '../services/netwix_api.dart';
import '../services/webview_guard.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// ภารกิจ: ดูคลิปรับเหรียญ — plays the mission video (direct URL via
/// [VideoPlayerController], YouTube via an IFrame-API WebView) and sends a
/// heartbeat every ~15s ONLY while the video is playing AND the app is in the
/// foreground. The server (MissionService) validates real wall-clock time
/// between beats and grants the reward once watched ≥ required — the app never
/// decides the reward itself.
class MissionWatchScreen extends StatefulWidget {
  const MissionWatchScreen({super.key, required this.mission});

  final MissionItem mission;

  @override
  State<MissionWatchScreen> createState() => _MissionWatchScreenState();
}

class _MissionWatchScreenState extends State<MissionWatchScreen>
    with WidgetsBindingObserver {
  static const _beatEvery = Duration(seconds: 15);

  VideoPlayerController? _video;
  WebViewController? _web;

  String? _token;
  Timer? _beatTimer;
  bool _playing = false;
  bool _foreground = true;
  bool _beating = false; // one beat in flight at a time
  bool _done = false;
  String? _rewardLabel;
  String? _error;
  int _watched = 0;
  int _required = 0;

  MissionItem get mission => widget.mission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _required = mission.requiredSeconds;
    _watched = mission.watched;
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _beatTimer?.cancel();
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anti-cheat contract: beats only while the app is actually visible.
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _start() async {
    final res = await context.read<NetwixApi>().startMission(mission.id);
    if (!mounted) return;

    if (!res.ok) {
      setState(() => _error = res.error ??
          (res.alreadyEarned ? 'ภารกิจนี้รับรางวัลแล้ว' : 'เริ่มภารกิจไม่สำเร็จ ลองใหม่อีกครั้ง'));
      return;
    }

    setState(() {
      _token = res.token;
      if (res.required > 0) _required = res.required;
      _watched = 0; // a (re)start resets the attempt server-side
    });

    if (mission.isYoutube) {
      _initYoutube();
    } else {
      await _initVideo();
    }
    _beatTimer = Timer.periodic(_beatEvery, (_) => _beat());
  }

  // ------------------------------------------------------------ players

  Future<void> _initVideo() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(mission.videoRef));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c
        ..addListener(_onVideoTick)
        ..setLooping(true) // keep playing if the clip is shorter than required
        ..play();
      setState(() => _video = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = 'เปิดวิดีโอไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  void _onVideoTick() {
    final playing = _video?.value.isPlaying ?? false;
    if (playing != _playing) setState(() => _playing = playing);
  }

  void _initYoutube() {
    // The ref is interpolated into HTML/JS below — keep strictly to the YT-id
    // alphabet so a malformed admin value can't break out of the script.
    final ytId = mission.videoRef.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    // YT IFrame API page: state changes flow back through the `State` JS channel
    // (1 = playing), so beats stop the moment the user pauses.
    final html = '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{width:100%;height:100%}</style>
</head><body>
<div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function onYouTubeIframeAPIReady(){
  player = new YT.Player('p', {
    videoId: '$ytId',
    playerVars: {playsinline: 1, rel: 0},
    events: {onStateChange: function(e){ State.postMessage(String(e.data)); }}
  });
}
</script>
</body></html>''';

    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(playerOnlyNavigation())
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('State', onMessageReceived: (msg) {
        final playing = msg.message == '1';
        if (playing != _playing && mounted) setState(() => _playing = playing);
      })
      ..loadHtmlString(html, baseUrl: 'https://www.youtube.com');
    setState(() => _web = web);
  }

  // ---------------------------------------------------------- heartbeat

  Future<void> _beat() async {
    final token = _token;
    if (token == null || _done || _beating) return;
    if (!_playing || !_foreground) return; // the anti-cheat contract

    _beating = true;
    try {
      final res = await context.read<NetwixApi>().beatMission(mission.id, token);
      if (!mounted) return;

      if (!res.ok) {
        // A server REJECTION (bad/reset token) is fatal; a transient network
        // blip (no error payload) just skips this beat — the next one catches
        // up (the server caps a long gap's credit, so nothing is farmable).
        if (res.error != null) {
          setState(() => _error = res.error);
          _beatTimer?.cancel();
        }
        return;
      }

      setState(() {
        _watched = res.watched;
        if (res.required > 0) _required = res.required;
        if (res.done) {
          _done = true;
          _rewardLabel = res.rewardLabel;
        }
      });

      if (res.done) {
        _beatTimer?.cancel();
        _video?.pause();
        // The beat carries the fresh balance — coins update app-wide at once.
        final member = context.read<MemberState>();
        if (res.membership != null) member.applyMembershipState(res.membership!);
        unawaited(member.refreshMissions());
      }
    } finally {
      _beating = false;
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final progress = _required > 0 ? (_watched / _required).clamp(0.0, 1.0) : 0.0;
    final remain = (_required - _watched).clamp(0, _required);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(mission.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display(16, weight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _player()),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppTheme.body(13.5, color: T.textSecondary)),
            )
          else ...[
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    backgroundColor: T.hairlineStrong,
                    valueColor: const AlwaysStoppedAnimation(T.accent),
                  ),
                ),
                Text(
                  _done ? '✓' : '${remain}s',
                  style: AppTheme.display(_done ? 30 : 18, weight: FontWeight.w700, color: T.accent),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _done
                    ? l.pick('สำเร็จ! ได้รับ ${_rewardLabel ?? mission.rewardLabel} 🎉',
                        'Done! You earned ${_rewardLabel ?? mission.rewardLabel} 🎉')
                    : l.pick(
                        'ดูวิดีโอต่อเนื่องให้ครบ เพื่อรับ ${mission.rewardLabel}\n(นับเฉพาะตอนที่เล่นอยู่และเปิดแอปค้างไว้)',
                        'Keep the video playing to earn ${mission.rewardLabel}\n(only counts while playing in the foreground)'),
                textAlign: TextAlign.center,
                style: AppTheme.body(13.5, color: T.textSecondary),
              ),
            ),
            if (!_done && !_playing && _token != null) ...[
              const SizedBox(height: 8),
              Text(l.pick('▶ กดเล่นวิดีโอเพื่อเริ่มนับเวลา', '▶ Press play to start counting'),
                  style: AppTheme.body(12.5, color: T.accent)),
            ],
          ],
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
            child: AccentButton(
              label: _done ? l.pick('เสร็จสิ้น', 'Finish') : l.pick('กลับ', 'Back'),
              icon: _done ? Icons.check_circle_rounded : Icons.arrow_back_rounded,
              enabled: true,
              onPressed: () => Navigator.of(context).pop(_done),
            ),
          ),
        ],
      ),
    );
  }

  Widget _player() {
    if (_error != null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.error_outline_rounded, color: T.textFaint, size: 40)),
      );
    }
    if (mission.isYoutube) {
      final web = _web;
      return web == null
          ? const Center(child: CircularProgressIndicator(color: T.accent))
          : WebViewWidget(controller: web);
    }
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: T.accent));
    }
    return GestureDetector(
      onTap: () => v.value.isPlaying ? v.pause() : v.play(),
      child: VideoPlayer(v),
    );
  }
}
