import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../services/mcq_parser.dart';
import '../services/native_bridge.dart';
import '../services/source_curriculum_engine.dart';
import '../services/storage_service.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/socratic_tutor_sheet.dart';
import 'lesson_player_screen.dart';

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
    final folder = c.folder;
    final topicsList = folder.topicMastery.values.toList()
      ..sort((a, b) => a.masteryPct.compareTo(b.masteryPct));

    final weakList = topicsList.where((t) => t.level == 'weak').toList();
    final devList = topicsList.where((t) => t.level == 'developing').toList();
    final strongList = topicsList.where((t) => t.level == 'strong').toList();

    final totalAtt = topicsList.fold<int>(0, (s, e) => s + e.totalAttempts);
    final totalCorr = topicsList.fold<int>(0, (s, e) => s + e.totalCorrect);
    final overallPct = totalAtt == 0 ? 0 : ((totalCorr / totalAtt) * 100).round();

    final qs = folder.questions.where((q) => !q.hasIssue && !q.isMultiAnswer).toList();
    final counts = [0, 0, 0, 0];
    for (final q in qs) {
      final a = q.getCorrectIndices().first;
      if (a >= 0 && a < 4) counts[a]++;
    }
    final total = max(1, counts.reduce((a, b) => a + b));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Strengths & Weaknesses Mastery Hero Dashboard
        Card(
          color: BatchColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🎯 لوحة الإتقان ونقاط الضعف',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('تحليل الدقة حسب الموضوع عبر MCQ والبطاقات والألعاب',
                              style: TextStyle(color: Color(0xFF99F6E4), fontSize: 11.5)),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: BatchColors.teal,
                      child: Text('$overallPct%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _kpiBadge('🔴 ضعيف', '${weakList.length}', BatchColors.err),
                    const SizedBox(width: 8),
                    _kpiBadge('🟡 قيد التطوير', '${devList.length}', BatchColors.warn),
                    const SizedBox(width: 8),
                    _kpiBadge('🟢 متقن', '${strongList.length}', BatchColors.ok),
                  ],
                ),
                if (weakList.isNotEmpty || topicsList.any((t) => t.masteryPct < 75)) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: BatchColors.err, padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      final rem = SourceCurriculumEngine.buildTargetedWeaknessLesson(folder);
                      if (rem == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('لا توجد أسئلة/بطاقات كافية للمراجعة بعد.')),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LessonPlayerScreen(
                            controller: c,
                            lesson: rem,
                            isTargetedRemediation: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('توليد وبدء جلسة تقوية تلقائية لنقاط الضعف ⚡', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Per-Topic Mastery Breakdown Cards
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('📚 خريطة المواضيع (${topicsList.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                if (topicsList.isEmpty)
                  const Text('ابدأ بحل الأسئلة أو بطاقات الاسترجاع ليتم تحليل نقاط قوتك وضعفك تلقائياً 📊',
                      style: TextStyle(fontSize: 13))
                else
                  ...topicsList.map((tm) {
                    final col = tm.level == 'strong'
                        ? BatchColors.ok
                        : (tm.level == 'developing' ? BatchColors.warn : BatchColors.err);
                    final label = tm.level == 'strong' ? 'قوة' : (tm.level == 'developing' ? 'متوسط' : 'نقطة ضعف');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: col.withOpacity(0.45)),
                        color: col.withOpacity(0.06),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(tm.topic, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(999)),
                                child: Text('${tm.masteryPct}% • $label',
                                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: tm.masteryPct / 100.0,
                            minHeight: 7,
                            borderRadius: BorderRadius.circular(99),
                            color: col,
                            backgroundColor: col.withOpacity(0.18),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                'MCQ: ${tm.mcqCorrect}/${tm.mcqAttempts}  •  بطاقات: ${tm.fcMastered}/${tm.fcReviews}  •  ألعاب: ${tm.gameCorrect}/${tm.gameAttempts}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                                onPressed: () => openSocraticTutorSheet(
                                  context,
                                  controller: c,
                                  initialQuestion: 'ساعدني على فهم موضوع "${tm.topic}" بطريقة سقراطية تدريجية لأنني أحتاج تقوية فيه',
                                ),
                                child: const Text('🧠 معلم', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                                onPressed: () {
                                  final rem = SourceCurriculumEngine.buildTargetedWeaknessLesson(folder, singleTopic: tm.topic);
                                  if (rem != null) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LessonPlayerScreen(
                                          controller: c,
                                          lesson: rem,
                                          isTargetedRemediation: true,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('🎯 تدرب', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: BatchColors.teal)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
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
                    final adj = McqParser.smartBalanceAnswers(folder.questions);
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

  Widget _kpiBadge(String label, String val, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: BatchColors.navy2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.withOpacity(0.7)),
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(color: col, fontSize: 17, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
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
                        final files = await NativeBridge.pickFiles(allowMultiple: false);
                        if (files.isEmpty) return;
                        final msg = await c.restoreBackupJson(utf8.decode(files.first.bytes));
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
