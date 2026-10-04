import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/netwix_api.dart';

/// The admin chooses when to use this device's connection. No background jobs for ordinary viewers.
class ResolveAssistScreen extends StatefulWidget {
  const ResolveAssistScreen({super.key});
  @override
  State<ResolveAssistScreen> createState() => _ResolveAssistScreenState();
}

class _ResolveAssistScreenState extends State<ResolveAssistScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String _message = '';
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{16}$').hasMatch(code)) {
      setState(() => _message = 'กรุณาวางรหัส 16 ตัวจากหลังบ้าน');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'กำลังขอลิงก์ผ่านเน็ตของอุปกรณ์นี้…';
    });
    final ok = await context.read<NetwixApi>().assistResolution(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok
          ? 'ส่งลิงก์กลับหลังบ้านแล้ว กลับไปกดเล่นได้เลย'
          : 'ขอลิงก์ไม่ได้ ตรวจว่าเข้าสู่ระบบด้วยบัญชีผู้ดูแลเดียวกับหลังบ้าน รหัสยังไม่หมดอายุ และเน็ตนี้เปิดต้นทางได้';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ช่วยหลังบ้านขอลิงก์')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'เข้าสู่ระบบด้วยบัญชีผู้ดูแลเดียวกับหลังบ้าน แล้ววางรหัสที่ได้จากปุ่ม “ขอผ่านอุปกรณ์” แอปจะขอเฉพาะตอนนั้นผ่านอินเทอร์เน็ตของอุปกรณ์นี้ และส่งผลกลับหลังบ้าน',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          maxLength: 16,
          decoration: const InputDecoration(labelText: 'รหัสงานจากหลังบ้าน'),
        ),
        FilledButton(
          onPressed: _busy ? null : _resolve,
          child: Text(_busy ? 'กำลังขอ…' : 'ขอลิงก์และส่งกลับ'),
        ),
        const SizedBox(height: 16),
        Text(_message),
      ],
    ),
  );
}
