import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/profile.dart';
import '../services/netwix_api.dart';
import '../state/app_state.dart';
import '../state/catalog_state.dart';
import '../theme/app_theme.dart';
import '../theme/hex.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Profiles · โปรไฟล์ — switch profile and manage kids mode (the web's
/// `/profiles`).
///
/// Selecting binds the profile to this device's TOKEN server-side, so the adult
/// filter follows the choice and can't be undone by the client. After switching,
/// the catalogue is reloaded: a kids profile is served a different one.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  ProfileList? _list;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await context.read<NetwixApi>().fetchProfiles();
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  Future<void> _select(Profile p) async {
    if (_busy || p.id == _list?.activeId) return;
    setState(() => _busy = true);
    final ok = await context.read<NetwixApi>().selectProfile(p.id);
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok == null) {
      _toast(context.read<AppState>().l.pick('สลับโปรไฟล์ไม่สำเร็จ', 'Could not switch profile'));
      return;
    }
    await _load();
    if (!mounted) return;

    // A kids profile is served a different catalogue — drop what we cached for
    // the previous profile rather than showing it stale.
    await context.read<CatalogState>().load(force: true);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _edit({Profile? existing}) async {
    final l = context.read<AppState>().l;
    final res = await showModalBottomSheet<_ProfileDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileEditor(
        l: l,
        existing: existing,
        palette: _list?.palette ?? const [],
      ),
    );
    if (res == null || !mounted) return;

    setState(() => _busy = true);
    final api = context.read<NetwixApi>();
    final saved = existing == null
        ? await api.createProfile(
            name: res.name, avatarColor: res.color, isKids: res.isKids)
        : await api.updateProfile(existing.id,
            name: res.name, avatarColor: res.color, isKids: res.isKids);
    if (!mounted) return;
    setState(() => _busy = false);

    if (saved == null) {
      _toast(existing == null
          ? l.pick('สร้างโปรไฟล์ไม่สำเร็จ (สูงสุด ${_list?.max ?? 5} โปรไฟล์)',
              'Could not create profile (max ${_list?.max ?? 5})')
          : l.pick('บันทึกไม่สำเร็จ', 'Could not save'));
      return;
    }
    await _load();
  }

  Future<void> _delete(Profile p) async {
    final l = context.read<AppState>().l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: T.surface,
        title: Text(l.pick('ลบโปรไฟล์', 'Delete profile'),
            style: AppTheme.display(16, weight: FontWeight.w700)),
        content: Text(
          l.pick('ลบ "${p.name}" ถาวร? ประวัติการดูและรายการของโปรไฟล์นี้จะหายไปด้วย',
              'Permanently delete "${p.name}"? Its watch history and list go too.'),
          style: AppTheme.body(13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l.pick('ยกเลิก', 'Cancel'), style: AppTheme.body(13, color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l.pick('ลบ', 'Delete'), style: AppTheme.body(13, color: T.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final done = await context.read<NetwixApi>().deleteProfile(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) {
      _toast(l.pick('ลบไม่ได้ — ต้องมีอย่างน้อย 1 โปรไฟล์', 'Cannot delete — you need at least one'));
      return;
    }
    await _load();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final list = _list;

    return Scaffold(
      backgroundColor: T.screen,
      appBar: AppBar(
        backgroundColor: T.screen,
        elevation: 0,
        title: Text(l.bi('โปรไฟล์', 'Profiles'),
            style: AppTheme.display(17, weight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: T.accent))
          : list == null
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text(l.pick('โหลดไม่สำเร็จ · ลองใหม่', 'Failed to load · Retry'),
                        style: AppTheme.body(13, color: T.accent)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  children: [
                    Text(
                      l.pick('เลือกโปรไฟล์ที่จะใช้ดูบนเครื่องนี้',
                          'Choose the profile this device watches as'),
                      style: AppTheme.body(12.5, color: T.textMuted),
                    ),
                    const SizedBox(height: 14),
                    for (final p in list.items) _tile(p, list.activeId == p.id, l),
                    const SizedBox(height: 8),
                    if (list.canCreate)
                      GhostButton(
                        label: l.bi('+ สร้างโปรไฟล์', '+ Add profile'),
                        onPressed: _busy ? () {} : () => _edit(),
                      )
                    else
                      Text(
                        l.pick('ครบ ${list.max} โปรไฟล์แล้ว', 'You have all ${list.max} profiles'),
                        textAlign: TextAlign.center,
                        style: AppTheme.body(12, color: T.textFaint),
                      ),
                  ],
                ),
    );
  }

  Widget _tile(Profile p, bool active, L10n l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _select(p),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? T.accentSoft : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(T.rCard),
            border: Border.all(color: active ? T.accentGlow : T.hairline),
          ),
          child: Row(
            children: [
              HexAvatar(
                size: 44,
                tint: HexAvatar.parseColor(p.avatarColor),
                child: Center(
                  child: Text(p.initial,
                      style: AppTheme.display(17, weight: FontWeight.w700, color: T.textPrimary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(14.5,
                                weight: FontWeight.w700, color: T.textPrimary)),
                      ),
                      if (p.isKids) ...[
                        const SizedBox(width: 8),
                        Pill(text: l.pick('เด็ก', 'Kids'), filled: true, color: T.accent),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? l.pick('กำลังใช้อยู่', 'In use')
                          : (p.isKids
                              ? l.pick('ซ่อนหนัง 18+', 'Hides 18+ titles')
                              : l.pick('แตะเพื่อสลับ', 'Tap to switch')),
                      style: AppTheme.body(11.5, color: active ? T.accent : T.textFaint),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => _edit(existing: p),
                icon: const Icon(Icons.edit_rounded, size: 18, color: T.textMuted),
              ),
              IconButton(
                onPressed: _busy ? null : () => _delete(p),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: T.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the editor sheet returns.
class _ProfileDraft {
  const _ProfileDraft(this.name, this.color, this.isKids);
  final String name;
  final String? color;
  final bool isKids;
}

/// Create/edit sheet. A StatefulWidget, not a StatefulBuilder — the draft has to
/// survive rebuilds, and the controller needs disposing.
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.l, required this.palette, this.existing});

  final L10n l;
  final List<String> palette;
  final Profile? existing;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String? _color = widget.existing?.avatarColor ??
      (widget.palette.isNotEmpty ? widget.palette.first : null);
  late bool _kids = widget.existing?.isKids ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final canSave = _name.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        decoration: const BoxDecoration(
          color: T.screen,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: T.hairlineStrong)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? l.bi('สร้างโปรไฟล์', 'New profile')
                  : l.bi('แก้ไขโปรไฟล์', 'Edit profile'),
              style: AppTheme.display(17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              maxLength: 40, // server caps at 40
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              onChanged: (_) => setState(() {}),
              style: AppTheme.body(14, color: T.textPrimary),
              cursorColor: T.accent,
              decoration: InputDecoration(
                hintText: l.pick('ชื่อโปรไฟล์', 'Profile name'),
                hintStyle: AppTheme.body(13.5, color: T.textMuted),
                filled: true,
                fillColor: const Color(0x10FFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(T.rButton),
                  borderSide: const BorderSide(color: T.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(T.rButton),
                  borderSide: const BorderSide(color: T.hairline),
                ),
              ),
            ),
            if (widget.palette.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.pick('สี', 'Colour'), style: AppTheme.body(12, color: T.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final hex in widget.palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = hex),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: HexAvatar.parseColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == hex ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _kids = !_kids),
              child: Row(
                children: [
                  Icon(_kids ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 20, color: _kids ? T.accent : T.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.bi('โปรไฟล์เด็ก', 'Kids profile'),
                            style: AppTheme.body(13.5,
                                weight: FontWeight.w700, color: T.textPrimary)),
                        Text(l.pick('ซ่อนหนังเรต 18+/20+ ทั้งหมด', 'Hides all 18+/20+ titles'),
                            style: AppTheme.body(11.5, color: T.textFaint)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AccentButton(
              label: l.bi('บันทึก', 'Save'),
              icon: Icons.check_rounded,
              enabled: canSave,
              onPressed: () => Navigator.of(context)
                  .pop(_ProfileDraft(_name.text.trim(), _color, _kids)),
            ),
          ],
        ),
      ),
    );
  }
}
