import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

Future<void> openSocraticTutorSheet(
  BuildContext context, {
  required AppController controller,
  MicroLesson? activeLesson,
  String? initialQuestion,
  String? wrongContext,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      height: MediaQuery.of(ctx).size.height * 0.88,
      decoration: BoxDecoration(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(99)),
          ),
          Expanded(
            child: SocraticTutorPanel(
              controller: controller,
              activeLesson: activeLesson,
              initialQuestion: initialQuestion,
              wrongContext: wrongContext,
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}

class SocraticTutorPanel extends StatefulWidget {
  final AppController controller;
  final MicroLesson? activeLesson;
  final String? initialQuestion;
  final String? wrongContext;
  final VoidCallback? onClose;

  const SocraticTutorPanel({
    super.key,
    required this.controller,
    this.activeLesson,
    this.initialQuestion,
    this.wrongContext,
    this.onClose,
  });

  @override
  State<SocraticTutorPanel> createState() => _SocraticTutorPanelState();
}

class _SocraticTutorPanelState extends State<SocraticTutorPanel> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final initQ = widget.initialQuestion;
    if (initQ != null && initQ.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendText(initQ);
      });
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText(String txt) async {
    final clean = txt.trim();
    if (clean.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);
    _scrollToBottom();
    try {
      await widget.controller.sendTutorMessage(
        clean,
        activeLesson: widget.activeLesson,
        wrongQuestionContext: widget.wrongContext,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: BatchColors.err));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showCitationPreview(String citation) {
    final chunks = widget.controller.folder.allChunks;
    final matched = chunks.where((c) => c.citation == citation || citation.contains(c.sectionTitle)).toList();
    final excerpt = matched.isNotEmpty
        ? matched.first.text
        : (widget.activeLesson?.sourceExcerpt.isNotEmpty == true
            ? widget.activeLesson!.sourceExcerpt
            : 'هذا المرجع مرتبط بالمادة المرفوعة داخل مجلد "${widget.controller.folder.name}".');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.menu_book_rounded, color: BatchColors.teal, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(citation, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(excerpt, textDirection: detectTextDirection(excerpt), style: const TextStyle(fontSize: 13.5, height: 1.5)),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('فهمت')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final history = c.folder.tutorHistory;
        final chunkCount = c.folder.allChunks.length;
        final lang = c.data.tutorLanguage;
        final lastTutorMsg = history.lastWhere(
          (m) => m.role == 'tutor',
          orElse: () => TutorMessage(role: 'tutor', text: ''),
        );

        return Column(
          children: [
            // Socratic Tutor Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: BatchColors.navy,
                borderRadius: widget.onClose != null ? const BorderRadius.vertical(top: Radius.circular(18)) : null,
                border: const Border(bottom: BorderSide(color: BatchColors.teal, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 17,
                        backgroundColor: BatchColors.teal,
                        child: Text('🧠', style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('المعلم السقراطي الذكي (LearnKata)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                            Text(
                              widget.activeLesson != null
                                  ? 'مقيّد بمصدر الدرس: ${widget.activeLesson!.sourceCitation}'
                                  : (chunkCount > 0
                                      ? 'موثق بـ $chunkCount مقطع من مصادرك • لا يعطيك الجواب جاهزاً!'
                                      : 'ارفع PDF/PPTX أو نص محاضرة لتفعيل الاستشهاد المصدري'),
                              style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'محادثة جديدة',
                        onPressed: c.clearTutorHistory,
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                      ),
                      if (widget.onClose != null)
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Multilingual selector row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _langChip(c, 'bilingual', '🌐 ثنائي (عربي + مصطلحات)', lang == 'bilingual'),
                        const SizedBox(width: 6),
                        _langChip(c, 'ar', '🇸🇦 عربي', lang == 'ar'),
                        const SizedBox(width: 6),
                        _langChip(c, 'en', '🇬🇧 English', lang == 'en'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Chat timeline
            Expanded(
              child: history.isEmpty
                  ? _buildEmptyWelcome(chunkCount)
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: history.length + (_sending ? 1 : 0),
                      itemBuilder: (context, idx) {
                        if (_sending && idx == history.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('المعلم يراجع المصادر لصياغة تلميح ذكي...', style: TextStyle(fontSize: 12.5)),
                              ],
                            ),
                          );
                        }
                        final msg = history[idx];
                        final isUser = msg.role == 'user';
                        return _buildBubble(msg, isUser);
                      },
                    ),
            ),

            // Contextual Starter / Guided Hint Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (lastTutorMsg.suggestedPrompt != null && lastTutorMsg.suggestedPrompt!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 15, color: BatchColors.teal),
                          label: Text(lastTutorMsg.suggestedPrompt!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          onPressed: () => _sendText(lastTutorMsg.suggestedPrompt!),
                        ),
                      ),
                    ActionChip(
                      label: const Text('💡 أعطني تلميحاً فقط', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => _sendText('لا تخبرني بالإجابة مباشرة، أعطني تلميحاً خطوة بخطوة مع المرجع'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('🔬 اشرح بمثال سريري', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => _sendText('اشرح هذا المفهوم بتشبيه سريري مبسط واسألني سؤالاً للتأكد من فهمي'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('❓ اختبر فهمي', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => _sendText('اسألني سؤال استنتاج قصير من مصدر الدرس لأتأكد من استيعابي'),
                    ),
                  ],
                ),
              ),
            ),

            // Input bar
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendText,
                      decoration: const InputDecoration(
                        hintText: 'اسأل المعلم السقراطي أو اشرح له محاولتك...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: BatchColors.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _sending ? null : () => _sendText(_inputCtrl.text),
                    child: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _langChip(AppController c, String val, String label, bool selected) {
    return ChoiceChip(
      selected: selected,
      selectedColor: BatchColors.teal,
      backgroundColor: BatchColors.navy2,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      label: Text(label),
      onSelected: (_) => c.setTutorLanguage(val),
    );
  }

  Widget _buildEmptyWelcome(int chunkCount) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('🧠 منهجية LearnKata السقراطية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  chunkCount > 0
                      ? 'أنا مرتبط حالياً بـ $chunkCount مقطع من مصادرك المرفوعة.\nلن أعطيك الإجابة جاهزة؛ بل سأقودك بالتلميحات والأمثلة خطوة بخطوة مع توثيق رقم السلايد/الصفحة!'
                      : 'ابدأ برفع ملف محاضرة (PDF / PPTX) أو لصق نص في تبويب الخطة، أو اسألني وسأرشدك بالاستنتاج خطوة بخطوة.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(TutorMessage msg, bool isUser) {
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser
        ? BatchColors.teal
        : (Theme.of(context).brightness == Brightness.dark ? BatchColors.darkCard2 : Colors.white);
    final fg = isUser ? Colors.white : null;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: BatchColors.teal.withOpacity(0.35)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              textDirection: detectTextDirection(msg.text),
              style: TextStyle(color: fg, fontSize: 13.5, height: 1.5, fontWeight: isUser ? FontWeight.w600 : FontWeight.w500),
            ),
            if (!isUser && msg.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: msg.citations
                    .map((cite) => ActionChip(
                          avatar: const Icon(Icons.menu_book_outlined, size: 14, color: BatchColors.teal),
                          label: Text(cite, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                          onPressed: () => _showCitationPreview(cite),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
