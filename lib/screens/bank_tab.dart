import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/mcq_parser.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gemini_auth_dialog.dart';

class BankTab extends StatefulWidget {
  final AppController controller;
  const BankTab({super.key, required this.controller});

  @override
  State<BankTab> createState() => _BankTabState();
}

class _BankTabState extends State<BankTab> {
  final _pasteCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _importExpanded = false;
  bool _toolsExpanded = false;
  bool _revealAnswers = true;
  bool _onlyIssues = false;
  String _diffFilter = 'all';
  String _sortMode = 'original';

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: err ? BatchColors.err : null),
    );
  }

  Future<void> _pickAndImport({bool forceSheet = false, bool useGemini = false}) async {
    final c = widget.controller;
    if (useGemini && !c.gemini.config.isSignedIn) {
      await showDialog(context: context, builder: (_) => GeminiAuthDialog(controller: c));
      return;
    }
    try {
      final msg = await c.importPickedFiles(forceSheet: forceSheet, useGemini: useGemini);
      _snack(msg);
    } catch (e) {
      _snack('خطأ: $e', err: true);
    }
  }

  Future<void> _parsePasted({bool useGemini = false}) async {
    final c = widget.controller;
    final txt = _pasteCtrl.text.trim();
    if (txt.isEmpty) {
      _snack('الصق نص الأسئلة أو المحاضرة أولاً.');
      return;
    }
    if (useGemini && !c.gemini.config.isSignedIn) {
      await showDialog(context: context, builder: (_) => GeminiAuthDialog(controller: c));
      return;
    }
    try {
      final msg = await c.importPastedText(txt, useGemini: useGemini);
      _pasteCtrl.clear();
      _snack(msg);
    } catch (e) {
      _snack('خطأ: $e', err: true);
    }
  }

  Future<void> _openQuestionEditor([McqQuestion? existing]) async {
    final c = widget.controller;
    final stemCtrl = TextEditingController(text: existing?.stem ?? '');
    final optCtrls = List.generate(4, (i) => TextEditingController(text: (existing != null && i < existing.options.length) ? existing.options[i] : ''));
    final expCtrl = TextEditingController(text: existing?.explanation ?? '');
    final topicCtrl = TextEditingController(text: existing?.topic ?? '');
    var diff = existing?.difficulty ?? 'medium';
    final selectedAns = <int>{...(existing?.getCorrectIndices() ?? [0])};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? '➕ إضافة سؤال MCQ' : '✏️ تعديل السؤال'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: stemCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'نص السؤال')),
                const SizedBox(height: 8),
                for (var i = 0; i < 4; i++) ...[
                  Row(
                    children: [
                      Checkbox(
                        value: selectedAns.contains(i),
                        onChanged: (v) => setS(() {
                          if (v == true) selectedAns.add(i);
                          else selectedAns.remove(i);
                        }),
                      ),
                      Expanded(
                        child: TextField(
                          controller: optCtrls[i],
                          decoration: InputDecoration(labelText: 'الخيار ${kMcqLetters[i]}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                DropdownButtonFormField<String>(
                  value: diff,
                  decoration: const InputDecoration(labelText: 'الصعوبة'),
                  items: const [
                    DropdownMenuItem(value: 'easy', child: Text('سهل')),
                    DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                    DropdownMenuItem(value: 'hard', child: Text('صعب')),
                  ],
                  onChanged: (v) => setS(() => diff = v ?? 'medium'),
                ),
                const SizedBox(height: 8),
                TextField(controller: topicCtrl, decoration: const InputDecoration(labelText: 'الموضوع')),
                const SizedBox(height: 8),
                TextField(controller: expCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'التعليل')),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  c.folder.questions.removeWhere((q) => q.uid == existing.uid);
                  c.save();
                  Navigator.pop(ctx);
                },
                child: const Text('حذف', style: TextStyle(color: BatchColors.err)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final opts = optCtrls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
                if (stemCtrl.text.trim().isEmpty || opts.length < 2) return;
                final cleanAns = selectedAns.where((i) => i < opts.length).toList()..sort();
                if (existing == null) {
                  c.folder.questions.add(McqParser.buildQuestion(
                    c.data,
                    stem: stemCtrl.text.trim(),
                    options: opts,
                    answerIndices: cleanAns,
                    explicitDiff: diff,
                    explicitTopic: topicCtrl.text.trim(),
                    explanation: expCtrl.text.trim(),
                  ));
                } else {
                  existing.stem = stemCtrl.text.trim();
                  existing.options = opts;
                  existing.setCorrectIndices(cleanAns);
                  existing.difficulty = diff;
                  if (topicCtrl.text.trim().isNotEmpty) existing.topic = topicCtrl.text.trim();
                  existing.explanation = expCtrl.text.trim();
                }
                c.save();
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  List<McqQuestion> _filteredQuestions(SubjectFolder folder) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final list = folder.questions.where((q) {
      if (_onlyIssues && !q.hasIssue) return false;
      if (_diffFilter != 'all' && q.difficulty != _diffFilter) return false;
      if (query.isNotEmpty) {
        final blob = '${q.stem} ${q.options.join(' ')} ${q.topic} ${q.explanation}'.toLowerCase();
        if (!blob.contains(query)) return false;
      }
      return true;
    }).toList();

    if (_sortMode == 'difficulty') {
      const order = {'easy': 1, 'medium': 2, 'hard': 3};
      list.sort((a, b) => (order[a.difficulty] ?? 2).compareTo(order[b.difficulty] ?? 2));
    } else if (_sortMode == 'topic') {
      list.sort((a, b) => a.topic.compareTo(b.topic));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final folder = c.folder;
    final total = folder.questions.length;
    final missing = folder.questions.where((q) => q.hasIssue).length;
    final ready = total - missing;
    final filtered = _filteredQuestions(folder);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Stats Row
        Row(
          children: [
            _statTile('الإجمالي', '$total', BatchColors.teal),
            const SizedBox(width: 6),
            _statTile('جاهزة', '$ready', BatchColors.ok),
            const SizedBox(width: 6),
            _statTile('ناقصة', '$missing', BatchColors.warn),
            const SizedBox(width: 6),
            _statTile('كاردز', '${folder.flashcards.length}', BatchColors.gold),
          ],
        ),
        const SizedBox(height: 10),

        // Import Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('📥 إضافة الأسئلة والشيتات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Wrap(
                      spacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => setState(() => _importExpanded = !_importExpanded),
                          icon: Icon(_importExpanded ? Icons.expand_less : Icons.folder_open, size: 17),
                          label: const Text('استيراد / لصق', style: TextStyle(fontSize: 12)),
                        ),
                        FilledButton.icon(
                          onPressed: () => _pickAndImport(forceSheet: false),
                          icon: const Icon(Icons.upload_file, size: 17),
                          label: const Text('شيت PDF/PPTX', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: () => _openQuestionEditor(),
                          child: const Text('＋ سؤال', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_importExpanded) ...[
                  const Divider(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _pickAndImport(forceSheet: true, useGemini: true),
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: const Text('استخراج بـ Gemini (PDF/PPTX)'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _pickAndImport(forceSheet: true, useGemini: false),
                        icon: const Icon(Icons.auto_fix_high, size: 17),
                        label: const Text('تحويل محلي سريع'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final msg = await c.importPastedText(McqParser.sampleText);
                          _snack(msg);
                        },
                        child: const Text('🧪 عينة جاهزة'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pasteCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'الصق نص الأسئلة أو ملخص المحاضرة هنا...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => _parsePasted(useGemini: false),
                        child: const Text('⚡ تحليل النص'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _parsePasted(useGemini: true),
                        child: const Text('✨ استخراج بـ Gemini'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // Search & Filter Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, size: 19),
                          hintText: 'ابحث في الأسئلة أو المواضيع...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => setState(() => _toolsExpanded = !_toolsExpanded),
                      icon: const Icon(Icons.tune),
                      tooltip: 'الفلاتر والأدوات',
                    ),
                  ],
                ),
                if (_toolsExpanded) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _diffFilter,
                          decoration: const InputDecoration(labelText: 'الصعوبة'),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('الكل')),
                            DropdownMenuItem(value: 'easy', child: Text('سهل')),
                            DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                            DropdownMenuItem(value: 'hard', child: Text('صعب')),
                          ],
                          onChanged: (v) => setState(() => _diffFilter = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _sortMode,
                          decoration: const InputDecoration(labelText: 'الترتيب'),
                          items: const [
                            DropdownMenuItem(value: 'original', child: Text('الأصلي')),
                            DropdownMenuItem(value: 'difficulty', child: Text('حسب الصعوبة')),
                            DropdownMenuItem(value: 'topic', child: Text('حسب الموضوع')),
                          ],
                          onChanged: (v) => setState(() => _sortMode = v ?? 'original'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('إظهار الإجابات'),
                        selected: _revealAnswers,
                        onSelected: (v) => setState(() => _revealAnswers = v),
                      ),
                      FilterChip(
                        label: const Text('التي تنقصها إجابة'),
                        selected: _onlyIssues,
                        onSelected: (v) => setState(() => _onlyIssues = v),
                      ),
                      ActionChip(
                        label: const Text('♻️ حذف المكرر'),
                        onPressed: () {
                          final n = c.removeDuplicates();
                          _snack(n > 0 ? 'تم حذف $n سؤال مكرر' : 'لا توجد أسئلة مكررة ✅');
                        },
                      ),
                      ActionChip(
                        label: const Text('🔀 خلط الأسئلة'),
                        onPressed: () {
                          folder.questions.shuffle(Random());
                          c.save();
                          _snack('تم خلط الأسئلة 🔀');
                        },
                      ),
                      ActionChip(
                        label: const Text('⚖️ موازنة A/B/C/D'),
                        onPressed: () {
                          final adj = McqParser.smartBalanceAnswers(folder.questions);
                          c.save();
                          _snack('تم إعادة توزيع $adj سؤال بتوازن ذكي ⚖️');
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 38)),
                  const SizedBox(height: 6),
                  Text('مجلد "${folder.name}" فارغ أو لا يطابق البحث',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('ارفع ملف PDF / PowerPoint / DOCX / TXT أو الصق الأسئلة بالأعلى.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          )
        else
          ...filtered.asMap().entries.map((entry) {
            final idx = entry.key;
            final q = entry.value;
            final corr = q.getCorrectIndices();
            final dir = detectTextDirection(q.stem);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _pill('#${idx + 1}', BatchColors.navy),
                        const SizedBox(width: 6),
                        _pill(kDiffLabels[q.difficulty] ?? q.difficulty,
                            q.difficulty == 'easy' ? BatchColors.ok : (q.difficulty == 'hard' ? BatchColors.err : BatchColors.warn)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(q.topic,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: BatchColors.teal)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _openQuestionEditor(q),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Directionality(
                      textDirection: dir,
                      child: Text(q.stem, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    ),
                    const SizedBox(height: 8),
                    for (var oi = 0; oi < q.options.length; oi++)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          final cur = [...q.getCorrectIndices()];
                          if (q.isMultiAnswer) {
                            if (cur.contains(oi)) cur.remove(oi);
                            else cur.add(oi);
                            q.setCorrectIndices(cur, keepMultiFlag: true);
                          } else {
                            q.setCorrectIndices([oi]);
                          }
                          c.save();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: (_revealAnswers && corr.contains(oi))
                                ? BatchColors.ok.withOpacity(0.14)
                                : Theme.of(context).dividerColor.withOpacity(0.12),
                            border: Border.all(
                              color: (_revealAnswers && corr.contains(oi))
                                  ? BatchColors.ok
                                  : Theme.of(context).dividerColor.withOpacity(0.4),
                            ),
                          ),
                          child: Directionality(
                            textDirection: detectTextDirection(q.options[oi]),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: (_revealAnswers && corr.contains(oi)) ? BatchColors.ok : Colors.black12,
                                  child: Text(kMcqLetters[oi],
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: (_revealAnswers && corr.contains(oi)) ? Colors.white : null)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(q.options[oi], style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_revealAnswers && q.explanation.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BatchColors.teal.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('💡 ${q.explanation}', style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _statTile(String label, String val, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: col)),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _pill(String txt, Color col) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: col.withOpacity(0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(txt, style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}
