import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/gemini_oauth_service.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class GeminiAuthDialog extends StatefulWidget {
  final AppController controller;
  const GeminiAuthDialog({super.key, required this.controller});

  @override
  State<GeminiAuthDialog> createState() => _GeminiAuthDialogState();
}

class _GeminiAuthDialogState extends State<GeminiAuthDialog> {
  late final TextEditingController _clientCtrl;
  late final TextEditingController _projCtrl;
  late String _scopeMode;
  late String _model;
  bool _testing = false;
  String? _statusNote;

  @override
  void initState() {
    super.initState();
    final cfg = widget.controller.gemini.config;
    _clientCtrl = TextEditingController(text: cfg.clientId);
    _projCtrl = TextEditingController(text: cfg.projectId);
    _scopeMode = cfg.scopeMode;
    _model = cfg.model;
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _projCtrl.dispose();
    super.dispose();
  }

  void _copy(String val) {
    Clipboard.setData(ClipboardData(text: val));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم النسخ إلى الحافظة 📋'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _signIn() async {
    try {
      await widget.controller.gemini.startSignIn(
        clientId: _clientCtrl.text,
        projectId: _projCtrl.text,
        scopeMode: _scopeMode,
        model: _model,
      );
      if (mounted) {
        setState(() => _statusNote = 'تم فتح متصفح Google — أكمل تسجيل الدخول ثم ارجع للتطبيق.');
      }
    } catch (e) {
      if (mounted) setState(() => _statusNote = e.toString());
    }
  }

  Future<void> _testGemini() async {
    setState(() {
      _testing = true;
      _statusNote = '⏳ جاري اختبار الاتصال بـ Gemini...';
    });
    try {
      widget.controller.gemini.config.projectId = _projCtrl.text.trim();
      widget.controller.gemini.config.model = _model;
      await widget.controller.gemini.save();
      await widget.controller.gemini.callGeminiJson(
        'Reply with JSON {"ok":true,"status":"connected"}.',
        'ping',
      );
      widget.controller.playSound('correct');
      if (mounted) setState(() => _statusNote = '✅ الاتصال بـ Gemini عبر حساب Google يعمل بنجاح!');
    } catch (e) {
      if (mounted) setState(() => _statusNote = '❌ فشل الاختبار: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final cfg = widget.controller.gemini.config;
        return AlertDialog(
          title: const Text('✨ ربط Gemini بحساب Google', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (cfg.isSignedIn ? BatchColors.ok : BatchColors.teal).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (cfg.isSignedIn ? BatchColors.ok : BatchColors.teal).withOpacity(0.4)),
                  ),
                  child: Text(
                    cfg.isSignedIn
                        ? '✅ متصل بـ: ${cfg.userEmail.isNotEmpty ? cfg.userEmail : "حساب Google"}${cfg.refreshToken.isNotEmpty ? " (جلسة دائمة)" : ""}'
                        : 'غير مسجّل الدخول بحساب Google بعد — أدخل OAuth Client ID ثم اضغط تسجيل الدخول.',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('🔑 Google OAuth Client ID (Android)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: _clientCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: '1234567890-abc.apps.googleusercontent.com'),
                ),
                const SizedBox(height: 10),
                const Text('🏷️ Google Cloud Project ID (اختياري)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: _projCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'my-gemini-project-id'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _model,
                  decoration: const InputDecoration(labelText: 'نموذج Gemini'),
                  items: const [
                    DropdownMenuItem(value: 'gemini-2.5-flash', child: Text('gemini-2.5-flash (سريع وموصى به)')),
                    DropdownMenuItem(value: 'gemini-2.5-pro', child: Text('gemini-2.5-pro (أدق للشيتات الطويلة)')),
                  ],
                  onChanged: (v) => setState(() => _model = v ?? 'gemini-2.5-flash'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _scopeMode,
                  decoration: const InputDecoration(labelText: 'نطاق صلاحية OAuth'),
                  items: const [
                    DropdownMenuItem(value: 'gen', child: Text('generative-language (موصى به)')),
                    DropdownMenuItem(value: 'cloud', child: Text('cloud-platform')),
                  ],
                  onChanged: (v) => setState(() => _scopeMode = v ?? 'gen'),
                ),
                if (_statusNote != null) ...[
                  const SizedBox(height: 10),
                  Text(_statusNote!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _signIn,
                      icon: const Icon(Icons.login, size: 18),
                      label: Text(cfg.isSignedIn ? 'تبديل الحساب' : 'تسجيل الدخول بـ Google'),
                    ),
                    if (cfg.isSignedIn)
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testGemini,
                        icon: const Icon(Icons.bolt, size: 18),
                        label: const Text('اختبار Gemini'),
                      ),
                    if (cfg.isSignedIn)
                      TextButton.icon(
                        onPressed: () async {
                          await widget.controller.gemini.signOut();
                          widget.controller.notifyListeners();
                        },
                        icon: const Icon(Icons.logout, size: 18, color: BatchColors.err),
                        label: const Text('خروج', style: TextStyle(color: BatchColors.err)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('📋 بيانات الربط في Google Cloud Console', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                  children: [
                    _copyRow('Package', GeminiOAuthService.packageName),
                    _copyRow('SHA-1', GeminiOAuthService.certSha1),
                    _copyRow('Redirect URI', GeminiOAuthService.redirectUri),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://console.cloud.google.com/apis/credentials'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('فتح Google Cloud Credentials'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        );
      },
    );
  }

  Widget _copyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: SelectableText('$label: $value', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () => _copy(value),
            tooltip: 'نسخ',
          ),
        ],
      ),
    );
  }
}
