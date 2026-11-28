import 'dart:math';
import '../models/models.dart';
import 'file_extractor.dart';
import 'gemini_oauth_service.dart';
import 'lecture_analyzer.dart';
import 'mcq_parser.dart';

class IngestResult {
  final SourceDocument document;
  final List<MicroLesson> lessons;
  final List<McqQuestion> bankQuestions;
  final List<FlashcardItem> flashcards;
  final bool usedAi;

  IngestResult({
    required this.document,
    required this.lessons,
    required this.bankQuestions,
    required this.flashcards,
    required this.usedAi,
  });
}

class SourceCurriculumEngine {
  static Future<IngestResult> ingestSource({
    required AppDataState appState,
    required GeminiOAuthService gemini,
    required String sourceName,
    required String rawText,
    String fileType = 'text',
    bool preferGemini = true,
    int startingOrderIndex = 0,
  }) async {
    final chunks = FileExtractor.parseTextIntoChunks(sourceName, rawText);
    final doc = SourceDocument(
      id: 'src_${DateTime.now().microsecondsSinceEpoch}',
      name: sourceName,
      fileType: fileType,
      chunks: chunks,
    );

    List<MicroLesson> lessons = [];
    var usedAi = false;

    if (preferGemini && gemini.config.isSignedIn && chunks.isNotEmpty) {
      try {
        lessons = await gemini.generateMicroCurriculum(
          appState,
          chunks,
          sourceName: sourceName,
          language: appState.tutorLanguage,
        );
        usedAi = lessons.isNotEmpty;
      } catch (_) {
        lessons = [];
      }
    }

    if (lessons.isEmpty) {
      lessons = buildOfflineMicroLessons(
        appState,
        chunks,
        rawText: rawText,
        sourceName: sourceName,
      );
    }

    for (var i = 0; i < lessons.length; i++) {
      lessons[i].orderIndex = startingOrderIndex + i;
    }

    // Also mirror generated MCQs & flashcards into the main folder bank so Quiz/Flashcard tabs stay synced
    final bankQs = <McqQuestion>[];
    final bankFcs = <FlashcardItem>[];
    for (final lesson in lessons) {
      for (final q in lesson.quizzes) {
        if (q.sourceCitation.isEmpty) q.sourceCitation = lesson.sourceCitation;
        bankQs.add(q);
      }
      for (final fc in lesson.flashcards) {
        if (fc.sourceCitation.isEmpty) fc.sourceCitation = lesson.sourceCitation;
        bankFcs.add(fc);
      }
    }

    return IngestResult(
      document: doc,
      lessons: lessons,
      bankQuestions: bankQs,
      flashcards: bankFcs,
      usedAi: usedAi,
    );
  }

  static List<MicroLesson> buildOfflineMicroLessons(
    AppDataState appState,
    List<SourceChunk> chunks, {
    required String rawText,
    required String sourceName,
  }) {
    final rng = Random();
    final filteredChunks = chunks.where((c) {
      final low = c.sectionTitle.toLowerCase();
      if (low.contains('reference') || low.contains('thank you') || low == 'outline') return false;
      return c.text.length >= 35;
    }).toList();

    final workChunks = filteredChunks.isNotEmpty ? filteredChunks : chunks;
    if (workChunks.isEmpty) return [];

    // Group chunks cleanly into 4..8 bite-sized MicroLessons
    final groupSize = workChunks.length <= 5 ? 1 : (workChunks.length <= 12 ? 2 : 3);
    final lessons = <MicroLesson>[];

    // Global pool across source for plausible distractors & matching games
    final globalDraft = LectureAnalyzer.analyze(appState, rawText, sourceName: sourceName);

    for (var i = 0; i < workChunks.length; i += groupSize) {
      final slice = workChunks.sublist(i, min(i + groupSize, workChunks.length));
      final combinedText = slice.map((c) => '# Slide 1: ${c.sectionTitle}\n${c.text}').join('\n\n');
      final citation = slice.length == 1
          ? slice.first.citation
          : '${slice.first.citation} — ${slice.last.citation.split('•').last.trim()}';
      final firstTitle = slice.first.sectionTitle.replaceAll(RegExp(r'^Slide\s*\d+\s*:\s*', caseSensitive: false), '').trim();
      final topic = firstTitle.isNotEmpty ? firstTitle : sourceName;

      final analyzed = LectureAnalyzer.analyze(appState, combinedText, sourceName: sourceName);
      final parsedBundle = McqParser.parseBundle(appState, combinedText, sourceName: sourceName);

      // Extract clean summary & takeaways from lines
      final lines = slice
          .expand((c) => c.text.split('\n'))
          .map((l) => l.replaceFirst(RegExp(r'^[•●▪▸\-\*]+\s*'), '').trim())
          .where((l) => l.length >= 16 && !RegExp(r'^\d+$').hasMatch(l))
          .toList();

      final summaryLines = lines.take(4).toList();
      final summary = summaryLines.isNotEmpty
          ? summaryLines.join(' ')
          : slice.map((e) => e.text).join(' ').trim();
      final takeaways = lines.skip(1).take(4).toList();
      if (takeaways.isEmpty && lines.isNotEmpty) takeaways.add(lines.first);

      // Flashcards
      final fcs = <FlashcardItem>[];
      for (final fc in analyzed.flashcards.take(5)) {
        fcs.add(FlashcardItem(
          uid: appState.nextCardUid++,
          front: fc.front,
          back: fc.back,
          hint: fc.topic,
          topic: topic,
          sourceCitation: citation,
        ));
      }
      if (fcs.isEmpty && lines.length >= 2) {
        fcs.add(FlashcardItem(
          uid: appState.nextCardUid++,
          front: 'What are the core takeaways of $topic?',
          back: takeaways.map((e) => '• $e').join('\n'),
          hint: citation,
          topic: topic,
          sourceCitation: citation,
        ));
      }

      // Concept Check MCQs WITH per-option feedback & citations
      final lessonQs = <McqQuestion>[];
      final candQs = [...parsedBundle.questions, ...analyzed.questions];
      if (candQs.isEmpty) {
        candQs.addAll(globalDraft.questions.where((q) => McqParser.normalizeStem(q.topic) == McqParser.normalizeStem(topic)));
      }
      for (final q in candQs.take(4)) {
        q.topic = topic;
        q.sourceCitation = citation;
        q.optionRationales = _buildOptionRationales(q, citation);
        lessonQs.add(q);
      }

      // Ensure every MicroLesson has at least 1 grounded Concept Check MCQ
      if (lessonQs.isEmpty && lines.length >= 2) {
        final correctStmt = lines.firstWhere((l) => l.length >= 20 && l.length <= 140, orElse: () => lines.first);
        final otherLines = globalDraft.flashcards
            .where((f) => f.topic != topic && f.back.length >= 18 && f.back.length <= 130)
            .map((f) => f.back)
            .toList()
          ..shuffle(rng);
        final opts = [
          correctStmt,
          ...otherLines.take(3),
        ];
        while (opts.length < 4) {
          opts.add('Unrelated mechanism outside $topic (${opts.length})');
        }
        final q = McqParser.buildQuestion(
          appState,
          sourceNum: lessonQs.length + 1,
          sourceName: sourceName,
          stem: 'Based on [$citation], which statement accurately describes "$topic"?',
          options: opts,
          answerIndices: [0],
          explicitTopic: topic,
          explanation: 'Grounded in $citation: $correctStmt',
        );
        final shuffledOrder = [0, 1, 2, 3]..shuffle(rng);
        final newOpts = [for (final idx in shuffledOrder) opts[idx]];
        final newAns = shuffledOrder.indexOf(0);
        q.options = newOpts;
        q.setCorrectIndices([newAns]);
        q.sourceCitation = citation;
        q.optionRationales = _buildOptionRationales(q, citation);
        lessonQs.add(q);
      }

      // Matching Pairs Game
      final pairs = <MatchPairItem>[];
      for (var fi = 0; fi < fcs.length && pairs.length < 4; fi++) {
        final fc = fcs[fi];
        if (fc.front.length <= 60 && fc.back.length <= 140) {
          pairs.add(MatchPairItem(
            id: 'mp_${lessons.length}_$fi',
            left: fc.front,
            right: fc.back.replaceAll('\n', ' • '),
            citation: citation,
          ));
        }
      }
      if (pairs.length < 2) {
        for (final gfc in globalDraft.flashcards) {
          if (pairs.length >= 4) break;
          if (gfc.front.length <= 60 && gfc.back.length <= 140 && !pairs.any((p) => p.left == gfc.front)) {
            pairs.add(MatchPairItem(
              id: 'mp_${lessons.length}_${pairs.length}',
              left: gfc.front,
              right: gfc.back.replaceAll('\n', ' • '),
              citation: citation,
            ));
          }
        }
      }

      // Fill-in-the-Blank Exercise
      final blanks = _buildFillBlanksFromLines(lines, fcs, topic, citation, rng);

      lessons.add(MicroLesson(
        id: 'ml_${DateTime.now().microsecondsSinceEpoch}_${lessons.length}',
        orderIndex: lessons.length,
        title: firstTitle.isNotEmpty ? firstTitle : 'Module ${lessons.length + 1}',
        topic: topic,
        objective: 'Understand & recall key concepts of $topic accurately.',
        summary: summary.length > 440 ? '${summary.substring(0, 437)}...' : summary,
        keyTakeaways: takeaways,
        sourceCitation: citation,
        sourceExcerpt: slice.map((c) => '[${c.citation}]\n${c.text}').join('\n\n'),
        estimatedMinutes: max(3, min(7, (lines.length / 2).ceil() + 2)),
        quizzes: lessonQs,
        flashcards: fcs,
        matchPairs: pairs,
        fillBlanks: blanks,
      ));
    }

    return lessons;
  }

  static List<String> _buildOptionRationales(McqQuestion q, String citation) {
    final correctSet = q.getCorrectIndices().toSet();
    final out = <String>[];
    for (var i = 0; i < q.options.length; i++) {
      if (correctSet.contains(i)) {
        out.add('✅ صحيح وفقاً للمصدر [$citation]: ${q.explanation.isNotEmpty ? q.explanation : q.options[i]}');
      } else {
        out.add('❌ غير دقيق: هذا الخيار لا يطابق آلية "${q.topic}" المذكورة في [$citation].');
      }
    }
    return out;
  }

  static List<FillBlankItem> _buildFillBlanksFromLines(
    List<String> lines,
    List<FlashcardItem> fcs,
    String topic,
    String citation,
    Random rng,
  ) {
    final blanks = <FillBlankItem>[];
    final wordPool = <String>{};
    for (final fc in fcs) {
      if (fc.front.length >= 4 && fc.front.length <= 28 && !fc.front.contains('?')) {
        wordPool.add(fc.front);
      }
    }

    // Build blanks from key-value / definition lines
    for (final line in lines) {
      if (blanks.length >= 2) break;
      final m = RegExp(r'^([^:–—]{3,28}?)\s*(?::|—|–|is|are|causes|inhibits)\s+(.{16,120})$', caseSensitive: false).firstMatch(line);
      if (m != null) {
        final term = m.group(1)!.trim();
        if (term.split(' ').length <= 3 && !term.toLowerCase().startsWith('this')) {
          wordPool.add(term);
          final distractorList = wordPool.where((w) => w.toLowerCase() != term.toLowerCase()).toList()..shuffle(rng);
          final choices = <String>[term, ...distractorList.take(3)];
          final fallbackTerms = ['Insulin resistance', 'SGLT2 reabsorption', 'Glucagon excess', 'Ketoacidosis', 'Glycation (AGEs)'];
          for (final ft in fallbackTerms) {
            if (choices.length >= 4) break;
            if (!choices.any((c) => c.toLowerCase() == ft.toLowerCase())) choices.add(ft);
          }
          choices.shuffle(rng);
          blanks.add(FillBlankItem(
            id: 'fb_${blanks.length}_${term.hashCode}',
            sentenceWithBlank: line.replaceFirst(term, '_____'),
            answer: term,
            choices: choices,
            hint: 'تذكّر مفهوم ($topic) المذكور في [$citation]',
            citation: citation,
          ));
        }
      }
    }
    return blanks;
  }

  /// Build MicroLessons from an existing MCQ question bank (so even raw MCQ folders work in LearnKata player!)
  static List<MicroLesson> buildFromRawQuestions(SubjectFolder folder, {int unitSize = 6}) {
    final byTopic = <String, List<McqQuestion>>{};
    for (final q in folder.questions.where((x) => !x.hasIssue)) {
      byTopic.putIfAbsent(q.topic, () => []).add(q);
    }
    final lessons = <MicroLesson>[];
    byTopic.forEach((topic, qs) {
      for (var i = 0; i < qs.length; i += unitSize) {
        final slice = qs.sublist(i, min(i + unitSize, qs.length));
        for (final q in slice) {
          if (q.optionRationales.isEmpty) {
            q.optionRationales = _buildOptionRationales(q, q.sourceCitation.isNotEmpty ? q.sourceCitation : folder.name);
          }
        }
        final matchingFcs = folder.flashcards
            .where((fc) => McqParser.normalizeStem(fc.topic) == McqParser.normalizeStem(topic))
            .take(5)
            .toList();
        final pairs = matchingFcs
            .where((fc) => fc.front.length <= 55 && fc.back.length <= 130)
            .take(4)
            .map((fc) => MatchPairItem(id: 'mp_${fc.uid}', left: fc.front, right: fc.back.replaceAll('\n', ' '), citation: topic))
            .toList();
        lessons.add(MicroLesson(
          id: 'raw_${folder.id}_${lessons.length}',
          orderIndex: lessons.length,
          title: qs.length > unitSize ? '$topic (Part ${(i ~/ unitSize) + 1})' : topic,
          topic: topic,
          objective: 'Master key clinical questions on $topic',
          summary: slice.map((q) => q.explanation.isNotEmpty ? q.explanation : q.stem).take(3).join(' • '),
          keyTakeaways: [
            for (final q in slice.take(3))
              q.getCorrectIndices().isNotEmpty
                  ? '${q.options[q.getCorrectIndices().first]} — ${q.explanation.isNotEmpty ? q.explanation : q.topic}'
                  : q.stem,
          ],
          sourceCitation: '${folder.name} • $topic',
          sourceExcerpt: slice.map((q) => '${q.stem}\nAnswer: ${q.getCorrectIndices().map((ix) => q.options[ix]).join(", ")}').join('\n\n'),
          estimatedMinutes: max(3, slice.length),
          quizzes: slice,
          flashcards: matchingFcs,
          matchPairs: pairs,
          fillBlanks: const [],
        ));
      }
    });
    return lessons;
  }

  /// Lightweight keyword + bigram retriever grounding Socratic responses strictly in uploaded chunks.
  static List<SourceChunk> retrieveRelevantChunks(
    SubjectFolder folder,
    String query, {
    MicroLesson? activeLesson,
    int topK = 4,
  }) {
    final all = folder.allChunks;
    if (all.isEmpty && activeLesson != null) {
      return [
        SourceChunk(
          id: 'lesson_src',
          sourceName: folder.name,
          citation: activeLesson.sourceCitation.isNotEmpty ? activeLesson.sourceCitation : activeLesson.title,
          sectionTitle: activeLesson.title,
          text: activeLesson.sourceExcerpt.isNotEmpty ? activeLesson.sourceExcerpt : activeLesson.summary,
        ),
      ];
    }
    if (all.isEmpty) return [];

    final qTokens = _tokenize('$query ${activeLesson?.topic ?? ""} ${activeLesson?.title ?? ""}');
    final scored = <MapEntry<SourceChunk, double>>[];
    for (final c in all) {
      var score = 0.0;
      final cTokens = _tokenize('${c.sectionTitle} ${c.text}');
      for (final tok in qTokens) {
        if (cTokens.contains(tok)) score += 2.0;
      }
      if (activeLesson != null && (c.citation == activeLesson.sourceCitation || c.sectionTitle == activeLesson.title)) {
        score += 5.5;
      }
      scored.add(MapEntry(c, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(topK).map((e) => e.key).toList();
  }

  static Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();
  }

  /// Offline Socratic Tutor fallback — still NEVER spoils the answer on turn 1; guides with source-cited hints + questions!
  static TutorMessage respondOfflineSocratic({
    required List<TutorMessage> history,
    required String userMessage,
    required List<SourceChunk> citedChunks,
    MicroLesson? activeLesson,
    String? wrongQuestionContext,
    String language = 'bilingual',
  }) {
    final top = citedChunks.isNotEmpty ? citedChunks.first : null;
    final citeList = citedChunks.take(2).map((c) => c.citation).toList();
    final isEnglishOnly = language == 'en';
    final turnsSoFar = history.where((m) => m.role == 'user').length;

    final snippetLines = (top?.text ?? activeLesson?.summary ?? '')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.length >= 15)
        .toList();
    final clueLine = snippetLines.isNotEmpty ? snippetLines.first : (activeLesson?.objective ?? '');

    if (wrongQuestionContext != null && wrongQuestionContext.isNotEmpty && turnsSoFar == 0) {
      final msg = isEnglishOnly
          ? 'Great effort trying that question! Before revealing the answer, let us reason together from [${top?.citation ?? "the source"}].\n\n'
              '💡 Guiding Hint: Look closely at this key mechanism from your notes:\n"${_maskKeywords(clueLine)}"\n\n'
              '❓ Leading Question: What physiological step or clinical feature links that clue to the question?'
          : 'محاولة ممتازة! دعنا لا نستعجل الإجابة النهائية، بل نصل إليها معاً خطوة بخطوة من [${top?.citation ?? "المصدر"}].\n\n'
              '💡 تلميح موجّه: ركّز على هذه النقطة المذكورة في محاضرتك:\n«${_maskKeywords(clueLine)}»\n\n'
              '❓ سؤال تفكير: ما الآلية أو السبب الفسيولوجي الذي يربط هذا التلميح بالسؤال؟';
      return TutorMessage(
        role: 'tutor',
        text: msg,
        citations: citeList,
        suggestedPrompt: isEnglishOnly ? 'Give me a second step hint' : 'أعطني تلميحاً إضافياً لتقريب الفكرة',
      );
    }

    if (turnsSoFar <= 1) {
      final detail = snippetLines.length > 1 ? snippetLines[1] : clueLine;
      final msg = isEnglishOnly
          ? 'You are on the right track! Think of it step-by-step using [${top?.citation ?? "Source"}]:\n\n'
              '🔍 Key Anchor: "$detail"\n\n'
              '❓ Next Step: Based on that mechanism, which option/process matches — and why would the alternatives fail?'
          : 'ممتاز، أنت تقترب من الفكرة! لننظر للخطوة التالية في [${top?.citation ?? "المصدر"}]:\n\n'
              '🔍 المعلومة المرتكزة في النص:\n«$detail»\n\n'
              '❓ سؤال للمناقشة: بناءً على هذه الآلية، أيّ نتيجة تتوقع حدوثها ولماذا نستبعد البدائل الأخرى؟';
      return TutorMessage(
        role: 'tutor',
        text: msg,
        citations: citeList,
        suggestedPrompt: isEnglishOnly ? 'Let me verify my final conclusion' : 'أعتقد أن الفكرة هي... أكد لي بالمرجع',
      );
    }

    final exactSummary = snippetLines.take(3).join(' • ');
    final msg = isEnglishOnly
        ? 'Well reasoned! According strictly to [${top?.citation ?? "Source"}]:\n"$exactSummary"\n\n'
            'Ask me another concept or try the Concept Check quiz to test your mastery!'
        : 'أحسنت التفكير والربط! وبحسب النص الموثق في [${top?.citation ?? "المصدر"}]:\n«$exactSummary»\n\n'
            'جرّب الآن سؤال التحقق أو اسألني عن جزء آخر لنثبت المعلومة!';
    return TutorMessage(
      role: 'tutor',
      text: msg,
      citations: citeList,
      suggestedPrompt: isEnglishOnly ? 'Test me with a clinical scenario' : 'اختبر فهمي بسؤال تطبيقي آخر',
    );
  }

  static String _maskKeywords(String text) {
    if (text.length < 24) return text;
    final words = text.split(' ');
    if (words.length < 5) return text;
    final mid = words.length ~/ 2;
    words[mid] = '____';
    return words.join(' ');
  }

  /// Automatically builds a Targeted Weakness Review Session from all low-mastery topics!
  static MicroLesson? buildTargetedWeaknessLesson(SubjectFolder folder, {String? singleTopic}) {
    final weakTopics = <String>{};
    if (singleTopic != null && singleTopic.isNotEmpty) {
      weakTopics.add(singleTopic);
    } else {
      folder.topicMastery.forEach((t, stat) {
        if (stat.level == 'weak' || stat.masteryPct < 75) weakTopics.add(t);
      });
      if (weakTopics.isEmpty) {
        for (final q in folder.questions) {
          if (q.stats.wrong > 0 || q.isDue()) weakTopics.add(q.topic);
        }
      }
    }
    if (weakTopics.isEmpty) return null;

    final quizzes = <McqQuestion>[];
    final flashcards = <FlashcardItem>[];
    final pairs = <MatchPairItem>[];
    final blanks = <FillBlankItem>[];
    final takeaways = <String>[];
    final citations = <String>{};

    for (final l in folder.lessons) {
      if (!weakTopics.contains(l.topic)) continue;
      if (l.sourceCitation.isNotEmpty) citations.add(l.sourceCitation);
      takeaways.addAll(l.keyTakeaways.take(2));
      quizzes.addAll(l.quizzes);
      flashcards.addAll(l.flashcards);
      pairs.addAll(l.matchPairs);
      blanks.addAll(l.fillBlanks);
    }

    for (final q in folder.questions) {
      if (weakTopics.contains(q.topic) && !q.hasIssue && !quizzes.any((x) => x.uid == q.uid)) {
        quizzes.add(q);
      }
    }
    for (final fc in folder.flashcards) {
      if (weakTopics.contains(fc.topic) && !flashcards.any((x) => x.uid == fc.uid)) {
        flashcards.add(fc);
      }
    }

    if (quizzes.isEmpty && flashcards.isEmpty) return null;

    final titleLabel = singleTopic != null
        ? '🎯 تقوية: $singleTopic'
        : '🎯 جلسة تقوية نقاط الضعف (${weakTopics.length} مواضيع)';

    return MicroLesson(
      id: 'weak_review_${DateTime.now().microsecondsSinceEpoch}',
      orderIndex: 0,
      title: titleLabel,
      topic: singleTopic ?? weakTopics.first,
      objective: 'Targeted remediation across weak concepts: ${weakTopics.take(4).join(", ")}',
      summary: 'جلسة مراجعة ذكية مجمعة خصيصاً من المواضيع ذات الدقة المنخفضة لتعزيز الاسترجاع النشط قبل الانتقال للمراحل المتقدمة.',
      keyTakeaways: takeaways.take(5).toList(),
      sourceCitation: citations.isNotEmpty ? citations.take(3).join(' | ') : folder.name,
      sourceExcerpt: takeaways.take(4).join('\n'),
      estimatedMinutes: max(3, min(10, quizzes.length)),
      quizzes: quizzes.take(10).toList(),
      flashcards: flashcards.take(10).toList(),
      matchPairs: pairs.take(4).toList(),
      fillBlanks: blanks.take(3).toList(),
    );
  }
}
