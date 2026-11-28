import 'dart:convert';

const List<String> kMcqLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

const Map<String, String> kDiffLabels = {
  'easy': 'سهل',
  'medium': 'متوسط',
  'hard': 'صعب',
};

class SrsInfo {
  int wrongCount;
  int streak;
  int intervalDays;
  int dueAt;
  int lastReviewedAt;
  String lastResult;
  bool mastered;

  SrsInfo({
    this.wrongCount = 0,
    this.streak = 0,
    this.intervalDays = 1,
    this.dueAt = 0,
    this.lastReviewedAt = 0,
    this.lastResult = '',
    this.mastered = false,
  });

  factory SrsInfo.fromJson(Map<String, dynamic> j) => SrsInfo(
        wrongCount: (j['wrongCount'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 1,
        dueAt: (j['dueAt'] as num?)?.toInt() ?? 0,
        lastReviewedAt: (j['lastReviewedAt'] as num?)?.toInt() ?? 0,
        lastResult: j['lastResult']?.toString() ?? '',
        mastered: j['mastered'] == true,
      );

  Map<String, dynamic> toJson() => {
        'wrongCount': wrongCount,
        'streak': streak,
        'intervalDays': intervalDays,
        'dueAt': dueAt,
        'lastReviewedAt': lastReviewedAt,
        'lastResult': lastResult,
        'mastered': mastered,
      };
}

class QuestionStats {
  int attempts;
  int correct;
  int wrong;

  QuestionStats({this.attempts = 0, this.correct = 0, this.wrong = 0});

  factory QuestionStats.fromJson(Map<String, dynamic> j) => QuestionStats(
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        wrong: (j['wrong'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'correct': correct,
        'wrong': wrong,
      };
}

class McqQuestion {
  int uid;
  int sourceNum;
  String sourceName;
  String sourceCitation;
  String stem;
  List<String> options;
  List<String> optionRationales;
  List<int> answerIndices;
  int answerIndex;
  bool isMulti;
  String? caseId;
  String difficulty;
  String topic;
  String explanation;
  SrsInfo? srs;
  QuestionStats stats;

  McqQuestion({
    required this.uid,
    this.sourceNum = 0,
    this.sourceName = 'ملف',
    this.sourceCitation = '',
    required this.stem,
    required this.options,
    List<String>? optionRationales,
    required this.answerIndices,
    this.answerIndex = -1,
    this.isMulti = false,
    this.caseId,
    this.difficulty = 'medium',
    this.topic = 'General Medicine',
    this.explanation = '',
    this.srs,
    QuestionStats? stats,
  })  : optionRationales = optionRationales ?? const [],
        stats = stats ?? QuestionStats();

  bool get hasIssue => options.length < 2 || getCorrectIndices().isEmpty;
  bool get isMultiAnswer => getCorrectIndices().length > 1 || isMulti;

  List<int> getCorrectIndices() {
    final len = options.length;
    if (answerIndices.isNotEmpty) {
      final clean = answerIndices.where((i) => i >= 0 && i < len).toSet().toList()..sort();
      return clean;
    }
    if (answerIndex >= 0 && answerIndex < len) {
      return [answerIndex];
    }
    return [];
  }

  void setCorrectIndices(List<int> arr, {bool keepMultiFlag = false}) {
    final clean = arr.where((i) => i >= 0 && i < options.length).toSet().toList()..sort();
    answerIndices = clean;
    answerIndex = clean.isNotEmpty ? clean.first : -1;
    isMulti = clean.length > 1 || (keepMultiFlag && isMulti);
  }

  bool isUserAnswerCorrect(List<int> userIndices) {
    final exp = getCorrectIndices();
    final got = userIndices.toSet().toList()..sort();
    if (exp.isEmpty || got.isEmpty || exp.length != got.length) return false;
    for (var i = 0; i < exp.length; i++) {
      if (exp[i] != got[i]) return false;
    }
    return true;
  }

  bool isDue([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final s = srs;
    return s != null && s.wrongCount > 0 && !s.mastered && s.dueAt > 0 && s.dueAt <= now;
  }

  void recordOutcome(bool isOk, [int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    const dayMs = 86400000;
    stats.attempts++;
    if (isOk) {
      stats.correct++;
      final s = srs;
      if (s != null && s.wrongCount > 0 && !s.mastered) {
        s.streak += 1;
        s.lastReviewedAt = now;
        s.lastResult = 'ok';
        if (s.streak == 1) {
          s.intervalDays = 3;
          s.dueAt = now + 3 * dayMs;
        } else if (s.streak == 2) {
          s.intervalDays = 7;
          s.dueAt = now + 7 * dayMs;
        } else {
          s.intervalDays = 0;
          s.dueAt = 0;
          s.mastered = true;
        }
      }
    } else {
      stats.wrong++;
      srs = SrsInfo(
        wrongCount: (srs?.wrongCount ?? 0) + 1,
        streak: 0,
        intervalDays: 1,
        dueAt: now + dayMs,
        lastReviewedAt: now,
        lastResult: 'wrong',
        mastered: false,
      );
    }
  }

  factory McqQuestion.fromJson(Map<String, dynamic> j) {
    final opts = (j['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rats = (j['optionRationales'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    var ansArr = (j['answerIndices'] as List?)
            ?.map((e) => (e as num).toInt())
            .where((i) => i >= 0 && i < opts.length)
            .toList() ??
        [];
    final single = (j['answerIndex'] as num?)?.toInt() ?? -1;
    if (ansArr.isEmpty && single >= 0 && single < opts.length) {
      ansArr = [single];
    }
    final diff = j['difficulty']?.toString() ?? 'medium';
    return McqQuestion(
      uid: (j['uid'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch,
      sourceNum: (j['sourceNum'] as num?)?.toInt() ?? 0,
      sourceName: j['sourceName']?.toString() ?? 'ملف',
      sourceCitation: j['sourceCitation']?.toString() ?? '',
      stem: j['stem']?.toString() ?? '',
      options: opts,
      optionRationales: rats,
      answerIndices: ansArr,
      answerIndex: ansArr.isNotEmpty ? ansArr.first : -1,
      isMulti: j['isMulti'] == true || ansArr.length > 1,
      caseId: j['caseId']?.toString(),
      difficulty: kDiffLabels.containsKey(diff) ? diff : 'medium',
      topic: j['topic']?.toString() ?? 'General Medicine',
      explanation: j['explanation']?.toString() ?? '',
      srs: j['srs'] is Map<String, dynamic> ? SrsInfo.fromJson(j['srs']) : null,
      stats: j['stats'] is Map<String, dynamic> ? QuestionStats.fromJson(j['stats']) : QuestionStats(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'sourceNum': sourceNum,
        'sourceName': sourceName,
        'sourceCitation': sourceCitation,
        'stem': stem,
        'options': options,
        'optionRationales': optionRationales,
        'answerIndices': answerIndices,
        'answerIndex': answerIndex,
        'isMulti': isMulti,
        'caseId': caseId,
        'difficulty': difficulty,
        'topic': topic,
        'explanation': explanation,
        'srs': srs?.toJson(),
        'stats': stats.toJson(),
      };
}

class ClinicalCase {
  String id;
  String title;
  String vignette;
  String topic;

  ClinicalCase({
    required this.id,
    required this.title,
    required this.vignette,
    this.topic = '',
  });

  factory ClinicalCase.fromJson(Map<String, dynamic> j) => ClinicalCase(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? 'حالة سريرية',
        vignette: j['vignette']?.toString() ?? '',
        topic: j['topic']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'vignette': vignette,
        'topic': topic,
      };
}

class FlashcardItem {
  int uid;
  String front;
  String back;
  String hint;
  String topic;
  String sourceCitation;
  String status; // learning | review | mastered
  bool starred;
  int createdAt;

  FlashcardItem({
    required this.uid,
    required this.front,
    required this.back,
    this.hint = '',
    this.topic = '',
    this.sourceCitation = '',
    this.status = 'learning',
    this.starred = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory FlashcardItem.fromJson(Map<String, dynamic> j) => FlashcardItem(
        uid: (j['uid'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch,
        front: j['front']?.toString() ?? '',
        back: j['back']?.toString() ?? '',
        hint: j['hint']?.toString() ?? '',
        topic: j['topic']?.toString() ?? '',
        sourceCitation: j['sourceCitation']?.toString() ?? '',
        status: j['status']?.toString() ?? 'learning',
        starred: j['starred'] == true,
        createdAt: (j['createdAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'front': front,
        'back': back,
        'hint': hint,
        'topic': topic,
        'sourceCitation': sourceCitation,
        'status': status,
        'starred': starred,
        'createdAt': createdAt,
      };
}

// ============================================================================
// LEARNKATA-INSPIRED PEDAGOGICAL MODELS (Sources, MicroLessons, Games, Mastery)
// ============================================================================

class SourceChunk {
  String id;
  String sourceName;
  String citation; // e.g., "Lecture.pdf • Page 3" or "Deck.pptx • Slide 5"
  String sectionTitle;
  String text;

  SourceChunk({
    required this.id,
    required this.sourceName,
    required this.citation,
    required this.sectionTitle,
    required this.text,
  });

  factory SourceChunk.fromJson(Map<String, dynamic> j) => SourceChunk(
        id: j['id']?.toString() ?? '',
        sourceName: j['sourceName']?.toString() ?? '',
        citation: j['citation']?.toString() ?? '',
        sectionTitle: j['sectionTitle']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceName': sourceName,
        'citation': citation,
        'sectionTitle': sectionTitle,
        'text': text,
      };
}

class SourceDocument {
  String id;
  String name;
  String fileType;
  int uploadedAtMs;
  List<SourceChunk> chunks;

  SourceDocument({
    required this.id,
    required this.name,
    this.fileType = 'text',
    int? uploadedAtMs,
    List<SourceChunk>? chunks,
  })  : uploadedAtMs = uploadedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        chunks = chunks ?? [];

  factory SourceDocument.fromJson(Map<String, dynamic> j) => SourceDocument(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Source',
        fileType: j['fileType']?.toString() ?? 'text',
        uploadedAtMs: (j['uploadedAtMs'] as num?)?.toInt(),
        chunks: (j['chunks'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(SourceChunk.fromJson)
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileType': fileType,
        'uploadedAtMs': uploadedAtMs,
        'chunks': chunks.map((e) => e.toJson()).toList(),
      };
}

class MatchPairItem {
  String id;
  String left;
  String right;
  String citation;

  MatchPairItem({
    required this.id,
    required this.left,
    required this.right,
    this.citation = '',
  });

  factory MatchPairItem.fromJson(Map<String, dynamic> j) => MatchPairItem(
        id: j['id']?.toString() ?? '',
        left: j['left']?.toString() ?? '',
        right: j['right']?.toString() ?? '',
        citation: j['citation']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'left': left,
        'right': right,
        'citation': citation,
      };
}

class FillBlankItem {
  String id;
  String sentenceWithBlank; // uses "_____"
  String answer;
  List<String> choices; // clickable chips including answer
  String hint;
  String citation;

  FillBlankItem({
    required this.id,
    required this.sentenceWithBlank,
    required this.answer,
    required this.choices,
    this.hint = '',
    this.citation = '',
  });

  factory FillBlankItem.fromJson(Map<String, dynamic> j) => FillBlankItem(
        id: j['id']?.toString() ?? '',
        sentenceWithBlank: j['sentenceWithBlank']?.toString() ?? '',
        answer: j['answer']?.toString() ?? '',
        choices: (j['choices'] as List?)?.map((e) => e.toString()).toList() ?? [],
        hint: j['hint']?.toString() ?? '',
        citation: j['citation']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sentenceWithBlank': sentenceWithBlank,
        'answer': answer,
        'choices': choices,
        'hint': hint,
        'citation': citation,
      };
}

class MicroLesson {
  String id;
  int orderIndex;
  String title;
  String topic;
  String objective;
  String summary;
  List<String> keyTakeaways;
  String sourceCitation;
  String sourceExcerpt;
  int estimatedMinutes;
  List<McqQuestion> quizzes;
  List<FlashcardItem> flashcards;
  List<MatchPairItem> matchPairs;
  List<FillBlankItem> fillBlanks;
  bool completed;
  int bestQuizPct;
  bool gameCompleted;
  int stars;

  MicroLesson({
    required this.id,
    required this.orderIndex,
    required this.title,
    required this.topic,
    required this.objective,
    required this.summary,
    List<String>? keyTakeaways,
    this.sourceCitation = '',
    this.sourceExcerpt = '',
    this.estimatedMinutes = 4,
    List<McqQuestion>? quizzes,
    List<FlashcardItem>? flashcards,
    List<MatchPairItem>? matchPairs,
    List<FillBlankItem>? fillBlanks,
    this.completed = false,
    this.bestQuizPct = 0,
    this.gameCompleted = false,
    this.stars = 0,
  })  : keyTakeaways = keyTakeaways ?? [],
        quizzes = quizzes ?? [],
        flashcards = flashcards ?? [],
        matchPairs = matchPairs ?? [],
        fillBlanks = fillBlanks ?? [];

  factory MicroLesson.fromJson(Map<String, dynamic> j) => MicroLesson(
        id: j['id']?.toString() ?? '',
        orderIndex: (j['orderIndex'] as num?)?.toInt() ?? 0,
        title: j['title']?.toString() ?? '',
        topic: j['topic']?.toString() ?? 'General',
        objective: j['objective']?.toString() ?? '',
        summary: j['summary']?.toString() ?? '',
        keyTakeaways: (j['keyTakeaways'] as List?)?.map((e) => e.toString()).toList() ?? [],
        sourceCitation: j['sourceCitation']?.toString() ?? '',
        sourceExcerpt: j['sourceExcerpt']?.toString() ?? '',
        estimatedMinutes: (j['estimatedMinutes'] as num?)?.toInt() ?? 4,
        quizzes: (j['quizzes'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(McqQuestion.fromJson)
                .toList() ??
            [],
        flashcards: (j['flashcards'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(FlashcardItem.fromJson)
                .toList() ??
            [],
        matchPairs: (j['matchPairs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(MatchPairItem.fromJson)
                .toList() ??
            [],
        fillBlanks: (j['fillBlanks'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(FillBlankItem.fromJson)
                .toList() ??
            [],
        completed: j['completed'] == true,
        bestQuizPct: (j['bestQuizPct'] as num?)?.toInt() ?? 0,
        gameCompleted: j['gameCompleted'] == true,
        stars: (j['stars'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderIndex': orderIndex,
        'title': title,
        'topic': topic,
        'objective': objective,
        'summary': summary,
        'keyTakeaways': keyTakeaways,
        'sourceCitation': sourceCitation,
        'sourceExcerpt': sourceExcerpt,
        'estimatedMinutes': estimatedMinutes,
        'quizzes': quizzes.map((e) => e.toJson()).toList(),
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'matchPairs': matchPairs.map((e) => e.toJson()).toList(),
        'fillBlanks': fillBlanks.map((e) => e.toJson()).toList(),
        'completed': completed,
        'bestQuizPct': bestQuizPct,
        'gameCompleted': gameCompleted,
        'stars': stars,
      };
}

class TopicMastery {
  String topic;
  int mcqAttempts;
  int mcqCorrect;
  int fcReviews;
  int fcMastered;
  int gameAttempts;
  int gameCorrect;
  int lastUpdatedMs;
  List<String> citations;

  TopicMastery({
    required this.topic,
    this.mcqAttempts = 0,
    this.mcqCorrect = 0,
    this.fcReviews = 0,
    this.fcMastered = 0,
    this.gameAttempts = 0,
    this.gameCorrect = 0,
    this.lastUpdatedMs = 0,
    List<String>? citations,
  }) : citations = citations ?? [];

  int get totalAttempts => mcqAttempts + fcReviews + gameAttempts;
  int get totalCorrect => mcqCorrect + fcMastered + gameCorrect;

  int get masteryPct {
    if (totalAttempts <= 0) return 0;
    return ((totalCorrect / totalAttempts) * 100).round().clamp(0, 100);
  }

  /// 'weak' (<65), 'developing' (65..84), 'strong' (>=85)
  String get level {
    final pct = masteryPct;
    if (totalAttempts == 0 || pct < 65) return 'weak';
    if (pct < 85) return 'developing';
    return 'strong';
  }

  void record({required bool isCorrect, bool isFlashcard = false, bool isGame = false, String? citation}) {
    if (isFlashcard) {
      fcReviews++;
      if (isCorrect) fcMastered++;
    } else if (isGame) {
      gameAttempts++;
      if (isCorrect) gameCorrect++;
    } else {
      mcqAttempts++;
      if (isCorrect) mcqCorrect++;
    }
    lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
    if (citation != null && citation.trim().isNotEmpty && !citations.contains(citation.trim())) {
      citations.add(citation.trim());
    }
  }

  factory TopicMastery.fromJson(Map<String, dynamic> j) => TopicMastery(
        topic: j['topic']?.toString() ?? 'General',
        mcqAttempts: (j['mcqAttempts'] as num?)?.toInt() ?? 0,
        mcqCorrect: (j['mcqCorrect'] as num?)?.toInt() ?? 0,
        fcReviews: (j['fcReviews'] as num?)?.toInt() ?? 0,
        fcMastered: (j['fcMastered'] as num?)?.toInt() ?? 0,
        gameAttempts: (j['gameAttempts'] as num?)?.toInt() ?? 0,
        gameCorrect: (j['gameCorrect'] as num?)?.toInt() ?? 0,
        lastUpdatedMs: (j['lastUpdatedMs'] as num?)?.toInt() ?? 0,
        citations: (j['citations'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'mcqAttempts': mcqAttempts,
        'mcqCorrect': mcqCorrect,
        'fcReviews': fcReviews,
        'fcMastered': fcMastered,
        'gameAttempts': gameAttempts,
        'gameCorrect': gameCorrect,
        'lastUpdatedMs': lastUpdatedMs,
        'citations': citations,
      };
}

class TutorMessage {
  String role; // 'user' | 'tutor'
  String text;
  List<String> citations;
  String? suggestedPrompt;
  int timestampMs;

  TutorMessage({
    required this.role,
    required this.text,
    List<String>? citations,
    this.suggestedPrompt,
    int? timestampMs,
  })  : citations = citations ?? [],
        timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  factory TutorMessage.fromJson(Map<String, dynamic> j) => TutorMessage(
        role: j['role']?.toString() ?? 'tutor',
        text: j['text']?.toString() ?? '',
        citations: (j['citations'] as List?)?.map((e) => e.toString()).toList() ?? [],
        suggestedPrompt: j['suggestedPrompt']?.toString(),
        timestampMs: (j['timestampMs'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'citations': citations,
        'suggestedPrompt': suggestedPrompt,
        'timestampMs': timestampMs,
      };
}

class SubjectFolder {
  String id;
  String name;
  String colorHex;
  List<McqQuestion> questions;
  List<ClinicalCase> cases;
  List<FlashcardItem> flashcards;
  List<int> lastWrongIds;
  List<SourceDocument> sources;
  List<MicroLesson> lessons;
  Map<String, TopicMastery> topicMastery;
  List<TutorMessage> tutorHistory;

  SubjectFolder({
    required this.id,
    required this.name,
    this.colorHex = '#0D9488',
    List<McqQuestion>? questions,
    List<ClinicalCase>? cases,
    List<FlashcardItem>? flashcards,
    List<int>? lastWrongIds,
    List<SourceDocument>? sources,
    List<MicroLesson>? lessons,
    Map<String, TopicMastery>? topicMastery,
    List<TutorMessage>? tutorHistory,
  })  : questions = questions ?? [],
        cases = cases ?? [],
        flashcards = flashcards ?? [],
        lastWrongIds = lastWrongIds ?? [],
        sources = sources ?? [],
        lessons = lessons ?? [],
        topicMastery = topicMastery ?? {},
        tutorHistory = tutorHistory ?? [];

  ClinicalCase? caseById(String? caseId) {
    if (caseId == null || caseId.isEmpty) return null;
    for (final c in cases) {
      if (c.id == caseId) return c;
    }
    return null;
  }

  List<SourceChunk> get allChunks => [
        for (final s in sources) ...s.chunks,
      ];

  factory SubjectFolder.fromJson(Map<String, dynamic> j) {
    final tm = <String, TopicMastery>{};
    if (j['topicMastery'] is Map) {
      (j['topicMastery'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) {
          tm[k.toString()] = TopicMastery.fromJson(v);
        }
      });
    }
    return SubjectFolder(
      id: j['id']?.toString() ?? 'f1',
      name: j['name']?.toString() ?? 'عام (General)',
      colorHex: j['color']?.toString() ?? '#0D9488',
      questions: (j['questions'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(McqQuestion.fromJson)
              .toList() ??
          [],
      cases: (j['cases'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ClinicalCase.fromJson)
              .toList() ??
          [],
      flashcards: (j['flashcards'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FlashcardItem.fromJson)
              .toList() ??
          [],
      lastWrongIds: (j['lastWrongIds'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
      sources: (j['sources'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SourceDocument.fromJson)
              .toList() ??
          [],
      lessons: (j['lessons'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(MicroLesson.fromJson)
              .toList() ??
          [],
      topicMastery: tm,
      tutorHistory: (j['tutorHistory'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(TutorMessage.fromJson)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorHex,
        'questions': questions.map((e) => e.toJson()).toList(),
        'cases': cases.map((e) => e.toJson()).toList(),
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'lastWrongIds': lastWrongIds,
        'sources': sources.map((e) => e.toJson()).toList(),
        'lessons': lessons.map((e) => e.toJson()).toList(),
        'topicMastery': topicMastery.map((k, v) => MapEntry(k, v.toJson())),
        'tutorHistory': tutorHistory.take(40).map((e) => e.toJson()).toList(),
      };
}

class QuizHistoryEntry {
  String id;
  int ts;
  String folderId;
  String folderName;
  String mode;
  int total;
  int attempted;
  int correct;
  int wrong;
  int skipped;
  int pct;
  Map<String, List<int>> byDiff;
  Map<String, List<int>> byTopic;

  QuizHistoryEntry({
    required this.id,
    required this.ts,
    required this.folderId,
    required this.folderName,
    required this.mode,
    required this.total,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.pct,
    required this.byDiff,
    required this.byTopic,
  });

  factory QuizHistoryEntry.fromJson(Map<String, dynamic> j) {
    Map<String, List<int>> parsePairMap(dynamic raw) {
      final out = <String, List<int>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List && v.length >= 2) {
            out[k.toString()] = [(v[0] as num).toInt(), (v[1] as num).toInt()];
          }
        });
      }
      return out;
    }

    return QuizHistoryEntry(
      id: j['id']?.toString() ?? '',
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      folderId: j['folderId']?.toString() ?? '',
      folderName: j['folderName']?.toString() ?? '',
      mode: j['mode']?.toString() ?? 'تدريب',
      total: (j['total'] as num?)?.toInt() ?? 0,
      attempted: (j['attempted'] as num?)?.toInt() ?? 0,
      correct: (j['correct'] as num?)?.toInt() ?? 0,
      wrong: (j['wrong'] as num?)?.toInt() ?? 0,
      skipped: (j['skipped'] as num?)?.toInt() ?? 0,
      pct: (j['pct'] as num?)?.toInt() ?? 0,
      byDiff: parsePairMap(j['byDiff']),
      byTopic: parsePairMap(j['byTopic']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts,
        'folderId': folderId,
        'folderName': folderName,
        'mode': mode,
        'total': total,
        'attempted': attempted,
        'correct': correct,
        'wrong': wrong,
        'skipped': skipped,
        'pct': pct,
        'byDiff': byDiff,
        'byTopic': byTopic,
      };
}

class StudyUnitProgress {
  int stars;
  int bestPct;
  int attempts;

  StudyUnitProgress({this.stars = 0, this.bestPct = 0, this.attempts = 0});

  factory StudyUnitProgress.fromJson(Map<String, dynamic> j) => StudyUnitProgress(
        stars: (j['stars'] as num?)?.toInt() ?? 0,
        bestPct: (j['bestPct'] as num?)?.toInt() ?? 0,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'stars': stars, 'bestPct': bestPct, 'attempts': attempts};
}

class ReminderSettings {
  bool enabled;
  String mode; // delay | clock
  int delayMin;
  String clockTime;
  int intervalMin;
  int sessionMin;
  int nextTriggerMs;
  String title;
  String body;

  ReminderSettings({
    this.enabled = false,
    this.mode = 'delay',
    this.delayMin = 30,
    this.clockTime = '20:00',
    this.intervalMin = 1440,
    this.sessionMin = 15,
    this.nextTriggerMs = 0,
    this.title = '',
    this.body = '',
  });

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        enabled: j['enabled'] == true,
        mode: j['mode']?.toString() ?? 'delay',
        delayMin: (j['delayMin'] as num?)?.toInt() ?? 30,
        clockTime: j['clockTime']?.toString() ?? '20:00',
        intervalMin: (j['intervalMin'] as num?)?.toInt() ?? 1440,
        sessionMin: (j['sessionMin'] as num?)?.toInt() ?? 15,
        nextTriggerMs: (j['nextTriggerMs'] as num?)?.toInt() ?? 0,
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'delayMin': delayMin,
        'clockTime': clockTime,
        'intervalMin': intervalMin,
        'sessionMin': sessionMin,
        'nextTriggerMs': nextTriggerMs,
        'title': title,
        'body': body,
      };
}

class AppDataState {
  List<SubjectFolder> folders;
  String activeFolderId;
  int nextFolderId;
  int nextUid;
  int nextCardUid;
  int nextCaseId;
  List<QuizHistoryEntry> quizHistory;
  int xp;
  int dailyXp;
  int dailyGoal;
  String lastXpDay;
  int hearts;
  bool spLockMode;
  int spUnitSize;
  int streak;
  String lastStudyDay;
  Map<String, StudyUnitProgress> studyProgress;
  bool soundEnabled;
  bool darkMode;
  String tutorLanguage; // 'ar' | 'en' | 'bilingual'
  ReminderSettings reminder;

  AppDataState({
    List<SubjectFolder>? folders,
    this.activeFolderId = 'f1',
    this.nextFolderId = 2,
    this.nextUid = 1,
    this.nextCardUid = 1,
    this.nextCaseId = 1,
    List<QuizHistoryEntry>? quizHistory,
    this.xp = 0,
    this.dailyXp = 0,
    this.dailyGoal = 100,
    this.lastXpDay = '',
    this.hearts = 5,
    this.spLockMode = true,
    this.spUnitSize = 0,
    this.streak = 0,
    this.lastStudyDay = '',
    Map<String, StudyUnitProgress>? studyProgress,
    this.soundEnabled = true,
    this.darkMode = false,
    this.tutorLanguage = 'bilingual',
    ReminderSettings? reminder,
  })  : folders = folders ?? [SubjectFolder(id: 'f1', name: 'عام (General)', colorHex: '#0D9488')],
        quizHistory = quizHistory ?? [],
        studyProgress = studyProgress ?? {},
        reminder = reminder ?? ReminderSettings();

  SubjectFolder get activeFolder {
    for (final f in folders) {
      if (f.id == activeFolderId) return f;
    }
    if (folders.isEmpty) {
      folders.add(SubjectFolder(id: 'f1', name: 'عام (General)'));
    }
    activeFolderId = folders.first.id;
    return folders.first;
  }

  void syncDailyReset() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (lastXpDay != today) {
      lastXpDay = today;
      dailyXp = 0;
    }
  }

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
        'folders': folders.map((e) => e.toJson()).toList(),
        'activeFolderId': activeFolderId,
        'nextFolderId': nextFolderId,
        'nextUid': nextUid,
        'nextCardUid': nextCardUid,
        'nextCaseId': nextCaseId,
        'quizHistory': quizHistory.map((e) => e.toJson()).toList(),
        'xp': xp,
        'dailyXp': dailyXp,
        'dailyGoal': dailyGoal,
        'lastXpDay': lastXpDay,
        'hearts': hearts,
        'spLockMode': spLockMode,
        'spUnitSize': spUnitSize,
        'streak': streak,
        'lastStudyDay': lastStudyDay,
        'studyProgress': studyProgress.map((k, v) => MapEntry(k, v.toJson())),
        'soundEnabled': soundEnabled,
        'darkMode': darkMode,
        'tutorLanguage': tutorLanguage,
        'reminder': reminder.toJson(),
      };

  factory AppDataState.fromJson(Map<String, dynamic> j) {
    final folders = (j['folders'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(SubjectFolder.fromJson)
            .toList() ??
        [SubjectFolder(id: 'f1', name: 'عام (General)')];
    if (folders.isEmpty) {
      folders.add(SubjectFolder(id: 'f1', name: 'عام (General)'));
    }
    final sp = <String, StudyUnitProgress>{};
    if (j['studyProgress'] is Map) {
      (j['studyProgress'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) sp[k.toString()] = StudyUnitProgress.fromJson(v);
      });
    }
    return AppDataState(
      folders: folders,
      activeFolderId: j['activeFolderId']?.toString() ?? folders.first.id,
      nextFolderId: (j['nextFolderId'] as num?)?.toInt() ?? 2,
      nextUid: (j['nextUid'] as num?)?.toInt() ?? 1,
      nextCardUid: (j['nextCardUid'] as num?)?.toInt() ?? 1,
      nextCaseId: (j['nextCaseId'] as num?)?.toInt() ?? 1,
      quizHistory: (j['quizHistory'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(QuizHistoryEntry.fromJson)
              .toList() ??
          [],
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      dailyXp: (j['dailyXp'] as num?)?.toInt() ?? 0,
      dailyGoal: (j['dailyGoal'] as num?)?.toInt() ?? 100,
      lastXpDay: j['lastXpDay']?.toString() ?? '',
      hearts: (j['hearts'] as num?)?.toInt() ?? 5,
      spLockMode: j['spLockMode'] != false,
      spUnitSize: (j['spUnitSize'] as num?)?.toInt() ?? 0,
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      lastStudyDay: j['lastStudyDay']?.toString() ?? '',
      studyProgress: sp,
      soundEnabled: j['soundEnabled'] != false,
      darkMode: j['darkMode'] == true,
      tutorLanguage: j['tutorLanguage']?.toString() ?? 'bilingual',
      reminder: j['reminder'] is Map<String, dynamic>
          ? ReminderSettings.fromJson(j['reminder'])
          : ReminderSettings(),
    );
  }
}
