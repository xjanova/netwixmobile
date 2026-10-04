import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/auto_updater.dart';
import '../services/update_info.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Checks netwix.online for a newer build and, if one exists, shows the update sheet.
/// [manual] = triggered by the user (so we surface an "up to date" toast and
/// don't honour a previously-skipped tag).
Future<void> maybePromptUpdate(BuildContext context, {bool manual = false}) async {
  final updater = context.read<AutoUpdater>();
  final app = context.read<AppState>();
  final l = app.l;

  final info = await updater.checkForUpdate();
  if (!context.mounted) return;

  if (info == null || !info.available) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.pick('เป็นเวอร์ชันล่าสุดแล้ว', "You're up to date")),
      ));
    }
    return;
  }

  if (!manual && app.settings.skippedUpdateTag == info.tag) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UpdateSheet(info: info, allowSkip: !manual),
  );
}

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info, this.allowSkip = true});
  final UpdateInfo info;
  final bool allowSkip;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  StreamSubscription<UpdateProgress>? _sub;
  UpdatePhase? _phase;
  int? _percent; // null until the first byte count arrives — the bar animates meanwhile
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startUpdate() {
    final updater = context.read<AutoUpdater>();
    _sub?.cancel(); // a retry after an error must not leave the old attempt's listener running
    setState(() {
      _phase = UpdatePhase.downloading;
      _percent = null;
      _error = null;
    });
    _sub = updater.downloadAndInstall(widget.info).listen((p) {
      if (!mounted) return;
      setState(() {
        _phase = p.phase;
        if (p.percent != null) _percent = p.percent!;
        _error = p.error;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<AppState>().l;
    final info = widget.info;
    final busy = _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: T.screen,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: T.hairlineStrong)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Floating(child: const GemCrest(size: 72, icon: Icons.arrow_downward_rounded))),
          const SizedBox(height: 16),
          // No release notes here — customers only learn that a new version exists.
          Text(l.bi('มีเวอร์ชันใหม่', 'Update available'),
              style: AppTheme.display(22, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Pill(text: info.latestLabel, filled: false),
            if (info.sizeLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(info.sizeLabel, style: AppTheme.body(12, color: T.textMuted)),
            ],
          ]),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!, style: AppTheme.body(13, color: const Color(0xFFF2705A))),
            const SizedBox(height: 12),
          ],
          if (_phase == UpdatePhase.done)
            Text(l.pick('กำลังเปิดตัวติดตั้ง…', 'Opening installer…'),
                style: AppTheme.body(13, color: T.textMuted))
          else if (busy)
            _ProgressRow(phase: _phase!, percent: _percent, l: l)
          else
            AccentButton(
              label: l.bi('อัปเดตเลย', 'Update now'),
              icon: Icons.download_rounded,
              onPressed: _startUpdate,
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!busy && _phase != UpdatePhase.done)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.bi('ภายหลัง', 'Later'),
                      style: AppTheme.body(13, color: T.textMuted)),
                ),
              if (widget.allowSkip && !busy && _phase != UpdatePhase.done) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    context.read<AppState>().settings.setSkippedUpdateTag(info.tag);
                    Navigator.of(context).pop();
                  },
                  child: Text(l.pick('ข้ามเวอร์ชันนี้', 'Skip this version'),
                      style: AppTheme.body(13, color: T.textFaint)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.phase, required this.percent, required this.l});
  final UpdatePhase phase;
  final int? percent; // null = not known yet → indeterminate bar, never a frozen 0%
  final L10n l;

  @override
  Widget build(BuildContext context) {
    final pct = percent;
    final label = phase == UpdatePhase.installing
        ? l.pick('กำลังติดตั้ง…', 'Installing…')
        : pct == null
            ? l.pick('กำลังดาวน์โหลด…', 'Downloading…')
            : l.pick('กำลังดาวน์โหลด $pct%', 'Downloading $pct%');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.body(13, color: T.textSecondary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: phase == UpdatePhase.installing || pct == null ? null : pct / 100,
            minHeight: 8,
            backgroundColor: T.hairlineStrong,
            valueColor: const AlwaysStoppedAnimation(T.accent),
          ),
        ),
      ],
    );
  }
}
