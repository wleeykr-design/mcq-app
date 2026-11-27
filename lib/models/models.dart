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
  String stem;
  List<String> options;
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
    required this.stem,
    required this.options,
    required this.answerIndices,
    this.answerIndex = -1,
    this.isMulti = false,
    this.caseId,
    this.difficulty = 'medium',
    this.topic = 'General Medicine',
    this.explanation = '',
    this.srs,
    QuestionStats? stats,
  }) : stats = stats ?? QuestionStats();

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
      stem: j['stem']?.toString() ?? '',
      options: opts,
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
        'stem': stem,
        'options': options,
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
  String status; // learning | review | mastered
  bool starred;
  int createdAt;

  FlashcardItem({
    required this.uid,
    required this.front,
    required this.back,
    this.hint = '',
    this.topic = '',
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
        'status': status,
        'starred': starred,
        'createdAt': createdAt,
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

  SubjectFolder({
    required this.id,
    required this.name,
    this.colorHex = '#0D9488',
    List<McqQuestion>? questions,
    List<ClinicalCase>? cases,
    List<FlashcardItem>? flashcards,
    List<int>? lastWrongIds,
  })  : questions = questions ?? [],
        cases = cases ?? [],
        flashcards = flashcards ?? [],
        lastWrongIds = lastWrongIds ?? [];

  ClinicalCase? caseById(String? caseId) {
    if (caseId == null || caseId.isEmpty) return null;
    for (final c in cases) {
      if (c.id == caseId) return c;
    }
    return null;
  }

  factory SubjectFolder.fromJson(Map<String, dynamic> j) => SubjectFolder(
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorHex,
        'questions': questions.map((e) => e.toJson()).toList(),
        'cases': cases.map((e) => e.toJson()).toList(),
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'lastWrongIds': lastWrongIds,
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
      reminder: j['reminder'] is Map<String, dynamic>
          ? ReminderSettings.fromJson(j['reminder'])
          : ReminderSettings(),
    );
  }
}
