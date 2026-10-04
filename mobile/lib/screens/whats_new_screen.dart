import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/update_sheet.dart';

/// 06 — Update · อัปเดตแอป. Shows the running version and a manual "check for
/// updates" that reuses the in-app OTA update flow (via netwix.online). Lists no
/// changes — customers aren't told what a release contains (owner's call).
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = 'v${p.version}');
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await maybePromptUpdate(context, manual: true);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l.bi('อัปเดตแอป', 'App update'), style: AppTheme.display(18, weight: FontWeight.w700)),
      ),
      body: DecoratedBox(
        decoration: T.screenBackground,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(child: Floating(child: const GemCrest(size: 76, icon: Icons.auto_awesome_rounded))),
            const SizedBox(height: 18),
            Center(child: Pill(text: _version.isEmpty ? '…' : _version)),
            const SizedBox(height: 34),
            _checking
                ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: T.accent)))
                : AccentButton(
                    label: l.bi('ตรวจหาการอัปเดต', 'Check for updates'),
                    icon: Icons.system_update_rounded,
                    onPressed: _check,
                  ),
          ],
        ),
      ),
    );
  }
}
