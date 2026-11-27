import 'dart:async';
import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gemini_auth_dialog.dart';
import 'bank_tab.dart';
import 'flashcards_tab.dart';
import 'more_tabs.dart';
import 'quiz_tab.dart';
import 'study_plan_tab.dart';

class HomeShell extends StatefulWidget {
  final AppController controller;
  const HomeShell({super.key, required this.controller});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  void _openGeminiDialog() {
    showDialog(
      context: context,
      builder: (_) => GeminiAuthDialog(controller: widget.controller),
    );
  }

  Future<void> _showFolderEditor({bool createNew = true}) async {
    final c = widget.controller;
    final existing = createNew ? null : c.folder;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var colorHex = existing?.colorHex ?? '#0D9488';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(createNew ? '➕ مجلد مادة جديد' : '✏️ تعديل المجلد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المادة / المجلد'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['#0D9488', '#0F2942', '#C59B27', '#2563EB', '#7C3AED', '#DC2626']
                    .map((hex) => GestureDetector(
                          onTap: () => setS(() => colorHex = hex),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: parseHexColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorHex == hex ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: colorHex == hex
                                  ? [BoxShadow(color: parseHexColor(hex), blurRadius: 6)]
                                  : null,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            if (!createNew && c.data.folders.length > 1)
              TextButton(
                onPressed: () {
                  c.deleteFolder(existing!.id);
                  Navigator.pop(ctx);
                },
                child: const Text('حذف', style: TextStyle(color: BatchColors.err)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (createNew) {
                  c.createFolder(name, colorHex);
                } else {
                  c.renameFolder(existing!.id, name, colorHex);
                }
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أدوات إضافية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            Row(
              children: [
                _moreTile(ctx, '✅', 'مصحح الأجوبة', 4),
                const SizedBox(width: 8),
                _moreTile(ctx, '📊', 'الإحصائيات والتوازن', 5),
                const SizedBox(width: 8),
                _moreTile(ctx, '📤', 'التصدير والنسخ', 6),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _moreTile(BuildContext ctx, String icon, String title, int tabIdx) {
    final active = widget.controller.currentTabIndex == tabIdx;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pop(ctx);
          widget.controller.setTab(tabIdx);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active ? BatchColors.teal.withOpacity(0.14) : Theme.of(context).cardColor,
            border: Border.all(color: active ? BatchColors.teal : Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.lastAuthMessage != null) {
          final msg = c.lastAuthMessage!;
          final isErr = c.lastAuthIsError;
          c.lastAuthMessage = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: isErr ? BatchColors.err : BatchColors.ok,
            ));
          });
        }

        final folder = c.folder;
        final dueCount = folder.questions.where((q) => !q.hasIssue && q.isDue()).length;

        final bodyWidget = switch (c.currentTabIndex) {
          0 => BankTab(controller: c),
          1 => StudyPlanTab(controller: c),
          2 => QuizTab(controller: c),
          3 => FlashcardsTab(controller: c),
          4 => SheetGraderTab(controller: c),
          5 => AnalyticsTab(controller: c),
          _ => ExportBackupTab(controller: c),
        };

        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                backgroundColor: BatchColors.navy,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: const Border(bottom: BorderSide(color: BatchColors.gold, width: 2.5)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: BatchColors.gold, width: 1.5),
                      ),
                      child: Image.asset('assets/images/logo.png', height: 32),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Batch 27 — MCQ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text('كلية الطب والعلوم الصحية', style: TextStyle(fontSize: 10.5, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: _openGeminiDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: c.gemini.config.isSignedIn ? const Color(0xFF6EE7B7) : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(c.gemini.config.isSignedIn ? '✨ Gemini ✅' : '✨ Gemini',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: c.data.soundEnabled ? 'الأصوات: شغالة' : 'الأصوات: مكتومة',
                    onPressed: c.toggleSound,
                    icon: Icon(c.data.soundEnabled ? Icons.volume_up : Icons.volume_off, size: 20),
                  ),
                  IconButton(
                    tooltip: 'الوضع الليلي',
                    onPressed: c.toggleTheme,
                    icon: Icon(c.data.darkMode ? Icons.light_mode : Icons.dark_mode, size: 20),
                  ),
                  IconButton(
                    tooltip: 'تفريغ المجلد',
                    onPressed: () {
                      c.clearActiveFolder();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم تفريغ مجلد "${folder.name}" 🗑️')),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (c.busy) const LinearProgressIndicator(minHeight: 3),
                  // Subject Folders Strip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5))),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('📁 المجلدات:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: parseHexColor(folder.colorHex).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(folder.name,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: parseHexColor(folder.colorHex))),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _showFolderEditor(createNew: true),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('جديد', style: TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              onPressed: () => _showFolderEditor(createNew: false),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'تعديل المجلد',
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 34,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: c.data.folders.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, idx) {
                              final f = c.data.folders[idx];
                              final active = f.id == folder.id;
                              final col = parseHexColor(f.colorHex);
                              return ChoiceChip(
                                selected: active,
                                label: Text('${f.name} (${f.questions.length})',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: active ? Colors.white : null,
                                    )),
                                selectedColor: col,
                                onSelected: (_) => c.switchFolder(f.id),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: bodyWidget),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: c.currentTabIndex > 3 ? 4 : c.currentTabIndex,
                onDestinationSelected: (idx) {
                  if (idx == 4) {
                    _openMoreSheet();
                  } else {
                    c.setTab(idx);
                  }
                },
                destinations: [
                  NavigationDestination(
                    icon: Badge(label: Text('${folder.questions.length}'), child: const Icon(Icons.inventory_2_outlined)),
                    label: 'الأسئلة',
                  ),
                  const NavigationDestination(icon: Icon(Icons.school_outlined), label: 'الخطة'),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: dueCount > 0,
                      label: Text('$dueCount'),
                      child: const Icon(Icons.edit_note),
                    ),
                    label: 'اختبر الآن',
                  ),
                  NavigationDestination(
                    icon: Badge(label: Text('${folder.flashcards.length}'), child: const Icon(Icons.style_outlined)),
                    label: 'فلاش كاردز',
                  ),
                  const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
                ],
              ),
            ),
            if (_showSplash)
              GestureDetector(
                onTap: () => setState(() => _showSplash = false),
                child: Container(
                  color: BatchColors.navy,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: BatchColors.gold, width: 3),
                        ),
                        child: Image.asset('assets/images/logo.png', height: 110),
                      ),
                      const SizedBox(height: 14),
                      const Text('Best of the Best',
                          style: TextStyle(color: BatchColors.gold, fontSize: 16, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
