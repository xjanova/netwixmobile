import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/content.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/login_sheet.dart';
import '../widgets/poster_card.dart';

/// My List · รายการของฉัน — the member's saved titles (`GET /api/app/my-list`,
/// the web's `/my-list`).
///
/// The endpoint and `NetwixApi.fetchMyList()` already existed but nothing ever
/// called them: members could add titles from the detail screen and then had no
/// way to see the list.
class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  List<Content> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<MemberState>().isLoggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final items = await context.read<NetwixApi>().fetchMyList();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      backgroundColor: T.screen,
      appBar: AppBar(
        backgroundColor: T.screen,
        elevation: 0,
        title: Text(l.bi('รายการของฉัน', 'My List'),
            style: AppTheme.display(17, weight: FontWeight.w700)),
      ),
      body: !member.isLoggedIn
          ? _signedOut(l)
          : _loading
              ? const Center(child: CircularProgressIndicator(color: T.accent))
              : _items.isEmpty
                  ? _empty(l)
                  : RefreshIndicator(
                      color: T.accent,
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.5,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) =>
                            PortraitPosterCard(content: _items[i], width: double.infinity),
                      ),
                    ),
    );
  }

  Widget _signedOut(L10n l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_border_rounded, size: 44, color: T.textMuted),
              const SizedBox(height: 12),
              Text(
                l.pick('เข้าสู่ระบบเพื่อดูรายการที่บันทึกไว้', 'Sign in to see your saved titles'),
                textAlign: TextAlign.center,
                style: AppTheme.body(13, color: T.textMuted),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () async {
                  await showLoginSheet(context);
                  if (mounted) _load();
                },
                child: Text(l.pick('เข้าสู่ระบบ', 'Sign in'),
                    style: AppTheme.body(13.5, color: T.accent)),
              ),
            ],
          ),
        ),
      );

  Widget _empty(L10n l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_border_rounded, size: 44, color: T.textMuted),
              const SizedBox(height: 12),
              Text(
                l.pick('ยังไม่มีรายการที่บันทึกไว้', 'Nothing saved yet'),
                style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                l.pick('กด "+ รายการของฉัน" ที่หน้าเรื่องเพื่อเก็บไว้ดูทีหลัง',
                    'Tap "+ My List" on a title to save it for later'),
                textAlign: TextAlign.center,
                style: AppTheme.body(12.5, color: T.textMuted),
              ),
            ],
          ),
        ),
      );
}
