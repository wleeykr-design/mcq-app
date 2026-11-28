import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/file_extractor.dart';
import '../services/gemini_oauth_service.dart';
import '../services/lecture_analyzer.dart';
import '../services/mcq_parser.dart';
import '../services/native_bridge.dart';
import '../services/source_curriculum_engine.dart';
import '../services/storage_service.dart';

class AppController extends ChangeNotifier {
  AppDataState data = AppDataState();
  final GeminiOAuthService gemini = GeminiOAuthService();

  // 0: bank, 1: studyPlan, 2: quiz, 3: flashcards, 4: sheet, 5: analytics/mastery, 6: export, 7: socraticTutor
  int currentTabIndex = 1;
  bool loaded = false;
  bool busy = false;
  String? lastAuthMessage;
  bool lastAuthIsError = false;

  // Quiz launch request from Study Plan or Analytics
  List<McqQuestion>? pendingQuizItems;
  String? pendingQuizUnitKey;

  Future<void> init() async {
    data = await StorageService.loadState();
    data.syncDailyReset();
    loaded = true;
    notifyListeners();

    await gemini.init((cfg, error) {
      if (error != null) {
        lastAuthMessage = error;
        lastAuthIsError = true;
      } else if (cfg.isSignedIn) {
        lastAuthMessage = '✅ تم ربط Gemini بحساب ${cfg.userEmail.isNotEmpty ? cfg.userEmail : "Google"} بنجاح!';
        lastAuthIsError = false;
        playSound('correct');
      }
      notifyListeners();
    });

    NativeBridge.listenOpenTab((tab) {
      if (tab == 'flashcards') {
        setTab(3);
      }
    });
    final pendingTab = await NativeBridge.consumePendingTab();
    if (pendingTab == 'flashcards') {
      setTab(3);
    }
  }

  @override
  void dispose() {
    gemini.dispose();
    super.dispose();
  }

  void setTab(int idx) {
    currentTabIndex = idx;
    notifyListeners();
  }

  Future<void> save() async {
    await StorageService.saveState(data);
    notifyListeners();
  }

  Future<void> signOutGoogle() async {
    await gemini.signOut();
    notifyListeners();
  }

  void playSound(String kind) {
    if (!data.soundEnabled) return;
    NativeBridge.playSound(kind);
  }

  void toggleSound() {
    data.soundEnabled = !data.soundEnabled;
    if (data.soundEnabled) playSound('correct');
    save();
  }

  void toggleTheme() {
    data.darkMode = !data.darkMode;
    save();
  }

  void setTutorLanguage(String lang) {
    data.tutorLanguage = lang;
    save();
  }

  SubjectFolder get folder => data.activeFolder;

  void switchFolder(String id) {
    data.activeFolderId = id;
    save();
  }

  void createFolder(String name, String colorHex) {
    final f = SubjectFolder(
      id: 'f${data.nextFolderId++}',
      name: name.trim(),
      colorHex: colorHex,
    );
    data.folders.add(f);
    data.activeFolderId = f.id;
    save();
  }

  void renameFolder(String id, String name, String colorHex) {
    for (final f in data.folders) {
      if (f.id == id) {
        f.name = name.trim();
        f.colorHex = colorHex;
      }
    }
    save();
  }

  bool deleteFolder(String id) {
    if (data.folders.length <= 1) return false;
    data.folders.removeWhere((f) => f.id == id);
    if (!data.folders.any((f) => f.id == data.activeFolderId)) {
      data.activeFolderId = data.folders.first.id;
    }
    save();
    return true;
  }

  void clearActiveFolder() {
    folder.questions.clear();
    folder.cases.clear();
    folder.flashcards.clear();
    folder.lastWrongIds.clear();
    folder.sources.clear();
    folder.lessons.clear();
    folder.topicMastery.clear();
    folder.tutorHistory.clear();
    save();
  }

  // ===========================================================================
  // LEARNKATA SOURCE-GROUNDED CURRICULUM INGESTION
  // ===========================================================================
  Future<String> ingestLearnKataMaterial({
    required String sourceName,
    required String rawText,
    String fileType = 'text',
    bool useGemini = false,
    bool replaceRoadmap = false,
  }) async {
    if (rawText.trim().length < 25) {
      throw Exception('المحتوى قصير جداً لبناء خطة دروس مترابطة.');
    }
    busy = true;
    notifyListeners();
    try {
      if (replaceRoadmap) {
        folder.lessons.clear();
        folder.sources.clear();
      }
      final res = await SourceCurriculumEngine.ingestSource(
        appState: data,
        gemini: gemini,
        sourceName: sourceName,
        rawText: rawText,
        fileType: fileType,
        preferGemini: useGemini,
        startingOrderIndex: folder.lessons.length,
      );

      folder.sources.add(res.document);
      folder.lessons.addAll(res.lessons);

      final existingQ = folder.questions.map((q) => McqParser.normalizeStem(q.stem)).toSet();
      for (final q in res.bankQuestions) {
        final k = McqParser.normalizeStem(q.stem);
        if (k.isNotEmpty && existingQ.add(k)) {
          folder.questions.add(q);
        }
      }

      final existingFc = folder.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
      for (final fc in res.flashcards) {
        final k = McqParser.normalizeStem(fc.front);
        if (k.isNotEmpty && existingFc.add(k)) {
          folder.flashcards.add(fc);
        }
      }

      data.xp += 15;
      data.dailyXp += 15;
      playSound('correct');
      await save();
      final modeLabel = res.usedAi ? '✨ بالذكاء الاصطناعي Gemini' : '⚡ بالمحلل المحلي الموثق';
      return '🎓 تم بناء ${res.lessons.length} دروس مصغرة ($modeLabel) مع مراجع المصدر في "${folder.name}"!';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> pickAndIngestLearnKata({bool useGemini = false, bool replaceRoadmap = false}) async {
    final files = await NativeBridge.pickFiles(allowMultiple: true);
    if (files.isEmpty) return '';

    busy = true;
    notifyListeners();
    var builtLessons = 0;
    var usedAiAny = false;
    final errors = <String>[];

    try {
      if (replaceRoadmap) {
        folder.lessons.clear();
        folder.sources.clear();
      }
      for (final file in files) {
        try {
          final text = await FileExtractor.extractText(file.name, file.bytes);
          final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'text';
          final res = await SourceCurriculumEngine.ingestSource(
            appState: data,
            gemini: gemini,
            sourceName: file.name,
            rawText: text,
            fileType: ext,
            preferGemini: useGemini,
            startingOrderIndex: folder.lessons.length,
          );
          if (res.usedAi) usedAiAny = true;
          folder.sources.add(res.document);
          folder.lessons.addAll(res.lessons);
          builtLessons += res.lessons.length;

          final existingQ = folder.questions.map((q) => McqParser.normalizeStem(q.stem)).toSet();
          for (final q in res.bankQuestions) {
            if (existingQ.add(McqParser.normalizeStem(q.stem))) {
              folder.questions.add(q);
            }
          }
          final existingFc = folder.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
          for (final fc in res.flashcards) {
            if (existingFc.add(McqParser.normalizeStem(fc.front))) {
              folder.flashcards.add(fc);
            }
          }
        } catch (e) {
          errors.add('${file.name}: $e');
        }
      }
    } finally {
      busy = false;
    }

    if (builtLessons > 0) {
      data.xp += 15;
      data.dailyXp += 15;
      playSound('correct');
      await save();
      return '🎓 تم توليد $builtLessons درس LearnKata تفاعلي${usedAiAny ? " (Gemini)" : ""} في "${folder.name}"!';
    }
    notifyListeners();
    if (errors.isNotEmpty) throw Exception(errors.join('\n'));
    return 'تعذر استخراج دروس من الملف المختار.';
  }

  void ensureRoadmapSyncedFromQuestions() {
    if (folder.lessons.isEmpty && folder.questions.isNotEmpty) {
      folder.lessons = SourceCurriculumEngine.buildFromRawQuestions(
        folder,
        unitSize: data.spUnitSize > 0 ? data.spUnitSize : 6,
      );
      save();
    }
  }

  // ===========================================================================
  // MASTERY TRACKING & LESSON COMPLETION
  // ===========================================================================
  void recordTopicAttempt(
    String topic, {
    required bool isCorrect,
    bool isFlashcard = false,
    bool isGame = false,
    String? citation,
  }) {
    final cleanTopic = topic.trim().isEmpty ? 'General Medicine' : topic.trim();
    final stat = folder.topicMastery.putIfAbsent(cleanTopic, () => TopicMastery(topic: cleanTopic));
    stat.record(isCorrect: isCorrect, isFlashcard: isFlashcard, isGame: isGame, citation: citation);
    save();
  }

  Future<void> completeMicroLesson(
    MicroLesson lesson, {
    required int quizPct,
    required bool didFlashcards,
    required bool didGame,
  }) async {
    lesson.completed = true;
    if (quizPct > lesson.bestQuizPct) lesson.bestQuizPct = quizPct;
    if (didGame) lesson.gameCompleted = true;
    final stars = quizPct >= 85 && didGame ? 3 : (quizPct >= 60 ? 2 : 1);
    if (stars > lesson.stars) lesson.stars = stars;

    // Also update legacy StudyUnitProgress map for full continuity
    data.studyProgress[lesson.id] = StudyUnitProgress(
      stars: lesson.stars,
      bestPct: lesson.bestQuizPct,
      attempts: (data.studyProgress[lesson.id]?.attempts ?? 0) + 1,
    );

    data.syncDailyReset();
    final gain = 25 + (didGame ? 10 : 0) + (didFlashcards ? 5 : 0);
    data.xp += gain;
    data.dailyXp += gain;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (data.lastStudyDay != today) {
      data.lastStudyDay = today;
      data.streak += 1;
    }

    playSound('correct');
    await save();
  }

  // ===========================================================================
  // STEP-BY-STEP SOCRATIC AI TUTOR
  // ===========================================================================
  Future<TutorMessage> sendTutorMessage(
    String userText, {
    MicroLesson? activeLesson,
    String? wrongQuestionContext,
  }) async {
    final clean = userText.trim();
    if (clean.isEmpty) {
      throw Exception('اكتب سؤالك للمعلم أولاً.');
    }

    folder.tutorHistory.add(TutorMessage(role: 'user', text: clean));
    notifyListeners();

    final citedChunks = SourceCurriculumEngine.retrieveRelevantChunks(
      folder,
      '$clean ${wrongQuestionContext ?? ""}',
      activeLesson: activeLesson,
      topK: 4,
    );

    TutorMessage reply;
    if (gemini.config.isSignedIn && citedChunks.isNotEmpty) {
      try {
        reply = await gemini.askSocraticTutor(
          history: folder.tutorHistory.where((m) => m.text != clean).toList(),
          userMessage: clean,
          citedChunks: citedChunks,
          activeLesson: activeLesson,
          wrongQuestionContext: wrongQuestionContext,
          language: data.tutorLanguage,
        );
      } catch (_) {
        reply = SourceCurriculumEngine.respondOfflineSocratic(
          history: folder.tutorHistory,
          userMessage: clean,
          citedChunks: citedChunks,
          activeLesson: activeLesson,
          wrongQuestionContext: wrongQuestionContext,
          language: data.tutorLanguage,
        );
      }
    } else {
      reply = SourceCurriculumEngine.respondOfflineSocratic(
        history: folder.tutorHistory,
        userMessage: clean,
        citedChunks: citedChunks,
        activeLesson: activeLesson,
        wrongQuestionContext: wrongQuestionContext,
        language: data.tutorLanguage,
      );
    }

    folder.tutorHistory.add(reply);
    await save();
    return reply;
  }

  void clearTutorHistory() {
    folder.tutorHistory.clear();
    save();
  }

  // ===========================================================================
  // EXISTING IMPORT / BANK TOOLS (Preserved + Synced with Citations & LearnKata)
  // ===========================================================================
  Future<String> importPickedFiles({bool forceSheet = false, bool useGemini = false}) async {
    final files = await NativeBridge.pickFiles(allowMultiple: true);
    if (files.isEmpty) return '';

    busy = true;
    notifyListeners();
    var addedMcq = 0;
    var addedCases = 0;
    var addedFc = 0;
    final errors = <String>[];

    final existingFc = folder.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
    final existingQ = folder.questions.map((q) => McqParser.normalizeStem(q.stem)).toSet();

    try {
      for (final file in files) {
        final bytes = file.bytes;
        try {
          final text = await FileExtractor.extractText(file.name, bytes);
          final chunks = FileExtractor.parseTextIntoChunks(file.name, text);
          if (chunks.isNotEmpty) {
            folder.sources.add(SourceDocument(
              id: 'src_${DateTime.now().microsecondsSinceEpoch}',
              name: file.name,
              fileType: file.name.split('.').last.toLowerCase(),
              chunks: chunks,
            ));
          }

          if (useGemini) {
            final aiRes = await gemini.generateFromLecture(data, text, sourceName: file.name);
            for (final q in aiRes.questions) {
              final k = McqParser.normalizeStem(q.stem);
              if (k.isNotEmpty && existingQ.add(k)) {
                q.sourceCitation = file.name;
                folder.questions.add(q);
                addedMcq++;
              }
            }
            for (final fc in aiRes.flashcards) {
              final k = McqParser.normalizeStem(fc.front);
              if (k.isNotEmpty && existingFc.add(k)) {
                folder.flashcards.add(FlashcardItem(
                  uid: data.nextCardUid++,
                  front: fc.front,
                  back: fc.back,
                  hint: fc.hint,
                  topic: fc.topic,
                  sourceCitation: file.name,
                ));
                addedFc++;
              }
            }
            continue;
          }

          final bundle = McqParser.parseBundle(data, text, sourceName: file.name);
          final isDocSheet = RegExp(r'\.(pdf|pptx|ppsx|potx|docx)$', caseSensitive: false).hasMatch(file.name);

          if (bundle.questions.isNotEmpty) {
            folder.questions.addAll(bundle.questions);
            folder.cases.addAll(bundle.cases);
            addedMcq += bundle.questions.length;
            addedCases += bundle.cases.length;
          }

          if (forceSheet || (isDocSheet && bundle.questions.isEmpty)) {
            final gen = LectureAnalyzer.analyze(data, text, sourceName: file.name);
            for (final fc in gen.flashcards) {
              final k = McqParser.normalizeStem(fc.front);
              if (k.isNotEmpty && existingFc.add(k)) {
                folder.flashcards.add(FlashcardItem(
                  uid: data.nextCardUid++,
                  front: fc.front,
                  back: fc.back,
                  hint: fc.hint,
                  topic: fc.topic,
                  sourceCitation: file.name,
                ));
                addedFc++;
              }
            }
            if (bundle.questions.isEmpty) {
              for (final q in gen.questions) {
                final k = McqParser.normalizeStem(q.stem);
                if (k.isNotEmpty && existingQ.add(k)) {
                  q.sourceCitation = file.name;
                  folder.questions.add(q);
                  addedMcq++;
                }
              }
            } else {
              addedFc += convertMcqsToFlashcards(bundle.questions);
            }
            // Also populate LearnKata micro-lessons automatically from the extracted sheet!
            if (chunks.isNotEmpty) {
              final newLessons = SourceCurriculumEngine.buildOfflineMicroLessons(
                data,
                chunks,
                rawText: text,
                sourceName: file.name,
              );
              for (var li = 0; li < newLessons.length; li++) {
                newLessons[li].orderIndex = folder.lessons.length + li;
              }
              folder.lessons.addAll(newLessons);
            }
          }
        } catch (e) {
          errors.add('${file.name}: $e');
        }
      }
    } finally {
      busy = false;
    }

    if (addedMcq > 0 || addedCases > 0 || addedFc > 0 || folder.lessons.isNotEmpty) {
      playSound('correct');
      await save();
      final parts = <String>[];
      if (addedMcq > 0) parts.add('$addedMcq سؤال MCQ');
      if (addedCases > 0) parts.add('$addedCases حالة');
      if (addedFc > 0) parts.add('$addedFc فلاش كارد');
      return '✨ تم استخراج ${parts.isNotEmpty ? parts.join(' + ') : "المحتوى"} في "${folder.name}"!';
    }
    notifyListeners();
    if (errors.isNotEmpty) throw Exception(errors.join('\n'));
    return 'لم يتم العثور على أسئلة أو مفاهيم نصية كافية داخل الملف.';
  }

  Future<String> importPastedText(String rawText, {bool useGemini = false, bool append = true}) async {
    busy = true;
    notifyListeners();
    try {
      if (useGemini) {
        final aiRes = await gemini.generateFromLecture(data, rawText, sourceName: folder.name);
        final existingFc = folder.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
        final existingQ = folder.questions.map((q) => McqParser.normalizeStem(q.stem)).toSet();
        var addedQ = 0;
        var addedFc = 0;
        for (final q in aiRes.questions) {
          if (existingQ.add(McqParser.normalizeStem(q.stem))) {
            folder.questions.add(q);
            addedQ++;
          }
        }
        for (final fc in aiRes.flashcards) {
          if (existingFc.add(McqParser.normalizeStem(fc.front))) {
            folder.flashcards.add(FlashcardItem(
              uid: data.nextCardUid++,
              front: fc.front,
              back: fc.back,
              hint: fc.hint,
              topic: fc.topic,
            ));
            addedFc++;
          }
        }
        await save();
        playSound('correct');
        return '✨ استخرج Gemini $addedQ سؤال MCQ + $addedFc فلاش كارد!';
      }

      final bundle = McqParser.parseBundle(data, rawText, sourceName: 'نص ملصوق');
      if (bundle.questions.isEmpty) {
        throw Exception('تعذر استخراج أسئلة MCQ. تأكد من كتابة الخيارات مثل A: أو أ.');
      }
      if (!append) {
        folder.questions = bundle.questions;
        folder.cases = bundle.cases;
      } else {
        folder.questions.addAll(bundle.questions);
        folder.cases.addAll(bundle.cases);
      }
      await save();
      playSound('correct');
      return 'تم إضافة ${bundle.questions.length} سؤال في "${folder.name}" ✅';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  int convertMcqsToFlashcards(List<McqQuestion> source, {bool includeOpts = false}) {
    final existing = folder.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
    var added = 0;
    for (final q in source) {
      if (q.hasIssue) continue;
      final front = includeOpts
          ? '${q.stem}\n\n${[for (var i = 0; i < q.options.length; i++) "${kMcqLetters[i]}) ${q.options[i]}"].join("\n")}'
          : q.stem;
      final fk = McqParser.normalizeStem(front);
      if (fk.isEmpty || !existing.add(fk)) continue;
      final ansTxt = q.getCorrectIndices().map((i) => '${kMcqLetters[i]}: ${q.options[i]}').join(' | ');
      final back = q.explanation.isNotEmpty ? '$ansTxt\n\n💡 ${q.explanation}' : ansTxt;
      folder.flashcards.add(FlashcardItem(
        uid: data.nextCardUid++,
        front: front,
        back: back,
        hint: q.topic,
        topic: q.topic,
        sourceCitation: q.sourceCitation,
      ));
      added++;
    }
    save();
    return added;
  }

  int removeDuplicates() {
    final seen = <String>{};
    final kept = <McqQuestion>[];
    var removed = 0;
    for (final q in folder.questions) {
      final k = McqParser.normalizeStem(q.stem);
      if (k.isNotEmpty && !seen.add(k)) {
        removed++;
      } else {
        kept.add(q);
      }
    }
    folder.questions = kept;
    save();
    return removed;
  }

  void launchCustomQuiz(List<McqQuestion> items, {String? studyUnitKey}) {
    pendingQuizItems = items;
    pendingQuizUnitKey = studyUnitKey;
    currentTabIndex = 2;
    notifyListeners();
  }

  Future<String> restoreBackupJson(String jsonStr, {bool merge = true}) async {
    final parsed = jsonDecode(jsonStr);
    final payload = (parsed is Map && parsed['data'] is Map) ? parsed['data'] as Map<String, dynamic> : parsed as Map<String, dynamic>;
    final incoming = AppDataState.fromJson(payload);
    if (!merge) {
      data = incoming;
    } else {
      for (final f in incoming.folders) {
        final match = data.folders.where((x) => x.name == f.name).toList();
        if (match.isEmpty) {
          f.id = 'f${data.nextFolderId++}';
          data.folders.add(f);
        } else {
          final target = match.first;
          final existingQ = target.questions.map((q) => McqParser.normalizeStem(q.stem)).toSet();
          for (final q in f.questions) {
            if (existingQ.add(McqParser.normalizeStem(q.stem))) {
              q.uid = data.nextUid++;
              target.questions.add(q);
            }
          }
          final existingFc = target.flashcards.map((c) => McqParser.normalizeStem(c.front)).toSet();
          for (final c in f.flashcards) {
            if (existingFc.add(McqParser.normalizeStem(c.front))) {
              c.uid = data.nextCardUid++;
              target.flashcards.add(c);
            }
          }
        }
      }
    }
    await save();
    return 'تمت استعادة النسخة الاحتياطية بنجاح (${data.folders.length} مجلد) ♻️';
  }
}
