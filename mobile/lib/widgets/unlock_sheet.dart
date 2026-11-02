import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/earn_coins_screen.dart';
import '../screens/go_pro_screen.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'login_sheet.dart';

/// Shown when a locked episode is tapped. Returns true if it got unlocked.
Future<bool> showUnlockSheet(
  BuildContext context, {
  required int seriesId,
  required int episode,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UnlockSheet(seriesId: seriesId, episode: episode),
  );
  return result ?? false;
}

class _UnlockSheet extends StatefulWidget {
  const _UnlockSheet({required this.seriesId, required this.episode});
  final int seriesId;
  final int episode;

  @override
  State<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<_UnlockSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();
    final cost = member.unlockCost;
    final enough = member.coins >= cost;

    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: 20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: T.screen,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: T.hairlineStrong)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HexIcon(icon: Icons.lock_rounded, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.pick('ปลดล็อกตอนที่', 'Unlock EP')} ${widget.episode}',
                        style: AppTheme.display(19, weight: FontWeight.w700)),
                    Text(l.pick('ดูฟรี ${member.freeEpisodes} ตอนแรกทุกเรื่อง', 'First ${member.freeEpisodes} episodes free'),
                        style: AppTheme.body(12, color: T.textMuted)),
                  ],
                ),
              ),
              Row(children: [
                const Icon(Icons.monetization_on_rounded, color: T.accent, size: 18),
                const SizedBox(width: 4),
                Text('${member.coins}',
                    style: AppTheme.display(16, weight: FontWeight.w700, color: T.accent)),
              ]),
            ],
          ),
          const SizedBox(height: 18),

          if (!member.isLoggedIn) ...[
            GestureDetector(
              onTap: _busy ? null : () => showLoginSheet(context),
              child: Container(
                height: 48,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(T.rButton),
                  border: Border.all(color: T.hairlineStrong),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.login_rounded, size: 18, color: T.accent),
                  const SizedBox(width: 8),
                  Text(l.pick('เข้าสู่ระบบรับ 10 เหรียญฟรี', 'Sign in for 10 free coins'),
                      style: AppTheme.body(13.5, weight: FontWeight.w600, color: T.textPrimary)),
                ]),
              ),
            ),
          ],

          AccentButton(
            label: '${l.pick('ปลดล็อกด้วย', 'Unlock for')} $cost ${l.pick('เหรียญ', 'coins')}',
            icon: Icons.lock_open_rounded,
            enabled: enough && !_busy,
            onPressed: () async {
              setState(() => _busy = true);
              final ok = await member.unlockEpisode(widget.seriesId, widget.episode);
              if (context.mounted) Navigator.of(context).pop(ok);
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(false);
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EarnCoinsScreen()));
                },
                icon: const Icon(Icons.bolt_rounded, size: 18, color: T.accent),
                label: Text(l.pick('หาเหรียญฟรี', 'Earn coins'),
                    style: AppTheme.body(13, color: T.accent)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoProScreen()));
                },
                child: Text(l.pick('สมัคร Pro ดูไม่จำกัด', 'Go Pro'),
                    style: AppTheme.body(13, color: T.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
