import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/legal.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// In-app viewer for the legal documents (ข้อตกลงการใช้งาน / นโยบายความเป็นส่วนตัว).
///
/// This used to be a WebView pointed at netwix.online/terms. That page is the full website — its
/// footer alone carries 28 internal links (/movies, /series, /anime, every /genre/*, /login,
/// /register) and the WebView followed every one of them, so a single stray tap dropped the viewer
/// into the website inside the app, with no app navigation and no obvious way back
/// (owner, 2026-08-16: "ในแอพมันจะทำให้คนไปเล่นในหน้าเว็บแทน สับสนหมด").
///
/// It now fetches the same text the website renders — from the server's one copy, so the two can't
/// drift — and lays it out with the app's own typography. There is no page here to navigate away
/// from, which is a stronger guarantee than trying to filter links out of one.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.doc});

  /// 'terms' | 'privacy'
  final String doc;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  Future<LegalDoc?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // NetwixApi comes from the provider tree, so the first fetch waits for context to be ready.
    _future ??= context.read<NetwixApi>().fetchLegal(widget.doc);
  }

  void _retry() => setState(() {
        _future = context.read<NetwixApi>().fetchLegal(widget.doc);
      });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final fallbackTitle = widget.doc == 'privacy'
        ? l.pick('นโยบายความเป็นส่วนตัว', 'Privacy Policy')
        : l.pick('ข้อตกลงการใช้งาน', 'Terms of Service');

    return Scaffold(
      backgroundColor: T.screen,
      appBar: AppBar(
        backgroundColor: T.screen,
        title: Text(fallbackTitle, style: AppTheme.display(17, weight: FontWeight.w700)),
      ),
      body: FutureBuilder<LegalDoc?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: T.accent));
          }
          final doc = snap.data;
          if (doc == null || doc.blocks.isEmpty) {
            return _Retry(
              message: l.pick('โหลดเอกสารไม่สำเร็จ', 'Could not load this document'),
              action: l.pick('ลองใหม่', 'Retry'),
              onRetry: _retry,
            );
          }

          return SafeArea(
            top: false,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              // +1 for the "last updated" line that heads the document.
              itemCount: doc.blocks.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      l.pick('ปรับปรุงล่าสุด: ', 'Last updated: ') + doc.updated,
                      style: AppTheme.body(12, color: T.textInactive),
                    ),
                  );
                }

                return _block(doc.blocks[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _block(LegalBlock b) {
    switch (b.type) {
      case LegalBlockType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(b.text, style: AppTheme.display(16, weight: FontWeight.w700)),
        );
      case LegalBlockType.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 7, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 9),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(color: T.accent, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Text(b.text, style: AppTheme.body(13.5, color: T.textPrimary, height: 1.6)),
              ),
            ],
          ),
        );
      case LegalBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(b.text, style: AppTheme.body(13.5, color: T.textPrimary, height: 1.65)),
        );
    }
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.action, required this.onRetry});

  final String message;
  final String action;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTheme.body(13, color: T.textInactive)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(action)),
        ],
      ),
    );
  }
}
