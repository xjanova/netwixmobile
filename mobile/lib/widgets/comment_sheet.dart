import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/member.dart';
import '../services/format.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import 'login_sheet.dart';

/// Comments for a title (netwix.online-backed, `/api/app/content/{id}/*`).
/// Reads are public; posting requires a signed-in member and echoes
/// optimistically, then reconciles with the stored comment.
void showCommentSheet(BuildContext context, int seriesId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentSheet(seriesId: seriesId),
  );
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.seriesId});
  final int seriesId;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();
  List<Comment> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await context.read<NetwixApi>().fetchComments(widget.seriesId);
    if (!mounted) return;
    setState(() {
      _comments = list;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Posting requires a member — prompt sign-in rather than echo a comment
    // the server will reject (401) and silently drop.
    final member = context.read<MemberState>();
    if (!member.isLoggedIn) {
      await showLoginSheet(context);
      if (!mounted || !context.read<MemberState>().isLoggedIn) return;
    }

    setState(() => _sending = true);
    final api = context.read<NetwixApi>();
    final me = context.read<MemberState>().member;

    // optimistic echo (stable id so we can swap in the stored comment)
    final optimistic = Comment(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      author: me?.name ?? 'ฉัน',
      text: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _comments = [optimistic, ..._comments];
      _controller.clear();
      _sending = false;
    });

    final saved = await api.postComment(widget.seriesId, text);
    if (!mounted) return;
    if (saved != null) {
      // Reconcile: replace the local echo with the server's stored comment.
      setState(() {
        _comments = [saved, ..._comments.where((x) => x.id != optimistic.id)];
      });
    }

    // Reward the comment (signed-in only, daily-capped server-side + locally).
    final got = await context.read<MemberState>().awardComment();
    if (mounted && got > 0) {
      final l = context.read<AppState>().l;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$got ${l.pick('เหรียญ', 'coins')} 🪙')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<AppState>().l;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: T.screen,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: T.hairlineStrong)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(l.bi('ความคิดเห็น', 'Comments'),
                      style: AppTheme.display(17, weight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_comments.length}', style: AppTheme.body(13, color: T.textMuted)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: T.accent))
                  : _comments.isEmpty
                      ? Center(
                          child: Text(l.pick('ยังไม่มีความคิดเห็น เป็นคนแรกเลย!', 'No comments yet — be first!'),
                              style: AppTheme.body(13, color: T.textMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) => _row(_comments[i], l),
                        ),
            ),
            _composer(l),
          ],
        ),
      ),
    );
  }

  Widget _row(Comment c, L10n l) {
    // Colour + initial tile, matching the web (comments never show a photo).
    final tint = HexAvatar.parseColor(c.avatarColor);
    final when = c.createdAt;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HexAvatar(
            size: 34,
            tint: tint,
            child: Center(
              child: Text(
                c.initial,
                style: AppTheme.display(14, weight: FontWeight.w700, color: T.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(12.5, weight: FontWeight.w700, color: T.textPrimary),
                      ),
                    ),
                    if (when != null) ...[
                      const SizedBox(width: 8),
                      Text(Format.ago(when, thai: l.isTh),
                          style: AppTheme.body(11, color: T.textFaint)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(c.text, style: AppTheme.body(13, color: T.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(L10n l) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
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
                  controller: _controller,
                  style: AppTheme.body(13.5, color: T.textPrimary),
                  cursorColor: T.accent,
                  minLines: 1,
                  maxLines: 4,
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
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(gradient: T.accentGradient, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: T.onAccent, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
