import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class StudyPlanTab extends StatelessWidget {
  final AppController controller;
  const StudyPlanTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final folder = c.folder;
    final readyQs = folder.questions.where((q) => !q.hasIssue).toList();
    final chunkSize = c.data.spUnitSize > 0
        ? c.data.spUnitSize
        : (readyQs.length <= 24 ? 6 : (readyQs.length <= 60 ? 10 : 12));

    final units = <Map<String, dynamic>>[];
    for (var i = 0; i < readyQs.length; i += chunkSize) {
      final slice = readyQs.sublist(i, min(i + chunkSize, readyQs.length));
      final idx = units.length;
      units.add({
        'key': '${folder.id}_u_$idx',
        'title': 'الوحدة ${idx + 1} (${slice.length} سؤال)',
        'qs': slice,
      });
    }

    final goalPct = min(1.0, c.data.dailyXp / max(1, c.data.dailyGoal));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
                      child: Text('🎓 مسار: ${folder.name}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    ActionChip(
                      backgroundColor: BatchColors.navy2,
                      label: Text('❤️ ${c.data.hearts}/5', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      onPressed: () {
                        c.data.hearts = 5;
                        c.save();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم شحن القلوب (5 / 5 ❤️)!')),
                        );
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
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: goalPct,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: Colors.white24,
                  color: BatchColors.gold,
                ),
                const SizedBox(height: 4),
                Text('هدف اليوم: ${c.data.dailyXp} / ${c.data.dailyGoal} XP',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
        if (units.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('ارفع أسئلة أو شيت محاضرة أولاً وسيتكوّن مسار المذاكرة تلقائياً 📚',
                    textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          )
        else
          ...units.asMap().entries.map((entry) {
            final i = entry.key;
            final u = entry.value;
            final key = u['key'] as String;
            final qs = u['qs'] as List<McqQuestion>;
            final prog = c.data.studyProgress[key];
            final stars = prog?.stars ?? 0;
            final prevStars = i == 0 ? 1 : (c.data.studyProgress[units[i - 1]['key']]?.stars ?? 0);
            final unlocked = !c.data.spLockMode || i == 0 || prevStars >= 1;

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: unlocked ? BatchColors.teal : Colors.grey.shade400,
                  child: Icon(unlocked ? (stars > 0 ? Icons.star : Icons.play_arrow) : Icons.lock, color: Colors.white),
                ),
                title: Text(u['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  '${'★' * stars}${'☆' * (3 - stars)}  •  أفضل نتيجة: ${prog?.bestPct ?? 0}%',
                  style: const TextStyle(fontSize: 12.5, color: BatchColors.gold, fontWeight: FontWeight.w700),
                ),
                trailing: FilledButton(
                  onPressed: unlocked
                      ? () {
                          if (c.data.spLockMode && c.data.hearts <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('انتهت قلوبك! اضغط على ❤️ بالأعلى لشحنها.')),
                            );
                            return;
                          }
                          c.launchCustomQuiz(qs, studyUnitKey: key);
                        }
                      : null,
                  child: Text(unlocked ? 'ابدأ' : 'مغلق'),
                ),
              ),
            );
          }),
      ],
    );
  }
}
