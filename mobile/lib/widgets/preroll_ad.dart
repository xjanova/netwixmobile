import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/l10n.dart';
import '../models/ad.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Blocking pre-roll ad shown before an episode starts — the app-side mirror of
/// the web player's pre-roll overlay (`partials/preroll-ad`).
///
/// The app previously rendered a small rotating *banner* fed by a phantom
/// endpoint on another host, so admin ad campaigns never reached mobile at all.
/// This plays the real campaign: an image, a direct video, or a YouTube creative.
///
/// Whether an ad shows at all (targeting, schedule, hide_for_pro) is decided
/// server-side; this widget only renders what it's handed and reports when the
/// viewer is done via [onFinished].
class PrerollAdOverlay extends StatefulWidget {
  const PrerollAdOverlay({super.key, required this.ad, required this.l, required this.onFinished});

  final PrerollAd ad;
  final L10n l;

  /// Fired exactly once — on skip, on natural completion, or on a creative that
  /// fails to load. Playback must never be permanently blocked by an ad.
  final VoidCallback onFinished;

  @override
  State<PrerollAdOverlay> createState() => _PrerollAdOverlayState();
}

class _PrerollAdOverlayState extends State<PrerollAdOverlay> {
  VideoPlayerController? _video;
  WebViewController? _web;
  Timer? _ticker;

  int _elapsed = 0;
  bool _done = false;

  PrerollAd get ad => widget.ad;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      // An image creative has no natural end — close it on its own timer.
      if (ad.isImage && _elapsed >= ad.imageSeconds) _finish();
    });

    if (ad.isYoutube) {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..loadHtmlString(_youtubeHtml(ad.youtube!));
      if (mounted) setState(() {});
      return;
    }

    if (!ad.isImage && (ad.src?.isNotEmpty ?? false)) {
      final c = VideoPlayerController.networkUrl(Uri.parse(ad.src!));
      try {
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        c.addListener(_onVideoTick);
        await c.play();
        setState(() => _video = c);
      } catch (_) {
        await c.dispose();
        _finish(); // a broken creative must not hold the viewer hostage
      }
    }
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    if (v.value.duration > Duration.zero && v.value.position >= v.value.duration) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker?.cancel();
    _video?.pause();
    widget.onFinished();
  }

  /// A YouTube creative can't be measured, so it falls back to the same timed
  /// close an image gets. Id is sanitised before interpolation.
  String _youtubeHtml(String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%}</style>
</head><body>
<iframe src="https://www.youtube.com/embed/$safe?autoplay=1&playsinline=1&controls=0&rel=0"
        allow="autoplay; encrypted-media" allowfullscreen></iframe>
</body></html>''';
  }

  bool get _canSkip => ad.skippable && _elapsed >= ad.skipAfter;
  int get _skipIn => (ad.skipAfter - _elapsed).clamp(0, ad.skipAfter);

  @override
  Widget build(BuildContext context) {
    final l = widget.l;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: _creative()),

          // Tap-through to the advertiser.
          if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty)
            Positioned(
              left: 16,
              bottom: 20,
              child: GestureDetector(
                onTap: () => _open(ad.linkUrl!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                      gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                  child: Text(l.pick('ดูเพิ่มเติม', 'Learn more'),
                      style: AppTheme.display(13, weight: FontWeight.w700, color: T.onAccent)),
                ),
              ),
            ),

          // "โฆษณา" marker — the viewer should always know this is an ad.
          Positioned(
            left: 14,
            top: 14,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(l.pick('โฆษณา', 'Ad'),
                    style: AppTheme.body(11, color: Colors.white)),
              ),
            ),
          ),

          if (ad.caption != null && ad.caption!.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: ad.linkUrl != null && ad.linkUrl!.isNotEmpty ? 68 : 20,
              child: Text(
                ad.caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(13, color: Colors.white),
              ),
            ),

          // Skip control. A non-skippable campaign shows nothing here and simply
          // plays out.
          if (ad.skippable)
            Positioned(
              right: 14,
              top: 14,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _canSkip ? _finish : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _canSkip ? Colors.white : Colors.black54,
                      borderRadius: BorderRadius.circular(T.rButton),
                    ),
                    child: Text(
                      _canSkip
                          ? '${l.pick('ข้ามโฆษณา', 'Skip ad')} ›'
                          : l.pick('ข้ามได้ใน $_skipIn', 'Skip in $_skipIn'),
                      style: AppTheme.display(12.5,
                          weight: FontWeight.w700,
                          color: _canSkip ? Colors.black : Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _creative() {
    if (ad.isYoutube) {
      return _web == null
          ? const CircularProgressIndicator(color: T.accent)
          : WebViewWidget(controller: _web!);
    }
    if (ad.isImage) {
      return CachedNetworkImage(
        imageUrl: ad.src!,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) {
          // Don't strand the viewer on a broken creative.
          WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
          return const SizedBox.shrink();
        },
      );
    }
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      return const CircularProgressIndicator(color: T.accent);
    }
    return AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v));
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
