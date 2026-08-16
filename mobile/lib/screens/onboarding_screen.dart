import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart' show Floating;
import '../theme/tokens.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/netwix_wordmark.dart';
import '../widgets/common.dart';
import '../widgets/login_sheet.dart';
import 'app_shell.dart';

/// 01 — Onboarding · เริ่มต้นใช้งาน. First-run pitch + entry.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.l;

    return Scaffold(
      body: AmbientBackdrop(
        asset: 'assets/art/onboarding-bg.webp',
        // Light scrim only: this is the pitch screen, so the atmosphere is the point — the text
        // below it sits over the artwork's naturally dark lower half.
        scrim: 0.28,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // NetWix wordmark hero, with a soft crimson glow behind it
                Floating(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [T.accentSoftGlow, Colors.transparent],
                        radius: 0.9,
                      ),
                    ),
                    child: const NetwixWordmark(height: 54),
                  ),
                ),
                const Spacer(),
                _pager(),
                const SizedBox(height: 22),
                Text(
                  l.pick('ดูฟรีทุกเรื่อง\nไม่มีโฆษณากวนใจ', 'Watch everything free\nNo annoying ads'),
                  textAlign: TextAlign.center,
                  style: AppTheme.display(25, weight: FontWeight.w700, letterSpacing: -0.02),
                ),
                const SizedBox(height: 10),
                Text(l.pick('ซีรีส์ · หนัง · แนวตั้ง — ดูฟรี', 'Series · Movies · Shorts — free'),
                    textAlign: TextAlign.center,
                    style: AppTheme.body(13, weight: FontWeight.w600, color: T.accent)),
                const SizedBox(height: 12),
                Text(
                  l.pick(
                    'ดูฟรีทุกเรื่อง ทุกประเภท · ไม่ต้องหยอดเหรียญ\nสมัคร Pro เพียง 129฿/เดือน เพื่อรับชมแบบไม่มีโฆษณา',
                    'Everything free · no coins per episode\nGo Pro for just 129฿/month to watch ad-free',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTheme.body(12.5, color: T.textMuted),
                ),
                const Spacer(flex: 2),
                AccentButton(
                  label: l.bi('เริ่มเลย', 'Get Started'),
                  onPressed: () async {
                    await app.completeOnboarding();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AppShell()),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                GhostButton(
                  label: l.bi('เข้าสู่ระบบ', 'Sign in'),
                  onPressed: () => showLoginSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _dot(true),
          _dot(false),
          _dot(false),
        ],
      );

  Widget _dot(bool active) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: active ? 22 : 7,
        height: 7,
        decoration: BoxDecoration(
          color: active ? T.accent : T.hairlineStrong,
          borderRadius: BorderRadius.circular(100),
        ),
      );
}
