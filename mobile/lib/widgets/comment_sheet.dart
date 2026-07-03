import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/member.dart';
import '../services/netwix_client.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';

/// Comments for a series (netwix.online-backed). Ready now; the list is empty
/// until the backend is live, and posting echoes optimistically.
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
    final list = await context.read<NetwixClient>().comments(widget.seriesId);
    if (!mounted) return;
    setState(() {
      _comments = list ?? const [];
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final netwix = context.read<NetwixClient>();
    final me = context.read<MemberState>().member;

    // optimistic echo
    final optimistic = Comment(
      id: 'local-${_comments.length}',
      author: me?.name ?? 'ฉัน',
      text: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _comments = [optimistic, ..._comments];
      _controller.clear();
      _sending = false;
    });
    await netwix.postComment(widget.seriesId, text); // graceful until live

    // Reward the comment (signed-in only, daily-capped server-side + locally).
    if (!mounted) return;
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
                          itemBuilder: (_, i) => _row(_comments[i]),
                        ),
            ),
            _composer(l),
          ],
        ),
      ),
    );
  }

  Widget _row(Comment c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HexAvatar(size: 34, child: Icon(Icons.person, color: T.accentHi, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.author, style: AppTheme.body(12.5, weight: FontWeight.w700, color: T.textPrimary)),
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
