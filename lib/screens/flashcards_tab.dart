import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../services/native_bridge.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gemini_auth_dialog.dart';

class FlashcardsTab extends StatefulWidget {
  final AppController controller;
  const FlashcardsTab({super.key, required this.controller});

  @override
  State<FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<FlashcardsTab> {
  bool _importOpen = false;
  bool _reminderOpen = false;
  bool _flipped = false;
  int _idx = 0;
  String _filter = 'all';
  String _notifStatus = 'ok';
  final _fcPasteCtrl = TextEditingController();
  final _delayCtrl = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _refreshNotif();
  }

  @override
  void dispose() {
    _fcPasteCtrl.dispose();
    _delayCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshNotif() async {
    final st = await NativeBridge.getNotifStatus();
    if (mounted) setState(() => _notifStatus = st);
  }

  List<FlashcardItem> _deck(SubjectFolder folder) {
    return folder.flashcards.where((c) {
      if (_filter == 'unmastered') return c.status != 'mastered';
      if (_filter == 'mastered') return c.status == 'mastered';
      if (_filter == 'starred') return c.starred;
      return true;
    }).toList();
  }

  void _addCardsFromText() {
    final c = widget.controller;
    final raw = _fcPasteCtrl.text.trim();
    if (raw.isEmpty) return;
    var added = 0;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final parts = t.split(RegExp(r'\s*(?:::|\t|\||;|؛)\s*'));
      if (parts.length >= 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        c.folder.flashcards.add(FlashcardItem(
          uid: c.data.nextCardUid++,
          front: parts[0].trim(),
          back: parts.sublist(1).join(' ').trim(),
          topic: c.folder.name,
        ));
        added++;
      }
    }
    if (added > 0) {
      _fcPasteCtrl.clear();
      c.save();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إضافة $added بطاقة ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final folder = c.folder;
    final deck = _deck(folder);
    if (_idx >= deck.length) _idx = max(0, deck.length - 1);
    final masteredCount = folder.flashcards.where((x) => x.status == 'mastered').length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('🃏 الفلاش كاردز', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Wrap(
                      spacing: 6,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => setState(() => _importOpen = !_importOpen),
                          child: const Text('📥 استيراد / توليد', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: () => setState(() => _reminderOpen = !_reminderOpen),
                          child: const Text('🔔 التذكير', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_importOpen) ...[
                  const Divider(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          final added = c.convertMcqsToFlashcards(folder.questions);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم توليد $added بطاقة من الأسئلة ✨')),
                          );
                        },
                        icon: const Icon(Icons.auto_fix_high, size: 17),
                        label: const Text('تحويل MCQ إلى بطاقات'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final msg = await c.importPickedFiles(forceSheet: true, useGemini: false);
                          if (mounted && msg.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf, size: 17),
                        label: const Text('شيت PDF/PPTX محلي'),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          if (!c.gemini.config.isSignedIn) {
                            await showDialog(context: context, builder: (_) => GeminiAuthDialog(controller: c));
                            return;
                          }
                          final msg = await c.importPickedFiles(forceSheet: true, useGemini: true);
                          if (mounted && msg.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                          }
                        },
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: const Text('شيت بـ Gemini'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final csv = ExportService.buildFlashcardsAnkiCsv(folder);
                          await NativeBridge.saveFile('${folder.name}-anki.csv', csv);
                        },
                        child: const Text('📄 تصدير Anki CSV'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _fcPasteCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'المصطلح :: التعريف (أو افصل بـ ; أو |)'),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _addCardsFromText, child: const Text('⚡ إضافة البطاقات')),
                  ),
                ],
                if (_reminderOpen) ...[
                  const Divider(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _delayCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'تذكير بعد (دقيقة)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final mins = max(1, int.tryParse(_delayCtrl.text.trim()) ?? 30);
                          final trigger = DateTime.now().millisecondsSinceEpoch + mins * 60000;
                          final st = await NativeBridge.scheduleReminder(
                            triggerAtMs: trigger,
                            intervalMs: c.data.reminder.intervalMin * 60000,
                            title: 'Batch 27 — تذكير المراجعة',
                            body: 'لديك ${folder.flashcards.length} بطاقة في ${folder.name} 🃏',
                          );
                          c.data.reminder.enabled = true;
                          c.data.reminder.delayMin = mins;
                          c.data.reminder.nextTriggerMs = trigger;
                          c.save();
                          setState(() => _notifStatus = st);
                        },
                        child: const Text('🔔 تفعيل'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => NativeBridge.testNotification('Batch 27', 'إشعار تجريبي للمراجعة 🃏'),
                        child: const Text('🧪 إشعار تجريبي'),
                      ),
                      TextButton(
                        onPressed: () {
                          NativeBridge.cancelReminder();
                          c.data.reminder.enabled = false;
                          c.save();
                        },
                        child: const Text('🔕 إيقاف'),
                      ),
                      if (_notifStatus != 'ok')
                        TextButton(
                          onPressed: NativeBridge.openNotifSettings,
                          child: const Text('⚙️ إعدادات الإشعارات'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // Study Arena
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      deck.isEmpty ? 'لا توجد بطاقات' : 'بطاقة ${_idx + 1} من ${deck.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Chip(label: Text('متقن: $masteredCount / ${folder.flashcards.length}', style: const TextStyle(fontSize: 11.5))),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _filter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('الكل')),
                        DropdownMenuItem(value: 'unmastered', child: Text('للمراجعة')),
                        DropdownMenuItem(value: 'mastered', child: Text('متقنة ✅')),
                        DropdownMenuItem(value: 'starred', child: Text('المفضلة ⭐')),
                      ],
                      onChanged: (v) => setState(() {
                        _filter = v ?? 'all';
                        _idx = 0;
                        _flipped = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (deck.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('ارفع شيت PDF/PPTX أو حوّل أسئلة MCQ لإنشاء بطاقاتك هنا 🃏',
                        textAlign: TextAlign.center),
                  )
                else ...[
                  GestureDetector(
                    onTap: () {
                      setState(() => _flipped = !_flipped);
                      c.playSound('flip');
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _flipped ? pi : 0),
                      duration: const Duration(milliseconds: 360),
                      builder: (context, angle, _) {
                        final isBack = angle > pi / 2;
                        final card = deck[_idx];
                        final shown = isBack ? card.back : card.front;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: isBack ? (Matrix4.identity()..rotateY(pi)) : Matrix4.identity(),
                            child: Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(minHeight: 220),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: isBack ? BatchColors.teal.withOpacity(0.12) : Theme.of(context).cardColor,
                                border: Border.all(
                                  color: isBack ? BatchColors.gold : BatchColors.teal,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Text(isBack ? 'الإجابة / الشرح' : 'المفهوم / السؤال',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: isBack ? BatchColors.gold : BatchColors.teal,
                                        )),
                                  ),
                                  const SizedBox(height: 14),
                                  Directionality(
                                    textDirection: detectTextDirection(shown),
                                    child: Text(
                                      shown,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (card.hint.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(card.hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_flipped)
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            deck[_idx].status = 'learning';
                            c.save();
                            setState(() {
                              _flipped = false;
                              _idx = (_idx + 1) % deck.length;
                            });
                          },
                          child: const Text('🔴 صعب'),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            deck[_idx].status = 'review';
                            c.save();
                            setState(() {
                              _flipped = false;
                              _idx = (_idx + 1) % deck.length;
                            });
                          },
                          child: const Text('🟡 تذكرتها'),
                        ),
                        FilledButton(
                          onPressed: () {
                            deck[_idx].status = 'mastered';
                            c.playSound('correct');
                            c.save();
                            setState(() {
                              _flipped = false;
                              _idx = (_idx + 1) % deck.length;
                            });
                          },
                          child: const Text('🟢 أتقنتها ✅'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _idx = (_idx - 1 + deck.length) % deck.length;
                          _flipped = false;
                        }),
                        child: const Text('⬅️ السابقة'),
                      ),
                      FilledButton(
                        onPressed: () => setState(() => _flipped = !_flipped),
                        child: const Text('🔄 اقلب'),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _idx = (_idx + 1) % deck.length;
                          _flipped = false;
                        }),
                        child: const Text('التالية ➡️'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
