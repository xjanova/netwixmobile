import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/content.dart';
import '../models/member.dart';
import '../services/format.dart';
import '../services/netwix_api.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import 'login_sheet.dart';

/// End-of-series card — "🎉 ดูจบแล้ว!" + 1-5 stars + a comment box + the latest
/// comments.
///
/// Mirrors the web's end card (`watch.blade.php` / `vertical-player.blade.php`
/// `showEndCard`), which fires on the LAST episode of a multi-episode title, or
/// at the credits marker for a long movie. Anchoring it to the credits — rather
/// than the true end — is the point: it asks while the viewer is still there,
/// instead of after they've already closed the app.
///
/// Reuses the same rate/comment endpoints as the rest of the app; no new API.
class EndCard extends StatefulWidget {
  const EndCard({super.key, required this.content, required this.l, required this.onClose});

  final Content content;
  final L10n l;
  final VoidCallback onClose;

  @override
  State<EndCard> createState() => _EndCardState();
}

class _EndCardState extends State<EndCard> {
  final _commentCtrl = TextEditingController();

  int _myRating = 0;
  double _avg = 0;
  int _count = 0;
  List<Comment> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<NetwixApi>();
    final id = widget.content.id;
    final isMember = context.read<MemberState>().isLoggedIn;

    // Ratings/comments are public; my_rating only exists for a member.
    final summary = await api.fetchRatings(id);
    final comments = await api.fetchComments(id);
    final state = isMember ? await api.fetchContentState(id) : null;
    if (!mounted) return;

    setState(() {
      _avg = state?.ratingAvg ?? summary?.avg ?? 0;
      _count = state?.ratingCount ?? summary?.count ?? 0;
      _myRating = state?.myRating ?? 0;
      _comments = comments.take(6).toList();
      _loading = false;
    });
  }

  Future<bool> _requireLogin() async {
    if (context.read<MemberState>().isLoggedIn) return true;
    await showLoginSheet(context);
    if (!mounted) return false;
    return context.read<MemberState>().isLoggedIn;
  }

  Future<void> _rate(int stars) async {
    if (!await _requireLogin() || !mounted) return;

    final prev = _myRating;
    setState(() => _myRating = stars); // optimistic
    final res = await context.read<NetwixApi>().postRating(widget.content.id, stars);
    if (!mounted) return;

    if (res == null) {
      setState(() => _myRating = prev); // revert — the server didn't take it
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.l.pick('ให้คะแนนไม่สำเร็จ', 'Could not save your rating')),
      ));
      return;
    }
    setState(() {
      _myRating = res.myRating;
      _avg = res.avg;
      _count = res.count;
      _rated = true;
    });
  }

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await _requireLogin() || !mounted) return;

    setState(() => _sending = true);
    final saved = await context.read<NetwixApi>().postComment(widget.content.id, text);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (saved != null) {
        _comments = [saved, ..._comments].take(6).toList();
        _commentCtrl.clear();
      }
    });

    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.l.pick('ส่งความคิดเห็นไม่สำเร็จ', 'Could not post your comment')),
      ));
      return;
    }

    final got = await context.read<MemberState>().awardComment();
    if (mounted && got > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('+$got ${widget.l.pick('เหรียญ', 'coins')} 🪙'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: T.textSecondary),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Center(
                    child: Text('🎉 ${l.pick('ดูจบแล้ว!', 'You finished it!')}',
                        style: AppTheme.display(22, weight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      widget.content.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(13, color: T.textMuted),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      _rated
                          ? l.pick('ขอบคุณสำหรับคะแนน!', 'Thanks for rating!')
                          : l.pick('ให้คะแนนเรื่องนี้', 'Rate this title'),
                      style: AppTheme.body(13.5, weight: FontWeight.w700, color: T.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: _stars()),
                  if (_count > 0) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        '★ ${_avg.toStringAsFixed(1)} · ${l.pick('$_count คะแนน', '$_count ratings')}',
                        style: AppTheme.body(11.5, color: T.textFaint),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(l.bi('ความคิดเห็น', 'Comments'),
                      style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
                  const SizedBox(height: 8),
                  _composer(l),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(child: CircularProgressIndicator(color: T.accent))
                  else if (_comments.isEmpty)
                    Text(l.pick('ยังไม่มีความคิดเห็น เป็นคนแรกเลย!', 'No comments yet — be first!'),
                        style: AppTheme.body(12.5, color: T.textMuted))
                  else
                    for (final c in _comments) _commentRow(c, l),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => _rate(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                i <= _myRating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 34,
                color: i <= _myRating ? const Color(0xFFF5A623) : T.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _composer(L10n l) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0x10FFFFFF),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: T.hairline),
            ),
            child: TextField(
              controller: _commentCtrl,
              style: AppTheme.body(13.5, color: T.textPrimary),
              cursorColor: T.accent,
              minLines: 1,
              maxLines: 3,
              maxLength: 500, // server caps at 500 (FeedbackController)
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l.pick('เขียนความคิดเห็น…', 'Write a comment…'),
                hintStyle: AppTheme.body(13.5, color: T.textMuted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sending ? null : _send,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(gradient: T.accentGradient, shape: BoxShape.circle),
            child: _sending
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2, color: T.onAccent),
                  )
                : const Icon(Icons.send_rounded, color: T.onAccent, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _commentRow(Comment c, L10n l) {
    final when = c.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HexAvatar(
            size: 30,
            tint: HexAvatar.parseColor(c.avatarColor),
            child: Center(
              child: Text(c.initial,
                  style: AppTheme.display(12.5, weight: FontWeight.w700, color: T.textPrimary)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(12, weight: FontWeight.w700, color: T.textPrimary)),
                  ),
                  if (when != null) ...[
                    const SizedBox(width: 8),
                    Text(Format.ago(when, thai: l.isTh),
                        style: AppTheme.body(10.5, color: T.textFaint)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(c.text, style: AppTheme.body(12.5, color: T.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
