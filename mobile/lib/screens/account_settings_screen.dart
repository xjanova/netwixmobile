import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/member_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/icon3d.dart';

/// ตั้งค่าบัญชี — the same contact record the web edits on /account/settings, so a change on
/// either side shows up on the other. The login email is shown but never editable (as on the web).
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _form = GlobalKey<FormState>();

  AccountContact? _loaded;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final c = await context.read<MemberState>().fetchAccount();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadFailed = c == null;
      if (c != null) _fill(c);
    });
  }

  void _fill(AccountContact c) {
    _loaded = c;
    _name.text = c.name;
    _phone.text = c.phone ?? '';
    _address.text = c.address ?? '';
  }

  bool get _dirty {
    final c = _loaded;
    if (c == null) return false;
    return _name.text.trim() != c.name ||
        _phone.text.trim() != (c.phone ?? '') ||
        _address.text.trim() != (c.address ?? '');
  }

  Future<void> _save(L10n l) async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final saved = await context.read<MemberState>().saveAccount(
          name: _name.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved != null) _fill(saved);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved != null
          ? l.pick('บันทึกแล้ว · ข้อมูลบนเว็บอัปเดตด้วย', 'Saved · your web account is updated too')
          : l.pick('บันทึกไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง', 'Could not save — check your connection and try again')),
    ));
  }

  /// Leaving with unsaved edits would silently drop them — ask first.
  Future<bool> _confirmDiscard(L10n l) async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.screen,
        title: Text(l.pick('ยังไม่ได้บันทึก', 'Unsaved changes'), style: AppTheme.display(17, weight: FontWeight.w700)),
        content: Text(l.pick('ออกโดยไม่บันทึกการแก้ไข?', 'Leave without saving your edits?'),
            style: AppTheme.body(13, color: T.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.pick('แก้ต่อ', 'Keep editing'), style: AppTheme.body(13, color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.pick('ออก', 'Leave'), style: AppTheme.body(13, weight: FontWeight.w700, color: T.accent)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard(l) && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(l.bi('ข้อมูลบัญชี', 'Account details'), style: AppTheme.display(18, weight: FontWeight.w700)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: T.accent))
            : _loadFailed
                ? _failed(l)
                : _formBody(l),
      ),
    );
  }

  Widget _failed(L10n l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon3D(Ic3.account, size: 72, tile: false),
            const SizedBox(height: 12),
            Text(l.pick('โหลดข้อมูลบัญชีไม่ได้', 'Could not load your account'),
                style: AppTheme.body(14, weight: FontWeight.w600, color: T.textPrimary)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: Text(l.pick('ลองใหม่', 'Retry'), style: AppTheme.body(13, color: T.accent))),
          ]),
        ),
      );

  Widget _formBody(L10n l) {
    final c = _loaded!;
    return Form(
      key: _form,
      onChanged: () => setState(() {}),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: T.glass(radius: 20),
            child: Row(children: [
              const Icon3D(Ic3.account, size: 64, tile: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.pick('ข้อมูลเดียวกับบนเว็บ', 'Same details as on the web'),
                      style: AppTheme.body(14.5, weight: FontWeight.w700, color: T.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                      l.pick('แก้ที่แอปหรือที่ netwix.online ก็อัปเดตทั้งสองที่',
                          'Edit here or on netwix.online — both stay in sync'),
                      style: AppTheme.body(12, color: T.textMuted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _label(l.pick('อีเมล / บัญชีที่ใช้เข้าสู่ระบบ', 'Sign-in account')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: T.hairline),
            ),
            child: Row(children: [
              const Icon(Icons.lock_outline_rounded, size: 16, color: T.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.email ?? '${(c.provider ?? '').toUpperCase()} ${l.pick('(ไม่มีอีเมล)', '(no email)')}'.trim(),
                  style: AppTheme.body(13.5, color: T.textMuted),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _label(l.pick('ชื่อที่แสดง', 'Display name')),
          _field(
            controller: _name,
            hint: l.pick('ชื่อของคุณ', 'Your name'),
            maxLength: 255,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return l.pick('กรุณาใส่ชื่อ', 'Please enter a name');
              return null;
            },
          ),
          const SizedBox(height: 14),
          _label(l.pick('เบอร์โทร (ไม่บังคับ)', 'Phone (optional)')),
          _field(
            controller: _phone,
            hint: '08x-xxx-xxxx',
            maxLength: 32,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _label(l.pick('ที่อยู่ (ไม่บังคับ)', 'Address (optional)')),
          _field(
            controller: _address,
            hint: l.pick('ที่อยู่สำหรับติดต่อ / รับของรางวัล', 'Contact / prize delivery address'),
            maxLength: 500,
            maxLines: 3,
          ),
          const SizedBox(height: 22),
          Opacity(
            opacity: _dirty && !_saving ? 1 : 0.5,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(T.rButton),
                onTap: _dirty && !_saving ? () => _save(l) : null,
                child: Ink(
                  height: 52,
                  decoration: BoxDecoration(gradient: T.accentGradient, borderRadius: BorderRadius.circular(T.rButton)),
                  child: Center(
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l.pick('บันทึก', 'Save'),
                            style: AppTheme.display(15, weight: FontWeight.w700, color: T.onAccent)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(text, style: AppTheme.body(12.5, weight: FontWeight.w600, color: T.textSecondary)),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        enabled: !_saving,
        style: AppTheme.body(14, color: T.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.body(13.5, color: T.textFaint),
          counterText: '',
          filled: true,
          fillColor: const Color(0x14FFFFFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: T.hairline)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: T.hairline)),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: T.accent)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF6B81))),
        ),
      );
}
