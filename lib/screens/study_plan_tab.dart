import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/source_curriculum_engine.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gemini_auth_dialog.dart';
import 'lesson_player_screen.dart';

class StudyPlanTab extends StatefulWidget {
  final AppController controller;
  const StudyPlanTab({super.key, required this.controller});

  @override
  State<StudyPlanTab> createState() => _StudyPlanTabState();
}

class _StudyPlanTabState extends State<StudyPlanTab> {
  void _snack(String msg, {bool err = false}) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? BatchColors.err : null),
    );
  }

  Future<void> _pickCourseMaterial({required bool useGemini}) async {
    final c = widget.controller;
    if (useGemini && !c.gemini.config.isSignedIn) {
      await showDialog(context: context, builder: (_) => GeminiAuthDialog(controller: c));
      return;
    }
    try {
      final msg = await c.pickAndIngestLearnKata(useGemini: useGemini);
      _snack(msg);
    } catch (e) {
      _snack('خطأ: $e', err: true);
    }
  }

  Future<void> _openPasteLectureDialog() async {
    final c = widget.controller;
    final titleCtrl = TextEditingController(text: 'محاضرة ${c.folder.sources.length + 1}');
    final textCtrl = TextEditingController();
    var useGemini = c.gemini.config.isSignedIn;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('📋 لصق نص محاضرة / ملخص'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المصدر / المحاضرة'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: textCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'الصق شرائح أو نقاط المحاضرة هنا لتوليد دروس مصغرة وأسئلة موثقة...',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useGemini,
                  title: Text(
                    c.gemini.config.isSignedIn ? 'استخدام ✨ Gemini AI' : 'توليد محلي فوري (بدون نت)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onChanged: (v) async {
                    if (v && !c.gemini.config.isSignedIn) {
                      await showDialog(context: ctx, builder: (_) => GeminiAuthDialog(controller: c));
                      setS(() => useGemini = c.gemini.config.isSignedIn);
                    } else {
                      setS(() => useGemini = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final raw = textCtrl.text.trim();
                if (raw.length < 25) {
                  _snack('النص قصير جداً — الصق فقرة أو نقاط واضحة.');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  final msg = await c.ingestLearnKataMaterial(
                    sourceName: titleCtrl.text.trim().isEmpty ? 'Notes' : titleCtrl.text.trim(),
                    rawText: raw,
                    fileType: 'pasted',
                    useGemini: useGemini,
                  );
                  _snack(msg);
                } catch (e) {
                  _snack('خطأ: $e', err: true);
                }
              },
              child: const Text('توليد الخطة 🎓'),
            ),
          ],
        ),
      ),
    );
  }

  void _launchLesson(MicroLesson lesson, {bool remediation = false}) {
    final c = widget.controller;
    if (!remediation && c.data.spLockMode && c.data.hearts <= 0) {
      _snack('انتهت قلوبك! اضغط على ❤️ بالأعلى لشحنها.', err: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPlayerScreen(
          controller: c,
          lesson: lesson,
          isTargetedRemediation: remediation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final folder = c.folder;
    final lessons = folder.lessons;
    final completedCount = lessons.where((l) => l.completed).length;
    final pathPct = lessons.isEmpty ? 0.0 : completedCount / lessons.length;
    final goalPct = min(1.0, c.data.dailyXp / max(1, c.data.dailyGoal));

    final weakTopics = folder.topicMastery.values.where((t) => t.level == 'weak').toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Top Duolingo/LearnKata Gamified Header
        Card(
          color: BatchColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🎓 مسار LearnKata: ${folder.name}',
                              style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                          Text(
                            lessons.isEmpty
                                ? 'ارفع محاضرتك لتوليد دروس مصغرة خطوة بخطوة'
                                : 'أنجزت $completedCount من ${lessons.length} درس (${(pathPct * 100).round()}%)',
                            style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    ActionChip(
                      backgroundColor: BatchColors.navy2,
                      label: Text('❤️ ${c.data.hearts}/5', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      onPressed: () {
                        c.data.hearts = 5;
                        c.save();
                        _snack('تم شحن القلوب (5 / 5 ❤️)!');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('🔥 ${c.data.streak} يوم', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    Text('⚡ ${c.data.xp} XP', style: const TextStyle(color: Color(0xFF5EEAD4), fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        c.data.spLockMode = !c.data.spLockMode;
                        c.save();
                      },
                      child: Text(c.data.spLockMode ? '🔒 وضع تدريجي' : '🔓 فتح حر',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: goalPct,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: Colors.white24,
                  color: BatchColors.gold,
                ),
                const SizedBox(height: 4),
                Text('هدف اليوم: ${c.data.dailyXp} / ${c.data.dailyGoal} XP',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              ],
            ),
          ),
        ),

        // Source-Grounded Material Ingestion Panel
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('📚 استيراد مادة وتوليد خطة موثقة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const Spacer(),
                    if (folder.sources.isNotEmpty)
                      Chip(
                        label: Text('${folder.sources.length} مصدر (${folder.allChunks.length} مقطع)',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: BatchColors.teal),
                      onPressed: () => _pickCourseMaterial(useGemini: false),
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('رفع PDF / PPTX / نص'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _openPasteLectureDialog,
                      icon: const Icon(Icons.content_paste_go_rounded, size: 18),
                      label: const Text('لصق ملاحظات / محاضرة'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickCourseMaterial(useGemini: true),
                      icon: const Text('✨'),
                      label: const Text('بناء بالذكاء الاصطناعي (Gemini)'),
                    ),
                  ],
                ),
                if (folder.sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: folder.sources
                          .map((s) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Chip(
                                  avatar: const Icon(Icons.description_outlined, size: 15, color: BatchColors.teal),
                                  label: Text('${s.name} (${s.chunks.length})', style: const TextStyle(fontSize: 11)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Targeted Weakness Remediation Callout
        if (weakTopics.isNotEmpty)
          Card(
            color: BatchColors.err.withOpacity(0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: BatchColors.err.withOpacity(0.5)),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: BatchColors.err,
                child: Text('🎯', style: TextStyle(fontSize: 18)),
              ),
              title: Text('رصدنا ${weakTopics.length} نقاط ضعف تحتاج مراجعة!',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: BatchColors.err, fontSize: 13.5)),
              subtitle: Text(
                weakTopics.take(3).map((w) => '${w.topic} (${w.masteryPct}%)').join(' • '),
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: BatchColors.err),
                onPressed: () {
                  final rem = SourceCurriculumEngine.buildTargetedWeaknessLesson(folder);
                  if (rem == null) {
                    _snack('أكمل بعض الأسئلة أو البطاقات في المواضيع الضعيفة لتوليد الجلسة.');
                    return;
                  }
                  _launchLesson(rem, remediation: true);
                },
                child: const Text('تقوية الآن'),
              ),
            ),
          ),

        // Empty State or Auto-Sync Raw MCQ Bank
        if (lessons.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Text('🗺️ خريطة التعلم التفاعلية فارغة بعد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text(
                    'ارفع ملف PDF أو باوربوينت PPTX أو الصق محتوى محاضرتك ليقوم LearnKata بتقسيمه تلقائياً إلى دروس مصغرة، أسئلة مع التعليل، فلاش كاردز، وألعاب تثبيت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  if (folder.questions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => c.ensureRoadmapSyncedFromQuestions(),
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: Text('تحويل ${folder.questions.length} سؤال في البنك إلى خطة دروس مصغرة'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          // Winding Duolingo-Style Micro-Lesson Roadmap
          ...lessons.asMap().entries.map((entry) {
            final i = entry.key;
            final l = entry.value;
            final prevDone = i == 0 || lessons[i - 1].completed;
            final unlocked = !c.data.spLockMode || l.completed || prevDone;
            final isActive = unlocked && !l.completed;
            final statusText = l.completed ? 'مكتمل ✅' : (unlocked ? 'نشط الآن ▶' : 'مقفل 🔒');
            final statusColor = l.completed ? BatchColors.ok : (unlocked ? BatchColors.teal : Colors.grey);

            // Slight alternating horizontal offset for visual winding roadmap feel
            final leftPad = (i % 3 == 1) ? 18.0 : (i % 3 == 2 ? 8.0 : 0.0);

            return Padding(
              padding: EdgeInsets.only(left: leftPad, right: leftPad == 18.0 ? 0 : (18.0 - leftPad)),
              child: Column(
                children: [
                  if (i > 0)
                    Container(
                      width: 3,
                      height: 16,
                      color: prevDone ? BatchColors.ok : Theme.of(context).dividerColor,
                    ),
                  Card(
                    elevation: isActive ? 3.5 : 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isActive ? BatchColors.teal : (l.completed ? BatchColors.ok.withOpacity(0.6) : Theme.of(context).dividerColor),
                        width: isActive ? 2.2 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: unlocked
                          ? () => _launchLesson(l)
                          : () => _snack('أكمل الدرس السابق (${lessons[i - 1].title}) أولاً لفتح هذا الدرس 🔒'),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: isActive ? [BoxShadow(color: BatchColors.teal.withOpacity(0.4), blurRadius: 10)] : null,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                l.completed ? Icons.check_rounded : (unlocked ? Icons.play_arrow_rounded : Icons.lock_rounded),
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text('درس ${i + 1} • $statusText',
                                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor)),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('⏱️ ${l.estimatedMinutes} د', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                                      if (l.stars > 0) ...[
                                        const Spacer(),
                                        Text('${'★' * l.stars}${'☆' * (3 - l.stars)}',
                                            style: const TextStyle(color: BatchColors.gold, fontSize: 12.5, fontWeight: FontWeight.w800)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(l.title,
                                      textDirection: detectTextDirection(l.title),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: unlocked ? null : BatchColors.mutedColor(context),
                                      )),
                                  const SizedBox(height: 3),
                                  Text(
                                    l.objective,
                                    textDirection: detectTextDirection(l.objective),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: BatchColors.mutedColor(context)),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '📄 ${l.sourceCitation}   •   ✅ ${l.quizzes.length} MCQ  |  🃏 ${l.flashcards.length}  |  🎮 ${l.matchPairs.length + l.fillBlanks.length}',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: BatchColors.teal),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 20),
      ],
    );
  }
}
