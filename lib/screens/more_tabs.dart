import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../services/mcq_parser.dart';
import '../services/native_bridge.dart';
import '../services/storage_service.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class SheetGraderTab extends StatefulWidget {
  final AppController controller;
  const SheetGraderTab({super.key, required this.controller});

  @override
  State<SheetGraderTab> createState() => _SheetGraderTabState();
}

class _SheetGraderTabState extends State<SheetGraderTab> {
  final _keyCtrl = TextEditingController();
  final _studentCtrl = TextEditingController();
  String _report = '';

  @override
  void dispose() {
    _keyCtrl.dispose();
    _studentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('1️⃣ ربط مفتاح إجابات بالأسئلة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'مثال: 1- B 2- A 3- D أو B A D C'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final map = McqParser.parseAnswerSequence(_keyCtrl.text);
                    var updated = 0;
                    for (var i = 0; i < c.folder.questions.length; i++) {
                      final q = c.folder.questions[i];
                      final arr = (q.sourceNum > 0 && map.containsKey(q.sourceNum)) ? map[q.sourceNum]! : (map[i + 1] ?? []);
                      final clean = arr.where((x) => x < q.options.length).toList();
                      if (clean.isNotEmpty) {
                        q.setCorrectIndices(clean);
                        updated++;
                      }
                    }
                    c.save();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم ربط مفتاح الإجابة لـ $updated سؤال 🔗')),
                    );
                  },
                  child: const Text('🔗 ربط مفتاح الإجابات'),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('2️⃣ تصحيح إجاباتك دفعة واحدة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                TextField(
                  controller: _studentCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '1-B 2-A 3-C ...'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    final map = McqParser.parseAnswerSequence(_studentCtrl.text);
                    var graded = 0;
                    var correct = 0;
                    for (var i = 0; i < c.folder.questions.length; i++) {
                      final q = c.folder.questions[i];
                      if (q.hasIssue) continue;
                      final userArr = map[i + 1] ?? map[q.sourceNum] ?? [];
                      if (userArr.isEmpty) continue;
                      graded++;
                      final ok = q.isUserAnswerCorrect(userArr);
                      q.recordOutcome(ok);
                      if (ok) correct++;
                    }
                    c.save();
                    final pct = graded == 0 ? 0 : ((correct / graded) * 100).round();
                    setState(() => _report = 'تم تصحيح $graded سؤال — صحيح: $correct ✅ ($pct%)');
                  },
                  child: const Text('✅ تصحيح ورقة الإجابات'),
                ),
                if (_report.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(_report, style: const TextStyle(fontWeight: FontWeight.w800, color: BatchColors.teal)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AnalyticsTab extends StatelessWidget {
  final AppController controller;
  const AnalyticsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final qs = c.folder.questions.where((q) => !q.hasIssue && !q.isMultiAnswer).toList();
    final counts = [0, 0, 0, 0];
    for (final q in qs) {
      final a = q.getCorrectIndices().first;
      if (a >= 0 && a < 4) counts[a]++;
    }
    final total = max(1, counts.reduce((a, b) => a + b));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('⚖️ توازن مواضع الإجابات الصحيحة (A / B / C / D)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                for (var i = 0; i < 4; i++) ...[
                  Row(
                    children: [
                      SizedBox(width: 24, child: Text(kMcqLetters[i], style: const TextStyle(fontWeight: FontWeight.w800))),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: counts[i] / total,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${counts[i]}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                FilledButton(
                  onPressed: () {
                    final adj = McqParser.smartBalanceAnswers(c.folder.questions);
                    c.save();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم إعادة توزيع $adj سؤال بتوازن ذكي ⚖️')),
                    );
                  },
                  child: const Text('⚖️ إعادة توزيع متوازن للمجلد'),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('📈 سجل الاختبارات (${c.data.quizHistory.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                if (c.data.quizHistory.isEmpty)
                  const Text('لا توجد اختبارات مسجلة بعد.')
                else
                  ...c.data.quizHistory.take(15).map((h) => ListTile(
                        dense: true,
                        title: Text('${h.folderName} (${h.mode})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('صحيح: ${h.correct} / ${h.total}'),
                        trailing: Text('${h.pct}%', style: const TextStyle(fontWeight: FontWeight.w900, color: BatchColors.teal)),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ExportBackupTab extends StatefulWidget {
  final AppController controller;
  const ExportBackupTab({super.key, required this.controller});

  @override
  State<ExportBackupTab> createState() => _ExportBackupTabState();
}

class _ExportBackupTabState extends State<ExportBackupTab> {
  String _format = 'ruda';
  bool _validOnly = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preview = ExportService.buildExportText(c.folder, _format, validOnly: _validOnly);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('📤 التصدير وطباعة الامتحان', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _format,
                  decoration: const InputDecoration(labelText: 'صيغة التصدير'),
                  items: const [
                    DropdownMenuItem(value: 'ruda', child: Text('TXT — صيغة Ruda App')),
                    DropdownMenuItem(value: 'numbered', child: Text('TXT — أسئلة مرقمة')),
                    DropdownMenuItem(value: 'csv', child: Text('CSV — Excel')),
                    DropdownMenuItem(value: 'json', child: Text('JSON — مهيكلة')),
                  ],
                  onChanged: (v) => setState(() => _format = v ?? 'ruda'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الأسئلة السليمة فقط'),
                  value: _validOnly,
                  onChanged: (v) => setState(() => _validOnly = v == true),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        final ext = (_format == 'json' || _format == 'csv') ? _format : 'txt';
                        NativeBridge.saveFile('${c.folder.name}.$ext', preview);
                      },
                      icon: const Icon(Icons.save_alt),
                      label: const Text('حفظ الملف'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: preview));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ 📋')));
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        final html = ExportService.buildPrintableExamHtml(c.folder);
                        NativeBridge.printHtml(html, 'Batch27-${c.folder.name}');
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة / PDF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('💾 النسخة الاحتياطية الكاملة (JSON)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => NativeBridge.saveFile('Batch27-Backup.json', StorageService.buildBackupJson(c.data)),
                      child: const Text('📥 تنزيل نسخة احتياطية'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final res = await FilePicker.platform.pickFiles(
                          withData: true,
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
                        final msg = await c.restoreBackupJson(utf8.decode(res.files.first.bytes!));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                        }
                      },
                      child: const Text('♻️ استعادة نسخة احتياطية'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
