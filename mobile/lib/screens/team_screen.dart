import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/login_sheet.dart';

/// "My Team" — the member's affiliate downline: dividend earned + members per
/// level. Data from GET /api/app/team (server-authoritative).
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  Map<String, dynamic>? _team;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<MemberState>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final t = await context.read<NetwixApi>().fetchTeam();
    if (!mounted) return;
    setState(() {
      _team = t;
      _loading = false;
    });
  }

  Future<void> _share(String code) async {
    final l = context.read<AppState>().l;
    await SharePlus.instance.share(ShareParams(
      text: l.pick(
        'มาดูหนังฟรีกับ NetWix กับฉันสิ! ใช้โค้ด $code รับ Pro ฟรี 🎬\n${NetwixApi.referralUrl(code)}',
        'Join me on NetWix — free movies! Use code $code for free Pro 🎬\n${NetwixApi.referralUrl(code)}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final member = context.watch<MemberState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l.bi('ทีมของฉัน', 'My Team'), style: AppTheme.display(18, weight: FontWeight.w700)),
      ),
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: !member.isLoggedIn
            ? _loginPrompt(l)
            : _loading
                ? const Center(child: CircularProgressIndicator(color: T.accent))
                : _content(l),
      ),
    );
  }

  Widget _loginPrompt(L10n l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_rounded, size: 48, color: T.textFaint),
              const SizedBox(height: 14),
              Text(l.pick('เข้าสู่ระบบเพื่อดูสายงานของคุณ', 'Sign in to see your team'),
                  textAlign: TextAlign.center, style: AppTheme.body(14, color: T.textMuted)),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: AccentButton(
                  label: l.pick('เข้าสู่ระบบ', 'Sign in'),
                  height: 48,
                  onPressed: () async {
                    await showLoginSheet(context);
                    if (mounted) _load();
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _content(L10n l) {
    final t = _team;
    final code = (t?['referral_code'] ?? '').toString();
    final totalDividend = (t?['total_dividend'] as num?)?.toInt() ?? 0;
    final totalMembers = (t?['total_members'] as num?)?.toInt() ?? 0;
    final levels = (t?['levels'] is List) ? (t!['levels'] as List) : const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _hero(l, totalDividend, totalMembers, code),
        const SizedBox(height: 18),
        SectionHeader(title: l.bi('สายงานของฉัน', 'My downline')),
        const SizedBox(height: 8),
        if (totalMembers == 0)
          _empty(l, code)
        else
          for (final lv in levels)
            if (lv is Map) _levelCard(l, lv.cast<String, dynamic>()),
      ],
    );
  }

  Widget _hero(L10n l, int dividend, int members, String code) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: T.accentGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.pick('เหรียญปันผลรวมจากทีม', 'Total team dividend'),
              style: AppTheme.body(12.5, color: T.onAccent.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('$dividend', style: AppTheme.display(34, weight: FontWeight.w800, color: T.onAccent)),
            const SizedBox(width: 6),
            const Text('🪙', style: TextStyle(fontSize: 22)),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$members', style: AppTheme.display(22, weight: FontWeight.w800, color: T.onAccent)),
              Text(l.pick('ลูกทีม', 'members'),
                  style: AppTheme.body(11.5, color: T.onAccent.withValues(alpha: 0.85))),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.pick('โค้ดชวนเพื่อน', 'Your code'),
                    style: AppTheme.body(10.5, color: T.onAccent.withValues(alpha: 0.8))),
                Text(code.isEmpty ? '—' : code,
                    style: AppTheme.display(17, weight: FontWeight.w800, color: T.onAccent)),
              ]),
              const Spacer(),
              GestureDetector(
                onTap: code.isEmpty ? null : () => _share(code),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                      color: T.onAccent, borderRadius: BorderRadius.circular(100)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.ios_share_rounded, size: 16, color: T.accent),
                    const SizedBox(width: 6),
                    Text(l.pick('ชวนเพื่อน', 'Invite'),
                        style: AppTheme.body(12.5, weight: FontWeight.w700, color: T.accent)),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _empty(L10n l, String code) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: T.hairline),
        ),
        child: Column(children: [
          const Icon(Icons.person_add_alt_1_rounded, size: 40, color: T.accent),
          const SizedBox(height: 12),
          Text(l.pick('ยังไม่มีลูกทีม', 'No team members yet'),
              style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          Text(
            l.pick('ชวนเพื่อนด้วยโค้ด $code — เพื่อนได้ Pro ฟรี และคุณรับเหรียญปันผลจากทุกกิจกรรมของสายงาน',
                'Invite friends with code $code — they get free Pro and you earn dividend coins from your downline.'),
            textAlign: TextAlign.center,
            style: AppTheme.body(12.5, color: T.textMuted, height: 1.5),
          ),
        ]),
      );

  Widget _levelCard(L10n l, Map<String, dynamic> lv) {
    final level = (lv['level'] as num?)?.toInt() ?? 0;
    final pct = (lv['pct'] as num?)?.toDouble() ?? 0;
    final count = (lv['count'] as num?)?.toInt() ?? 0;
    final dividend = (lv['dividend'] as num?)?.toInt() ?? 0;
    final members = (lv['members'] is List) ? (lv['members'] as List) : const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: T.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: T.accentGradient, shape: BoxShape.circle),
              child: Text('$level', style: AppTheme.display(15, weight: FontWeight.w800, color: T.onAccent)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.pick('ชั้น $level', 'Level $level'),
                    style: AppTheme.body(14, weight: FontWeight.w700, color: T.textPrimary)),
                Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}% · $count ${l.pick('คน', 'members')}',
                    style: AppTheme.body(11.5, color: T.textMuted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('+$dividend', style: AppTheme.display(16, weight: FontWeight.w800, color: T.accent)),
              Text(l.pick('เหรียญ', 'coins'), style: AppTheme.body(10.5, color: T.textFaint)),
            ]),
          ]),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in members)
                  if (m is Map) _memberChip(m.cast<String, dynamic>()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberChip(Map<String, dynamic> m) {
    final name = (m['name'] ?? 'สมาชิก').toString();
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return SizedBox(
      width: 58,
      child: Column(children: [
        HexAvatar(
          size: 40,
          child: Center(
            child: Text(initial,
                style: AppTheme.display(16, weight: FontWeight.w800, color: T.accentHi)),
          ),
        ),
        const SizedBox(height: 5),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(10, color: T.textSecondary)),
      ]),
    );
  }
}
