import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class QuizTab extends StatefulWidget {
  final AppController controller;
  const QuizTab({super.key, required this.controller});

  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
  String _mode = 'study'; // study | exam
  String _diff = 'all';
  String _topic = 'all';
  bool _shuffle = false;
  final _timerCtrl = TextEditingController(text: '0');

  bool _active = false;
  bool _finished = false;
  List<McqQuestion> _items = [];
  int _idx = 0;
  final Map<int, List<int>> _answers = {};
  final Set<int> _submitted = {};
  final Set<int> _flagged = {};
  String? _studyUnitKey;
  int _timerSec = 0;
  Timer? _timer;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _timer?.cancel();
    _timerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _checkPendingLaunch() {
    final c = widget.controller;
    if (c.pendingQuizItems != null) {
      final items = c.pendingQuizItems!;
      final unitKey = c.pendingQuizUnitKey;
      c.pendingQuizItems = null;
      c.pendingQuizUnitKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _launchQuiz(customItems: items, studyUnitKey: unitKey);
      });
    }
  }

  void _launchQuiz({List<McqQuestion>? customItems, String? studyUnitKey}) {
    final c = widget.controller;
    var items = customItems ??
        c.folder.questions.where((q) {
          if (q.hasIssue) return false;
          if (_diff != 'all' && q.difficulty != _diff) return false;
          if (_topic != 'all' && q.topic != _topic) return false;
          return true;
        }).toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أسئلة جاهزة مطابقة لاختيارك.')),
      );
      return;
    }

    // Keep clinical case questions grouped together
    final groups = <List<McqQuestion>>[];
    final gMap = <String, List<McqQuestion>>{};
    for (final q in items) {
      final key = q.caseId != null ? 'case:${q.caseId}' : 'q:${q.uid}';
      gMap.putIfAbsent(key, () {
        final g = <McqQuestion>[];
        groups.add(g);
        return g;
      }).add(q);
    }
    if (_shuffle) groups.shuffle(Random());
    items = groups.expand((g) => g).toList();

    _timer?.cancel();
    final mins = int.tryParse(_timerCtrl.text.trim()) ?? 0;
    setState(() {
      _active = true;
      _finished = false;
      _items = items;
      _idx = 0;
      _answers.clear();
      _submitted.clear();
      _flagged.clear();
      _studyUnitKey = studyUnitKey;
      _timerSec = mins > 0 ? mins * 60 : 0;
    });

    if (mins > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _timerSec--);
        if (_timerSec <= 0) _finishQuiz();
      });
    }
  }

  void _finishQuiz() {
    _timer?.cancel();
    final c = widget.controller;
    final now = DateTime.now().millisecondsSinceEpoch;
    var correct = 0;
    var wrong = 0;
    var skipped = 0;
    var attempted = 0;
    final wrongIds = <int>[];
    final byDiff = <String, List<int>>{'easy': [0, 0], 'medium': [0, 0], 'hard': [0, 0]};
    final byTopic = <String, List<int>>{};

    for (final q in _items) {
      final dKey = byDiff.containsKey(q.difficulty) ? q.difficulty : 'medium';
      byDiff[dKey]![1]++;
      byTopic.putIfAbsent(q.topic, () => [0, 0])[1]++;

      final ans = _answers[q.uid] ?? [];
      if (ans.isEmpty) {
        skipped++;
        wrongIds.add(q.uid);
      } else {
        attempted++;
        final ok = q.isUserAnswerCorrect(ans);
        q.recordOutcome(ok, now);
        if (ok) {
          correct++;
          byDiff[dKey]![0]++;
          byTopic[q.topic]![0]++;
        } else {
          wrong++;
          wrongIds.add(q.uid);
        }
      }
    }

    c.folder.lastWrongIds = wrongIds;
    final pct = _items.isEmpty ? 0 : ((correct / _items.length) * 100).round();

    if (attempted > 0) {
      c.data.syncDailyReset();
      final earnedXp = correct * 10 + (pct >= 60 ? 25 : 5);
      c.data.xp += earnedXp;
      c.data.dailyXp += earnedXp;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (c.data.lastStudyDay != today) {
        c.data.streak++;
        c.data.lastStudyDay = today;
      }
      if (_studyUnitKey != null) {
        if (wrong > 0 && c.data.spLockMode) {
          c.data.hearts = max(0, c.data.hearts - min(wrong, 2));
        }
        if (pct >= 70) c.data.hearts = min(5, c.data.hearts + 1);
        final stars = pct >= 90 ? 3 : (pct >= 70 ? 2 : (pct >= 50 ? 1 : 0));
        final prev = c.data.studyProgress[_studyUnitKey!] ?? StudyUnitProgress();
        c.data.studyProgress[_studyUnitKey!] = StudyUnitProgress(
          stars: max(prev.stars, stars),
          bestPct: max(prev.bestPct, pct),
          attempts: prev.attempts + 1,
        );
      }
      c.data.quizHistory.insert(
        0,
        QuizHistoryEntry(
          id: 'h_$now',
          ts: now,
          folderId: c.folder.id,
          folderName: c.folder.name,
          mode: _mode == 'study' ? 'تدريب' : 'امتحان',
          total: _items.length,
          attempted: attempted,
          correct: correct,
          wrong: wrong,
          skipped: skipped,
          pct: ((correct / max(1, attempted)) * 100).round(),
          byDiff: byDiff,
          byTopic: byTopic,
        ),
      );
      if (c.data.quizHistory.length > 200) {
        c.data.quizHistory = c.data.quizHistory.sublist(0, 200);
      }
    }

    c.playSound(pct >= 60 ? 'correct' : 'wrong');
    c.save();
    setState(() {
      _active = false;
      _finished = true;
    });
  }

  void _scrollTop() {
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 20) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkPendingLaunch();
    final c = widget.controller;
    final folder = c.folder;
    final topics = {'all', ...folder.questions.map((q) => q.topic)}.toList();
    if (!topics.contains(_topic)) _topic = 'all';

    if (_active && _items.isNotEmpty) {
      return _buildActiveQuiz(context);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('📝 إعداد الاختبار', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'وضع الحل'),
                  items: const [
                    DropdownMenuItem(value: 'study', child: Text('تدريب فوري (تصحيح + تعليل مباشر)')),
                    DropdownMenuItem(value: 'exam', child: Text('امتحان حقيقي (تصحيح في النهاية)')),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? 'study'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _diff,
                        decoration: const InputDecoration(labelText: 'الصعوبة'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('الكل')),
                          DropdownMenuItem(value: 'easy', child: Text('سهل')),
                          DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                          DropdownMenuItem(value: 'hard', child: Text('صعب')),
                        ],
                        onChanged: (v) => setState(() => _diff = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _topic,
                        decoration: const InputDecoration(labelText: 'الموضوع'),
                        items: topics
                            .map((t) => DropdownMenuItem(value: t, child: Text(t == 'all' ? 'كل المواضيع' : t, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _topic = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _timerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مؤقت الامتحان (بالدقائق — 0 بدون مؤقت)'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ترتيب عشوائي للأسئلة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  value: _shuffle,
                  onChanged: (v) => setState(() => _shuffle = v == true),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _launchQuiz(),
                      icon: const Icon(Icons.rocket_launch),
                      label: const Text('ابدأ الاختبار الآن'),
                    ),
                    if (folder.lastWrongIds.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          final wrongQs = folder.questions.where((q) => folder.lastWrongIds.contains(q.uid)).toList();
                          _launchQuiz(customItems: wrongQs);
                        },
                        icon: const Icon(Icons.replay),
                        label: Text('إعادة الأخطاء (${folder.lastWrongIds.length})'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_finished && _items.isNotEmpty) _buildResultCard(context),
      ],
    );
  }

  Widget _buildActiveQuiz(BuildContext context) {
    final c = widget.controller;
    final q = _items[_idx];
    final multi = q.isMultiAnswer;
    final expected = q.getCorrectIndices();
    final chosen = _answers[q.uid] ?? [];
    final isStudy = _mode == 'study';
    final showFeedback = isStudy && (multi ? _submitted.contains(q.uid) : chosen.isNotEmpty);
    final cObj = c.folder.caseById(q.caseId);
    final answeredCount = _items.where((it) => (_answers[it.uid] ?? []).isNotEmpty).length;

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('سؤال ${_idx + 1} من ${_items.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (_timerSec > 0)
                          Chip(
                            label: Text(
                              '⏱️ ${(_timerSec ~/ 60).toString().padLeft(2, '0')}:${(_timerSec % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            if (_flagged.contains(q.uid)) _flagged.remove(q.uid);
                            else _flagged.add(q.uid);
                          }),
                          child: Text(_flagged.contains(q.uid) ? '🚩 معلّم' : '🚩 مراجعة', style: const TextStyle(fontSize: 12)),
                        ),
                        FilledButton(
                          onPressed: _finishQuiz,
                          child: const Text('إنهاء وتصحيح', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: answeredCount / _items.length,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 12),
                if (cObj != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BatchColors.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BatchColors.gold),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🏥 ${cObj.title}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Directionality(
                          textDirection: detectTextDirection(cObj.vignette),
                          child: Text(cObj.vignette, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                Directionality(
                  textDirection: detectTextDirection(q.stem),
                  child: Text(q.stem, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                for (var oi = 0; oi < q.options.length; oi++) ...[
                  _buildOptionTile(q, oi, chosen, expected, showFeedback, multi),
                ],
                if (multi && isStudy && !showFeedback) ...[
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: chosen.isEmpty
                        ? null
                        : () {
                            setState(() => _submitted.add(q.uid));
                            c.playSound(q.isUserAnswerCorrect(chosen) ? 'correct' : 'wrong');
                          },
                    child: Text('✅ تحقق من الإجابات (${chosen.length})'),
                  ),
                ],
                // Inline feedback box — never overlaps navigation buttons
                if (showFeedback) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (q.isUserAnswerCorrect(chosen) ? BatchColors.ok : BatchColors.err).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: q.isUserAnswerCorrect(chosen) ? BatchColors.ok : BatchColors.err),
                    ),
                    child: Text(
                      q.isUserAnswerCorrect(chosen)
                          ? '✅ إجابة صحيحة! أحسنت.'
                          : '❌ إجابة خاطئة — الصحيح: ${expected.map((i) => kMcqLetters[i]).join(', ')}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: q.isUserAnswerCorrect(chosen) ? BatchColors.ok : BatchColors.err,
                      ),
                    ),
                  ),
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: BatchColors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('💡 التعليل: ${q.explanation}', style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: _idx > 0
                          ? () {
                              setState(() => _idx--);
                              _scrollTop();
                            }
                          : null,
                      child: const Text('⬅️ السابق'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (_idx < _items.length - 1) {
                          setState(() => _idx++);
                          _scrollTop();
                        } else {
                          _finishQuiz();
                        }
                      },
                      child: Text(_idx >= _items.length - 1 ? '📊 إنهاء وعرض النتيجة' : 'التالي ➡️'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      GestureDetector(
                        onTap: () {
                          setState(() => _idx = i);
                          _scrollTop();
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: _dotColor(_items[i], isStudy),
                            border: Border.all(
                              color: i == _idx ? BatchColors.gold : Colors.grey.shade400,
                              width: i == _idx ? 2.2 : 1,
                            ),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: _dotColor(_items[i], isStudy) != null ? Colors.white : null,
                            ),
                          ),
                        ),
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

  Color? _dotColor(McqQuestion item, bool isStudy) {
    final ans = _answers[item.uid] ?? [];
    final done = isStudy && (item.isMultiAnswer ? _submitted.contains(item.uid) : ans.isNotEmpty);
    if (done) return item.isUserAnswerCorrect(ans) ? BatchColors.ok : BatchColors.err;
    if (ans.isNotEmpty) return BatchColors.teal;
    return null;
  }

  Widget _buildOptionTile(McqQuestion q, int oi, List<int> chosen, List<int> expected, bool showFeedback, bool multi) {
    final isChosen = chosen.contains(oi);
    Color? bg;
    Color border = Theme.of(context).dividerColor;
    if (showFeedback) {
      if (expected.contains(oi)) {
        bg = BatchColors.ok.withOpacity(0.15);
        border = BatchColors.ok;
      } else if (isChosen) {
        bg = BatchColors.err.withOpacity(0.15);
        border = BatchColors.err;
      }
    } else if (isChosen) {
      bg = BatchColors.teal.withOpacity(0.14);
      border = BatchColors.teal;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (multi) {
          if (_mode == 'study' && _submitted.contains(q.uid)) return;
          final cur = [...(_answers[q.uid] ?? [])];
          if (cur.contains(oi)) cur.remove(oi);
          else cur.add(oi);
          cur.sort();
          setState(() => _answers[q.uid] = cur);
          widget.controller.playSound('flip');
        } else {
          if (_mode == 'study' && (_answers[q.uid] ?? []).isNotEmpty) return;
          setState(() => _answers[q.uid] = [oi]);
          if (_mode == 'study') {
            widget.controller.playSound(q.isUserAnswerCorrect([oi]) ? 'correct' : 'wrong');
          } else {
            widget.controller.playSound('flip');
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Directionality(
          textDirection: detectTextDirection(q.options[oi]),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: isChosen || (showFeedback && expected.contains(oi)) ? border : Colors.black12,
                child: Text(
                  kMcqLetters[oi],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: (isChosen || (showFeedback && expected.contains(oi))) ? Colors.white : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(q.options[oi], style: const TextStyle(fontSize: 14))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    final c = widget.controller;
    var correct = 0;
    for (final q in _items) {
      if (q.isUserAnswerCorrect(_answers[q.uid] ?? [])) correct++;
    }
    final pct = ((correct / _items.length) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: BatchColors.teal.withOpacity(0.14),
              child: Text('$pct%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: BatchColors.teal)),
            ),
            const SizedBox(height: 8),
            Text('النتيجة: $correct من ${_items.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (c.folder.lastWrongIds.isNotEmpty)
                  FilledButton.tonal(
                    onPressed: () {
                      final wrongQs = c.folder.questions.where((q) => c.folder.lastWrongIds.contains(q.uid)).toList();
                      final added = c.convertMcqsToFlashcards(wrongQs);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم تحويل $added سؤال خاطئ إلى فلاش كاردز 🃏')),
                      );
                    },
                    child: const Text('🃏 حوّل الأخطاء لفلاش كاردز'),
                  ),
                FilledButton(
                  onPressed: () => _launchQuiz(),
                  child: const Text('🔄 اختبار جديد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
