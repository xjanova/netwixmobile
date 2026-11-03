import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/content.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import 'comment_sheet.dart';
import 'login_sheet.dart';

/// Share a title through the system sheet, with the member's invite link when signed in, and pay
/// the share reward when the sheet reports a real share. Used by the rail and the detail page.
Future<void> shareContent(BuildContext context, Content c) async {
  final l = context.read<AppState>().l;
  final member = context.read<MemberState>();
  final messenger = ScaffoldMessenger.of(context);
  final invite = member.isLoggedIn ? '\nสมัครฟรี / Sign up: ${member.shareLink}' : '';
  final shared = await SharePlus.instance.share(ShareParams(
    text: l.pick('ดู "${c.title}" ฟรีบน NetWix 🎬\n${NetwixApi.titleUrl(c.slug)}',
            'Watch "${c.title}" free on NetWix 🎬\n${NetwixApi.titleUrl(c.slug)}') +
        invite,
  ));
  if (shared.status != ShareResultStatus.success) return;
  final got = await member.awardShare();
  if (got > 0) messenger.showSnackBar(SnackBar(content: Text('+$got ${l.pick('เหรียญ', 'coins')} 🪙')));
}

/// Like · comment · share, stacked for the right edge of Shorts and the player — the app twin of
/// the web player's rail. Same rows as netwix.online: a like or comment made here shows on the web
/// and the other way round.
///
/// Counts load for everyone (`/content/{id}/state` is public); a member also gets their own liked
/// flag. Liking or commenting as a guest opens the sign-in sheet first.
class SocialRail extends StatefulWidget {
  const SocialRail({super.key, required this.content, this.gap = 16});

  final Content content;
  final double gap;

  @override
  State<SocialRail> createState() => _SocialRailState();
}

class _SocialRailState extends State<SocialRail> {
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  bool _liking = false;
  bool _sharing = false;
  bool? _wasLoggedIn;

  int get _id => widget.content.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SocialRail old) {
    super.didUpdateWidget(old);
    if (old.content.id != _id) {
      // Recycled for another title (Shorts pages): drop the old title's state before loading.
      setState(() {
        _liked = false;
        _likes = 0;
        _comments = 0;
        _liking = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final id = _id;
    final st = await context.read<NetwixApi>().fetchContentState(id);
    // The rail may have moved to another title while this was in flight.
    if (!mounted || st == null || id != _id) return;
    setState(() {
      _liked = st.liked;
      _likes = st.likesCount;
      _comments = st.commentsCount;
    });
  }

  Future<bool> _requireLogin() async {
    if (context.read<MemberState>().isLoggedIn) return true;
    await showLoginSheet(context);
    if (!mounted || !context.read<MemberState>().isLoggedIn) return false;
    // Learn whether this member already likes the title before flipping it.
    await _load();
    return mounted;
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    final api = context.read<NetwixApi>();
    final member = context.read<MemberState>();
    final l = context.read<AppState>().l;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _requireLogin()) return;

    final id = _id;
    final was = _liked;
    HapticFeedback.lightImpact();
    setState(() {
      _liking = true;
      _liked = !was;
      _likes = (_likes + (was ? -1 : 1)).clamp(0, 1 << 31);
    });
    final res = await api.toggleLike(id);
    if (!mounted || id != _id) return;
    setState(() {
      _liking = false;
      if (res != null) {
        _liked = res.liked;
        _likes = res.likesCount;
      } else {
        _liked = was;
        _likes = (_likes + (was ? 1 : -1)).clamp(0, 1 << 31);
      }
    });
    if (res == null) {
      messenger.showSnackBar(SnackBar(
          content: Text(l.pick('กดถูกใจไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่', 'Could not like — check your connection'))));
      return;
    }
    // Coins only for turning a like ON (server + daily cap stop farming by toggling).
    if (res.liked) {
      final got = await member.awardLike();
      if (got > 0) messenger.showSnackBar(SnackBar(content: Text('+$got ${l.pick('เหรียญ', 'coins')} 🪙')));
    }
  }

  Future<void> _openComments() async {
    final id = _id;
    await showCommentSheet(context, id, onCount: (n) {
      if (mounted && id == _id) setState(() => _comments = n);
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    try {
      await shareContent(context, widget.content);
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    // Signed in or out while the rail is up: reload so the heart reflects this account.
    final loggedIn = context.select<MemberState, bool>((m) => m.isLoggedIn);
    if (_wasLoggedIn != null && _wasLoggedIn != loggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!loggedIn) setState(() => _liked = false);
        _load();
      });
    }
    _wasLoggedIn = loggedIn;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      _button(
        icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: _liked ? const Color(0xFFFF2D55) : Colors.white,
        label: _likes > 0 ? _compact(_likes) : l.pick('ถูกใจ', 'Like'),
        semantics: l.pick('ถูกใจ', 'Like'),
        selected: _liked,
        onTap: _toggleLike,
      ),
      SizedBox(height: widget.gap),
      _button(
        icon: Icons.chat_bubble_outline_rounded,
        label: _comments > 0 ? _compact(_comments) : l.pick('เม้นต์', 'Comment'),
        semantics: l.pick('ความคิดเห็น', 'Comments'),
        onTap: _openComments,
      ),
      SizedBox(height: widget.gap),
      _button(
        icon: Icons.reply_rounded,
        mirror: true,
        label: l.pick('แชร์', 'Share'),
        semantics: l.pick('แชร์', 'Share'),
        onTap: _share,
      ),
    ]);
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    final s = k < 10 ? k.toStringAsFixed(1) : k.toStringAsFixed(0);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}K';
  }

  Widget _button({
    required IconData icon,
    required String label,
    required String semantics,
    required VoidCallback onTap,
    Color color = Colors.white,
    bool mirror = false,
    bool selected = false,
  }) {
    Widget glyph = Icon(icon, size: 25, color: color);
    if (mirror) glyph = Transform.flip(flipX: true, child: glyph);
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Color(0x800B0712), shape: BoxShape.circle),
              child: Center(child: glyph),
            ),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: AppTheme.body(11, weight: FontWeight.w600, color: Colors.white)
                  .copyWith(shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 6)])),
        ]),
      ),
    );
  }
}
