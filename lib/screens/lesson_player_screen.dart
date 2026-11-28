import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/socratic_tutor_sheet.dart';

class LessonPlayerScreen extends StatefulWidget {
  final AppController controller;
  final MicroLesson lesson;
  final bool isTargetedRemediation;

  const LessonPlayerScreen({
    super.key,
    required this.controller,
    required this.lesson,
    this.isTargetedRemediation = false,
  });

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  // 0: Concept Summary | 1: Concept Check MCQs | 2: Active Recall Flashcards | 3: Quick Review Game
  int _stage = 0;

  // Stage 1 MCQ state
  int _qIdx = 0;
  int? _selectedOpt;
  bool _submittedOpt = false;
  int _mcqCorrectCount = 0;
  int _mcqAttemptCount = 0;

  // Stage 2 Flashcards state
  int _fcIdx = 0;
  bool _fcFlipped = false;
  bool _fcPracticed = false;

  // Stage 3 Game state (Matching + Fill in Blank)
  late List<MatchPairItem> _pairs;
  late List<MatchPairItem> _shuffledRights;
  int? _selLeftIdx;
  final Set<String> _matchedPairIds = {};
  bool _matchErrorFlash = false;

  late List<FillBlankItem> _blanks;
  int _blankIdx = 0;
  String? _blankChosen;
  bool _blankChecked = false;
  int _gameCorrect = 0;
  int _gameAttempts = 0;

  bool _showExcerpt = false;

  @override
  void initState() {
    super.initState();
    _pairs = [...widget.lesson.matchPairs];
    _shuffledRights = [..._pairs]..shuffle(Random());
    _blanks = [...widget.lesson.fillBlanks];
  }

  bool get _hasMcq => widget.lesson.quizzes.isNotEmpty;
  bool get _hasFc => widget.lesson.flashcards.isNotEmpty;
  bool get _hasGame => _pairs.isNotEmpty || _blanks.isNotEmpty;

  void _nextStage() {
    if (_stage == 0) {
      if (_hasMcq) {
        setState(() => _stage = 1);
      } else if (_hasFc) {
        setState(() => _stage = 2);
      } else if (_hasGame) {
        setState(() => _stage = 3);
      } else {
        _finishLesson();
      }
      return;
    }
    if (_stage == 1) {
      if (_hasFc) {
        setState(() => _stage = 2);
      } else if (_hasGame) {
        setState(() => _stage = 3);
      } else {
        _finishLesson();
      }
      return;
    }
    if (_stage == 2) {
      if (_hasGame) {
        setState(() => _stage = 3);
      } else {
        _finishLesson();
      }
      return;
    }
    _finishLesson();
  }

  Future<void> _finishLesson() async {
    final pct = _mcqAttemptCount > 0 ? ((_mcqCorrectCount / _mcqAttemptCount) * 100).round() : 100;
    if (!widget.isTargetedRemediation) {
      await widget.controller.completeMicroLesson(
        widget.lesson,
        quizPct: pct,
        didFlashcards: _fcPracticed || !_hasFc,
        didGame: _hasGame,
      );
    } else {
      widget.controller.data.xp += 30;
      widget.controller.data.dailyXp += 30;
      await widget.controller.save();
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isTargetedRemediation ? '🎯 أتممت جلسة التقوية!' : '🏆 تم إتقان الدرس المصغّر!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.lesson.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('دقة أسئلة التحقق: $pct%', style: const TextStyle(fontWeight: FontWeight.w800, color: BatchColors.teal)),
            if (_gameAttempts > 0)
              Text('دقة لعبة المراجعة: ${((_gameCorrect / _gameAttempts) * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('تم فتح الدرس التالي في خطتك وتحديث نقاط القوة والضعف ✨',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('متابعة المسار'),
          ),
        ],
      ),
    );
  }

  void _openTutorForWrongMcq(McqQuestion q, int chosenIdx) {
    final wrongCtx =
        'Question: "${q.stem}". Student selected "${q.options[chosenIdx]}" (INCORRECT). Correct concept area: ${q.topic} [${q.sourceCitation}]. Guide student step-by-step WITHOUT immediately spoiling the letter!';
    openSocraticTutorSheet(
      context,
      controller: widget.controller,
      activeLesson: widget.lesson,
      wrongContext: wrongCtx,
      initialQuestion: 'أخطأت في هذا السؤال، أرشدني خطوة بخطوة لأفهم السبب دون كشف الجواب مباشرة!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = ['المفهوم', 'التحقق', 'البطاقات', 'التثبيت'];
    final wide = MediaQuery.of(context).size.width >= 900;

    final body = Column(
      children: [
        // Calm Stepper Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5))),
          ),
          child: Row(
            children: List.generate(stages.length, (i) {
              final active = i == _stage;
              final done = i < _stage;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _stage = i),
                  child: Column(
                    children: [
                      Container(
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: done
                              ? BatchColors.ok
                              : (active ? BatchColors.teal : Theme.of(context).dividerColor.withOpacity(0.4)),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        stages[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: active || done ? FontWeight.w800 : FontWeight.w500,
                          color: active ? BatchColors.teal : (done ? BatchColors.ok : null),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: switch (_stage) {
            0 => _buildConceptStage(),
            1 => _buildMcqStage(),
            2 => _buildFlashcardStage(),
            _ => _buildGameStage(),
          },
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BatchColors.navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.lesson.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('⏱️ ${widget.lesson.estimatedMinutes} دقيقة  •  📄 ${widget.lesson.sourceCitation}',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF99F6E4)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (!wide)
            TextButton.icon(
              onPressed: () => openSocraticTutorSheet(context, controller: widget.controller, activeLesson: widget.lesson),
              icon: const Text('🧠', style: TextStyle(fontSize: 16)),
              label: const Text('المعلم', style: TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                Expanded(flex: 3, child: body),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: SocraticTutorPanel(controller: widget.controller, activeLesson: widget.lesson)),
              ],
            )
          : body,
    );
  }

  // ---------------------------------------------------------------------------
  // STAGE 0: CALM DISTRACTION-FREE CONCEPT SUMMARY + GROUNDED SOURCE CITATION
  // ---------------------------------------------------------------------------
  Widget _buildConceptStage() {
    final l = widget.lesson;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Learning Objective Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BatchColors.teal.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BatchColors.teal.withOpacity(0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎯 هدف التعلم (Learning Objective)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: BatchColors.teal)),
              const SizedBox(height: 6),
              Text(
                l.objective,
                textDirection: detectTextDirection(l.objective),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Key Concepts Calm Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('📖 خلاصة المفاهيم الأساسية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const Spacer(),
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 14, color: BatchColors.navy),
                      label: Text('${l.estimatedMinutes} min', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  l.summary,
                  textDirection: detectTextDirection(l.summary),
                  style: const TextStyle(fontSize: 14.5, height: 1.6),
                ),
                if (l.keyTakeaways.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('✨ نقاط التركيز الحاسمة:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: BatchColors.teal)),
                  const SizedBox(height: 6),
                  ...l.keyTakeaways.map((k) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: BatchColors.teal, fontWeight: FontWeight.w900, fontSize: 16)),
                            Expanded(
                              child: Text(k, textDirection: detectTextDirection(k), style: const TextStyle(fontSize: 13.5, height: 1.45)),
                            ),
                          ],
                        ),
                      )),
                ],
                const Divider(height: 22),
                InkWell(
                  onTap: () => setState(() => _showExcerpt = !_showExcerpt),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 18, color: BatchColors.teal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('المرجع الموثق: ${l.sourceCitation}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: BatchColors.teal)),
                      ),
                      Icon(_showExcerpt ? Icons.expand_less : Icons.expand_more, size: 18),
                    ],
                  ),
                ),
                if (_showExcerpt && l.sourceExcerpt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(l.sourceExcerpt, textDirection: detectTextDirection(l.sourceExcerpt), style: const TextStyle(fontSize: 12, height: 1.45)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => openSocraticTutorSheet(
            context,
            controller: widget.controller,
            activeLesson: l,
            initialQuestion: 'لخص لي هذا الدرس بتشبيه مبسط واسألني سؤال فهم سريع من المصدر',
          ),
          icon: const Text('🧠', style: TextStyle(fontSize: 17)),
          label: const Text('ناقش الفكرة مع المعلم السقراطي'),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: BatchColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _nextStage,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('انتقل للتطبيق النشط (تحقق الفهم) ➔', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STAGE 1: CONCEPT CHECK MCQs (PER-OPTION FEEDBACK + SOCRATIC HINT)
  // ---------------------------------------------------------------------------
  Widget _buildMcqStage() {
    final qs = widget.lesson.quizzes;
    if (qs.isEmpty) {
      return Center(child: FilledButton(onPressed: _nextStage, child: const Text('لا توجد أسئلة — انتقل للتالي')));
    }
    final q = qs[_qIdx];
    final correctIndices = q.getCorrectIndices();
    final isChosenRight = _submittedOpt && _selectedOpt != null && correctIndices.contains(_selectedOpt);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Chip(label: Text('سؤال ${_qIdx + 1} / ${qs.length}', style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                q.sourceCitation.isNotEmpty ? '📄 ${q.sourceCitation}' : widget.lesson.sourceCitation,
                style: const TextStyle(fontSize: 11.5, color: BatchColors.teal, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(q.stem, textDirection: detectTextDirection(q.stem), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.5)),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(q.options.length, (i) {
          final isSelected = _selectedOpt == i;
          final isRightOpt = correctIndices.contains(i);
          Color? bg;
          Color borderCol = Theme.of(context).dividerColor;
          if (_submittedOpt) {
            if (isRightOpt) {
              bg = BatchColors.ok.withOpacity(0.14);
              borderCol = BatchColors.ok;
            } else if (isSelected && !isRightOpt) {
              bg = BatchColors.err.withOpacity(0.14);
              borderCol = BatchColors.err;
            }
          } else if (isSelected) {
            bg = BatchColors.teal.withOpacity(0.12);
            borderCol = BatchColors.teal;
          }

          return GestureDetector(
            onTap: _submittedOpt
                ? null
                : () {
                    setState(() {
                      _selectedOpt = i;
                      _submittedOpt = true;
                      _mcqAttemptCount++;
                      if (correctIndices.contains(i)) {
                        _mcqCorrectCount++;
                        widget.controller.playSound('correct');
                        widget.controller.recordTopicAttempt(q.topic, isCorrect: true, citation: q.sourceCitation);
                      } else {
                        widget.controller.playSound('wrong');
                        widget.controller.recordTopicAttempt(q.topic, isCorrect: false, citation: q.sourceCitation);
                      }
                    });
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: bg ?? Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderCol, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: _submittedOpt && isRightOpt
                            ? BatchColors.ok
                            : (_submittedOpt && isSelected ? BatchColors.err : BatchColors.navy),
                        child: Text(kMcqLetters[i], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(q.options[i], textDirection: detectTextDirection(q.options[i]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (_submittedOpt && i < q.optionRationales.length && q.optionRationales[i].isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      q.optionRationales[i],
                      textDirection: detectTextDirection(q.optionRationales[i]),
                      style: TextStyle(fontSize: 12, color: isRightOpt ? BatchColors.ok : BatchColors.mutedColor(context), fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        if (_submittedOpt) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isChosenRight ? BatchColors.ok : BatchColors.warn).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isChosenRight ? BatchColors.ok : BatchColors.warn),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isChosenRight ? '✅ إجابة صحيحة! استيعاب ممتاز' : '💡 تعثرت في هذه النقطة — راجع التفسير أو اطلب تلميحاً',
                  style: TextStyle(fontWeight: FontWeight.w800, color: isChosenRight ? BatchColors.ok : BatchColors.warn),
                ),
                if (q.explanation.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(q.explanation, textDirection: detectTextDirection(q.explanation), style: const TextStyle(fontSize: 13, height: 1.45)),
                ],
                if (!isChosenRight && _selectedOpt != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openTutorForWrongMcq(q, _selectedOpt!),
                    icon: const Text('🧠'),
                    label: const Text('اشرح لي سقراطياً لماذا أخطأت دون حرق الفكرة'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BatchColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () {
              if (_qIdx + 1 < qs.length) {
                setState(() {
                  _qIdx++;
                  _selectedOpt = null;
                  _submittedOpt = false;
                });
              } else {
                _nextStage();
              }
            },
            child: Text(_qIdx + 1 < qs.length ? 'السؤال التالي ➔' : 'متابعة إلى بطاقات الاسترجاع ➔', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STAGE 2: ACTIVE RECALL FLASHCARDS
  // ---------------------------------------------------------------------------
  Widget _buildFlashcardStage() {
    final fcs = widget.lesson.flashcards;
    if (fcs.isEmpty) {
      return Center(child: FilledButton(onPressed: _nextStage, child: const Text('انتقل للعبة التثبيت ➔')));
    }
    final fc = fcs[_fcIdx];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Chip(label: Text('بطاقة ${_fcIdx + 1} / ${fcs.length}', style: const TextStyle(fontWeight: FontWeight.w800))),
              const Spacer(),
              Text('📄 ${fc.sourceCitation.isNotEmpty ? fc.sourceCitation : widget.lesson.sourceCitation}',
                  style: const TextStyle(fontSize: 11.5, color: BatchColors.teal, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _fcFlipped = !_fcFlipped),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Container(
                  key: ValueKey('${fc.uid}_$_fcFlipped'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _fcFlipped ? BatchColors.navy : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: BatchColors.teal, width: 2),
                    boxShadow: [BoxShadow(color: BatchColors.teal.withOpacity(0.14), blurRadius: 14)],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _fcFlipped ? '💡 الإجابة / الآلية' : '🧠 استرجع من ذاكرتك (اضغط للقلب)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _fcFlipped ? const Color(0xFF5EEAD4) : BatchColors.teal),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _fcFlipped ? fc.back : fc.front,
                        textAlign: TextAlign.center,
                        textDirection: detectTextDirection(_fcFlipped ? fc.back : fc.front),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.5, color: _fcFlipped ? Colors.white : null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!_fcFlipped)
            FilledButton.tonal(
              onPressed: () => setState(() => _fcFlipped = true),
              child: const Text('اكشف الإجابة 👁️'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: BatchColors.err),
                    onPressed: () {
                      widget.controller.recordTopicAttempt(fc.topic, isCorrect: false, isFlashcard: true, citation: fc.sourceCitation);
                      _advanceFc();
                    },
                    child: const Text('❌ نسيتها (تحتاج تقوية)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: BatchColors.ok),
                    onPressed: () {
                      widget.controller.recordTopicAttempt(fc.topic, isCorrect: true, isFlashcard: true, citation: fc.sourceCitation);
                      _advanceFc();
                    },
                    child: const Text('✅ تذكرتها بإتقان'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _advanceFc() {
    _fcPracticed = true;
    if (_fcIdx + 1 < widget.lesson.flashcards.length) {
      setState(() {
        _fcIdx++;
        _fcFlipped = false;
      });
    } else {
      _nextStage();
    }
  }

  // ---------------------------------------------------------------------------
  // STAGE 3: QUICK REVIEW GAME (MATCHING PAIRS + FILL IN THE BLANK)
  // ---------------------------------------------------------------------------
  Widget _buildGameStage() {
    final matchingDone = _matchedPairIds.length >= _pairs.length;
    if (!matchingDone && _pairs.isNotEmpty) {
      return _buildMatchingGame();
    }
    if (_blanks.isNotEmpty && _blankIdx < _blanks.length) {
      return _buildFillBlankGame();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: BatchColors.ok, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
          onPressed: _finishLesson,
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('إتمام الدرس وفتح التالي 🎉', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildMatchingGame() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: BatchColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('🎮 لعبة المطابقة السريعة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                Text('${_matchedPairIds.length} / ${_pairs.length}',
                    style: const TextStyle(color: Color(0xFF5EEAD4), fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        if (_matchErrorFlash)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('❌ ليست مطابقة صحيحة — فكر في الآلية وحاول مجدداً',
                textAlign: TextAlign.center, style: TextStyle(color: BatchColors.err, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Terms
            Expanded(
              child: Column(
                children: List.generate(_pairs.length, (i) {
                  final p = _pairs[i];
                  final matched = _matchedPairIds.contains(p.id);
                  final selected = _selLeftIdx == i;
                  return GestureDetector(
                    onTap: matched ? null : () => setState(() => _selLeftIdx = i),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: matched
                            ? BatchColors.ok.withOpacity(0.15)
                            : (selected ? BatchColors.teal : Theme.of(context).cardColor),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: matched ? BatchColors.ok : (selected ? BatchColors.navy : Theme.of(context).dividerColor), width: 1.5),
                      ),
                      child: Text(
                        p.left,
                        textDirection: detectTextDirection(p.left),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : null),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 10),
            // Right Definitions
            Expanded(
              child: Column(
                children: _shuffledRights.map((rp) {
                  final matched = _matchedPairIds.contains(rp.id);
                  return GestureDetector(
                    onTap: matched || _selLeftIdx == null
                        ? null
                        : () {
                            final leftItem = _pairs[_selLeftIdx!];
                            _gameAttempts++;
                            if (leftItem.id == rp.id) {
                              _gameCorrect++;
                              widget.controller.playSound('correct');
                              widget.controller.recordTopicAttempt(widget.lesson.topic, isCorrect: true, isGame: true, citation: rp.citation);
                              setState(() {
                                _matchedPairIds.add(rp.id);
                                _selLeftIdx = null;
                                _matchErrorFlash = false;
                              });
                            } else {
                              widget.controller.playSound('wrong');
                              widget.controller.recordTopicAttempt(widget.lesson.topic, isCorrect: false, isGame: true, citation: rp.citation);
                              setState(() {
                                _matchErrorFlash = true;
                                _selLeftIdx = null;
                              });
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: matched ? BatchColors.ok.withOpacity(0.15) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: matched ? BatchColors.ok : BatchColors.teal.withOpacity(0.5), width: 1.3),
                      ),
                      child: Text(rp.right, textDirection: detectTextDirection(rp.right), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFillBlankGame() {
    final fb = _blanks[_blankIdx];
    final correct = _blankChecked && _blankChosen?.toLowerCase() == fb.answer.toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Chip(label: Text('✏️ أكمل الفراغ (${_blankIdx + 1} / ${_blanks.length})  •  📄 ${fb.citation}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fb.sentenceWithBlank.replaceAll('_____', _blankChosen ?? '________'),
                  textDirection: detectTextDirection(fb.sentenceWithBlank),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: fb.choices.map((ch) {
                    final sel = _blankChosen == ch;
                    return ChoiceChip(
                      selected: sel,
                      label: Text(ch, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : null)),
                      selectedColor: BatchColors.teal,
                      onSelected: _blankChecked
                          ? null
                          : (_) {
                              _gameAttempts++;
                              final ok = ch.toLowerCase() == fb.answer.toLowerCase();
                              if (ok) _gameCorrect++;
                              widget.controller.playSound(ok ? 'correct' : 'wrong');
                              widget.controller.recordTopicAttempt(widget.lesson.topic, isCorrect: ok, isGame: true, citation: fb.citation);
                              setState(() {
                                _blankChosen = ch;
                                _blankChecked = true;
                              });
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        if (_blankChecked) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (correct ? BatchColors.ok : BatchColors.err).withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              correct ? '✅ ممتاز! الإجابة الدقيقة هي: ${fb.answer}' : '❌ الصواب وفق المصدر هو: ${fb.answer}\n💡 ${fb.hint}',
              style: TextStyle(fontWeight: FontWeight.w800, color: correct ? BatchColors.ok : BatchColors.err),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BatchColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () {
              if (_blankIdx + 1 < _blanks.length) {
                setState(() {
                  _blankIdx++;
                  _blankChosen = null;
                  _blankChecked = false;
                });
              } else {
                _finishLesson();
              }
            },
            child: Text(_blankIdx + 1 < _blanks.length ? 'الجملة التالية ➔' : 'إنهاء الدرس بنجاح 🎉', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ],
    );
  }
}
