import 'dart:convert';
import 'dart:math';
import '../models/models.dart';

class ParsedBundle {
  final List<McqQuestion> questions;
  final List<ClinicalCase> cases;
  ParsedBundle(this.questions, this.cases);
}

class _TopicRule {
  final String topic;
  final RegExp pattern;
  const _TopicRule(this.topic, this.pattern);
}

final List<_TopicRule> _kTopicRules = [
  _TopicRule('Biochemistry & Cell Biology', RegExp(r'\b(enzyme|atp|dna|rna|glycolysis|krebs|nadh|membrane|lipid|cholesterol|protein|amino acid|phospholipid|mitochondria|ribosome|metabolism|collagen|elastin|histone|telomere|glucose|osmosis|diffusion)\b|إنزيم|خلية|أحماض|بروتين|أيض|غشاء', caseSensitive: false)),
  _TopicRule('Cardiology', RegExp(r'\b(heart|cardiac|ecg|ekg|myocard|coronary|aorta|atrial|ventric|hypertension|bp|preload|afterload|murmur|angina|arrhythmia|mitral|stroke volume)\b|قلب|شريان|ضغط الدم|نبض', caseSensitive: false)),
  _TopicRule('Neurology & Neuroanatomy', RegExp(r'\b(brain|neuron|synapse|axon|myelin|cortex|cerebell|spinal|cranial nerve|stroke|seizure|dopamine|acetylcholine|csf|meninges)\b|دماغ|أعصاب|عصب|نخاع', caseSensitive: false)),
  _TopicRule('Respiratory', RegExp(r'\b(lung|alveol|bronch|asthma|copd|pneumonia|respirat|pleura|surfactant|hypoxia|spirometry|fev1|tidal volume)\b|رئة|تنفس|شعب|ربو', caseSensitive: false)),
  _TopicRule('Renal & Electrolytes', RegExp(r'\b(kidney|renal|nephron|glomerul|gfr|creatinine|urea|sodium|potassium|aldosterone|adh|acidosis|alkalosis|diuretic)\b|كلية|كلوي|بول|إلكتروليت', caseSensitive: false)),
  _TopicRule('Gastroenterology', RegExp(r'\b(liver|hepat|stomach|gastric|intestin|colon|pancreas|bile|bilirubin|ulcer|cirrhosis|amylase)\b|كبد|معدة|أمعاء|بنكرياس', caseSensitive: false)),
  _TopicRule('Pharmacology', RegExp(r'\b(drug|agonist|antagonist|receptor|half-life|bioavailability|clearance|inhibitor|blocker|antibiotic|penicillin|beta-lactam|dose|toxicity)\b|دواء|جرعة|مضاد|مستقبل', caseSensitive: false)),
  _TopicRule('Microbiology & Immunology', RegExp(r'\b(bacteria|virus|fungus|gram-positive|gram-negative|antibody|igg|igm|t-cell|b-cell|vaccine|cytokine|complement|sepsis)\b|بكتيريا|فيروس|مناعة|مضاد حيوي', caseSensitive: false)),
  _TopicRule('Hematology', RegExp(r'\b(hemoglobin|anemia|rbc|wbc|platelet|coagulation|hemostasis|leukemia|lymphoma|ferritin|iron)\b|دم|أنيميا|هيموجلوبين|تخثر', caseSensitive: false)),
  _TopicRule('Endocrinology', RegExp(r'\b(insulin|glucagon|diabetes|thyroid|tsh|cortisol|adrenal|pituitary|parathyroid|hormone|estrogen)\b|هرمون|أنسولين|سكري|غدة', caseSensitive: false)),
  _TopicRule('Citizenship & Ethics', RegExp(r'المواطنة|الوطن|الانتماء|الحقوق|القانون|الدستور|المفكر|توماس هوبز|جون لوك|أرسطو|أخلاق|ethics|autonomy', caseSensitive: false)),
];

const Map<String, int> _kArabicLetterMap = {
  'أ': 0,
  'ا': 0,
  'ب': 1,
  'ج': 2,
  'د': 3,
  'ه': 4,
  'و': 5,
};

class McqParser {
  static String normalizeStem(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), ' ').trim();
  }

  static int parseLetterToken(String? token) {
    if (token == null) return -1;
    final t = token.trim().replaceAll(RegExp(r'[()\[\].:\-✓✔*]'), '');
    if (RegExp(r'^[A-Fa-f]$').hasMatch(t)) {
      return kMcqLetters.indexOf(t.toUpperCase());
    }
    if (_kArabicLetterMap.containsKey(t)) return _kArabicLetterMap[t]!;
    if (RegExp(r'^[1-6]$').hasMatch(t)) return int.parse(t) - 1;
    return -1;
  }

  static List<int> parseAnswerTokens(dynamic raw, {int optsLen = 6}) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((v) => v is num ? v.toInt() : parseLetterToken(v.toString()))
          .where((i) => i >= 0 && i < optsLen)
          .toSet()
          .toList()
        ..sort();
    }
    var s = raw.toString().trim().replaceAll(RegExp(r'^[(\[\s]+|[)\]\s]+$'), '');
    if (s.isEmpty) return [];
    if (RegExp(r'^([A-Fa-f]|[أبجدهو]|[1-6])(?:\s*(?:[,;&+/و،\-]+|\s+)\s*([A-Fa-f]|[أبجدهو]|[1-6]))*$', caseSensitive: false).hasMatch(s)) {
      return s
          .split(RegExp(r'\s*[,;&+/و،\-]+\s*|\s+'))
          .map(parseLetterToken)
          .where((i) => i >= 0 && i < optsLen)
          .toSet()
          .toList()
        ..sort();
    }
    if (RegExp(r'^[A-Fa-f]{1,6}$').hasMatch(s)) {
      return s.split('').map(parseLetterToken).where((i) => i >= 0 && i < optsLen).toSet().toList()..sort();
    }
    final lead = RegExp(r'^([A-Fa-f]|[أبجدهو])(?:\b|\s|[.)\-:])').firstMatch(s);
    if (lead != null) {
      final single = parseLetterToken(lead.group(1));
      if (single >= 0 && single < optsLen) return [single];
    }
    return [];
  }

  static String detectDifficulty(String stem, List<String> options, [String? explicitDiff]) {
    if (explicitDiff != null && explicitDiff.trim().isNotEmpty) {
      final d = explicitDiff.toLowerCase();
      if (RegExp(r'(easy|سهل)').hasMatch(d)) return 'easy';
      if (RegExp(r'(hard|difficult|صعب)').hasMatch(d)) return 'hard';
      if (RegExp(r'(medium|moderate|متوسط)').hasMatch(d)) return 'medium';
    }
    final avgOptLen = options.isEmpty
        ? 0.0
        : options.fold<int>(0, (a, b) => a + b.length) / options.length;
    final isVignette = RegExp(
      r'\b(\d{1,3}-year-old|presents with|history of|physical examination|blood pressure|mm\s*hg|bmi|mechanism|directly and immediately|best explains)\b',
      caseSensitive: false,
    ).hasMatch(stem);
    final isNegative = RegExp(
      r'\b(except|least likely|not true|incorrect|false|all of the following)\b|(عدا|باستثناء|غير صحيح)',
      caseSensitive: false,
    ).hasMatch(stem);
    if (isVignette || (isNegative && stem.length > 90) || stem.length > 185 || avgOptLen > 52) {
      return 'hard';
    }
    if (isNegative ||
        stem.length > 88 ||
        avgOptLen > 24 ||
        RegExp(r'\b(compare|increase|decrease|inhibit|regulate|mechanism|difference|more permeable)\b', caseSensitive: false).hasMatch(stem)) {
      return 'medium';
    }
    return 'easy';
  }

  static String detectTopic(String stem, List<String> options, [String? explicitTopic]) {
    if (explicitTopic != null &&
        explicitTopic.trim().isNotEmpty &&
        !RegExp(r'^(سهل|متوسط|صعب|easy|medium|hard)$', caseSensitive: false).hasMatch(explicitTopic.trim())) {
      return explicitTopic.trim();
    }
    final blob = '$stem ${options.join(' ')}';
    for (final rule in _kTopicRules) {
      if (rule.pattern.hasMatch(blob)) return rule.topic;
    }
    return 'General Medicine';
  }

  static McqQuestion buildQuestion(
    AppDataState appState, {
    int sourceNum = 0,
    String sourceName = 'ملف',
    required String stem,
    required List<String> options,
    List<int>? answerIndices,
    int answerIndex = -1,
    bool isMulti = false,
    String? caseId,
    String? explicitDiff,
    String? explicitTopic,
    String explanation = '',
  }) {
    final cleanOpts = options.map((e) => e.trim()).where((e) => e.isNotEmpty).take(6).toList();
    var ans = (answerIndices ?? [])
        .where((i) => i >= 0 && i < cleanOpts.length)
        .toSet()
        .toList()
      ..sort();
    if (ans.isEmpty && answerIndex >= 0 && answerIndex < cleanOpts.length) {
      ans = [answerIndex];
    }
    final cleanStem = stem.trim();
    return McqQuestion(
      uid: appState.nextUid++,
      sourceNum: sourceNum,
      sourceName: sourceName,
      stem: cleanStem,
      options: cleanOpts,
      answerIndices: ans,
      answerIndex: ans.isNotEmpty ? ans.first : -1,
      isMulti: isMulti || ans.length > 1,
      caseId: caseId,
      difficulty: detectDifficulty(cleanStem, cleanOpts, explicitDiff),
      topic: detectTopic(cleanStem, cleanOpts, explicitTopic),
      explanation: explanation.trim(),
    );
  }

  static ParsedBundle parseBundle(AppDataState appState, String rawText, {String sourceName = 'ملف'}) {
    final txt = rawText.replaceFirst('\uFEFF', '').replaceAll(RegExp(r'\r\n?'), '\n').trim();
    if (txt.isEmpty) return ParsedBundle([], []);

    // 1. JSON check
    if ((txt.startsWith('[') || txt.startsWith('{')) &&
        RegExp(r'"question"|"stem"|"options"|"choices"|"cases"|"q"', caseSensitive: false).hasMatch(txt)) {
      try {
        final parsed = jsonDecode(txt);
        final casesOut = <ClinicalCase>[];
        final caseMap = <String, ClinicalCase>{};
        if (parsed is Map && parsed['cases'] is List) {
          for (final c in parsed['cases'] as List) {
            if (c is Map && (c['vignette'] != null || c['text'] != null || c['title'] != null)) {
              final cid = c['id']?.toString() ?? 'case_${appState.nextCaseId++}';
              final obj = ClinicalCase(
                id: cid,
                title: (c['title']?.toString() ?? 'حالة سريرية').trim(),
                vignette: (c['vignette']?.toString() ?? c['text']?.toString() ?? '').trim(),
                topic: c['topic']?.toString().trim() ?? '',
              );
              casesOut.add(obj);
              caseMap[cid] = obj;
            }
          }
        }
        final arr = parsed is List
            ? parsed
            : (parsed is Map ? (parsed['questions'] ?? parsed['items'] ?? parsed['data'] ?? []) : []);
        if (arr is List && arr.isNotEmpty) {
          final qs = <McqQuestion>[];
          for (var i = 0; i < arr.length; i++) {
            final item = arr[i];
            if (item is! Map) continue;
            final opts = item['options'] is List
                ? (item['options'] as List).map((e) => e.toString()).toList()
                : (item['choices'] is List
                    ? (item['choices'] as List).map((e) => e.toString()).toList()
                    : [item['A'], item['B'], item['C'], item['D'], item['E']]
                        .where((e) => e != null)
                        .map((e) => e.toString())
                        .toList());
            var ansIndices = parseAnswerTokens(item['answerIndices'] ?? item['answer'] ?? item['correct'] ?? item['ans'], optsLen: opts.isEmpty ? 6 : opts.length);
            if (ansIndices.isEmpty && item['answerIndex'] is num && (item['answerIndex'] as num).toInt() >= 0) {
              ansIndices = [(item['answerIndex'] as num).toInt()];
            }
            var cid = (item['caseId'] != null && caseMap.containsKey(item['caseId'].toString())) ? item['caseId'].toString() : null;
            if (cid == null && (item['caseText'] != null || item['vignette'] != null)) {
              final rawTitle = item['caseTitle']?.toString() ?? item['caseText']?.toString() ?? item['vignette']?.toString() ?? '';
              final key = rawTitle.substring(0, min(120, rawTitle.length));
              if (!caseMap.containsKey(key)) {
                final nc = ClinicalCase(
                  id: 'case_${appState.nextCaseId++}',
                  title: (item['caseTitle']?.toString() ?? 'حالة سريرية').trim(),
                  vignette: (item['caseText']?.toString() ?? item['vignette']?.toString() ?? '').trim(),
                  topic: item['topic']?.toString() ?? '',
                );
                casesOut.add(nc);
                caseMap[key] = nc;
              }
              cid = caseMap[key]!.id;
            }
            qs.add(buildQuestion(
              appState,
              sourceNum: (item['number'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? i + 1,
              sourceName: sourceName,
              stem: (item['question'] ?? item['stem'] ?? item['q'] ?? item['title'] ?? '').toString(),
              options: opts,
              answerIndices: ansIndices,
              isMulti: item['isMulti'] == true || ansIndices.length > 1,
              caseId: cid,
              explicitDiff: (item['difficulty'] ?? item['level'])?.toString(),
              explicitTopic: (item['topic'] ?? item['category'] ?? item['subject'])?.toString(),
              explanation: (item['explanation'] ?? item['rationale'] ?? '').toString(),
            ));
          }
          return ParsedBundle(qs.where((q) => q.stem.isNotEmpty).toList(), casesOut);
        }
      } catch (_) {}
    }

    // 2. CSV / TSV check
    final firstLine = txt.split('\n').first;
    if ((firstLine.contains(',') || firstLine.contains('\t')) &&
        RegExp(r'question|stem|option|answer|سؤال', caseSensitive: false).hasMatch(firstLine) &&
        !RegExp(r'^Question:', caseSensitive: false).hasMatch(firstLine)) {
      final csvQs = _tryParseCsv(appState, txt, sourceName);
      if (csvQs.isNotEmpty) return ParsedBundle(csvQs, []);
    }

    // 3. Universal Text Parser
    final lines = txt.split('\n');
    final questions = <McqQuestion>[];
    final cases = <ClinicalCase>[];
    final answerKeyMap = <int, List<int>>{};
    McqQuestion? curQ;
    ClinicalCase? activeCase;
    var curOptIdx = -1;
    var curSectionTopic = '';
    var curSectionDiff = '';
    var inAnswerKeySection = false;

    void pushCur() {
      if (curQ != null && (curQ!.stem.trim().isNotEmpty || curQ!.options.isNotEmpty)) {
        if (activeCase != null && activeCase!.vignette.trim().isEmpty && activeCase!.title.isNotEmpty) {
          activeCase!.vignette = activeCase!.title;
        }
        questions.add(curQ!);
      }
      curQ = null;
      curOptIdx = -1;
    }

    final reCaseEnd = RegExp(r'^\s*(?:={2,}|-{3,})?\s*(?:End\s*Case|Standalone(?:\s*Questions?)?|نهاية\s*الحالة|أسئلة\s*منفردة)\s*(?:={2,}|-{3,})?\s*:?\s*$', caseSensitive: false);
    final reCaseStart = RegExp(r'^\s*(?:={2,}\s*)?(?:Clinical\s*Case|Case\s*Study|Case\s*Scenario|Clinical\s*Vignette|Vignette|Case\s*\d+|Case\s*(?=[:\-])|حالة\s*سريرية|الحالة\s*السريرية|سيناريو\s*سريري|الحالة\s*\d*)\s*(?:\d*)\s*[:.\-\)]*\s*(.*?)(?:\s*={2,})?\s*$', caseSensitive: false);
    final reSection = RegExp(r'^\s*(?:={2,}|-{3,}|#{1,3})\s*(.+?)\s*(?:={2,}|-{3,})?\s*$');
    final reAnswerHeader = RegExp(r'^\s*(?:answer\s*key|answers?|key|مفتاح\s*الإجابات|الإجابات|الحلول)\s*:?\s*$', caseSensitive: false);
    final reAnswerKeyLine = RegExp(r'^\s*(?:Q?\s*(\d+))\s*[-.):\s]+\s*([A-Fa-fأبجدهو](?:\s*[,;&+/و،]\s*[A-Fa-fأبجدهو])*)\s*$', caseSensitive: false);
    final reRudaQ = RegExp(r'^\s*(?:Question|Stem|Q\s*\d*|السؤال|سؤال)\s*[:\-]\s*(.*)$', caseSensitive: false);
    final reNumQ = RegExp(r'^\s*(?:Q\s*)?(\d{1,4})\s*[.)\-:]\s+(.+)$', caseSensitive: false);
    final reArabicQPrefix = RegExp(r'^\s*(?:س\s*(\d+)|السؤال\s*(\d*))\s*[:.\-\)]\s*(.+)$');
    final reOpt = RegExp(r'^\s*(?:\(([A-Fa-f])\)|([A-Fa-f])\s*[:.)\-]|([أبجدهو])\s*[:.)\-]|([*✓✔☑])\s*([A-Fa-f])\s*[:.)\-]?)\s*(.+)$');
    final reAns = RegExp(r'^\s*(?:Correct\s*Answers?|Answers?|Ans|Correct|Key|الإجابة(?:\s*الصحيحة)?|الجواب(?:\s*الصحيح)?|الاجابة)\s*[:\-]\s*(.+)$', caseSensitive: false);
    final reExp = RegExp(r'^\s*(?:Explanation|Rationale|Reason|Note|التفسير|التعليل|الشرح|ملاحظة)\s*[:\-]\s*(.+)$', caseSensitive: false);
    final reDiffMeta = RegExp(r'^\s*(?:Difficulty|Level|الصعوبة|المستوى)\s*[:\-]\s*(.+)$', caseSensitive: false);
    final reTopicMeta = RegExp(r'^\s*(?:Topic|Category|Subject|الموضوع|القسم|المادة)\s*[:\-]\s*(.+)$', caseSensitive: false);

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (reCaseEnd.hasMatch(line)) {
        pushCur();
        activeCase = null;
        continue;
      }

      if (reAnswerHeader.hasMatch(line)) {
        pushCur();
        inAnswerKeySection = true;
        continue;
      }

      if (inAnswerKeySection) {
        final km = reAnswerKeyLine.firstMatch(line);
        if (km != null) {
          final idxs = parseAnswerTokens(km.group(2));
          if (idxs.isNotEmpty) answerKeyMap[int.parse(km.group(1)!)] = idxs;
          continue;
        }
        final inlinePairs = RegExp(r'(?:Q?\s*(\d+))\s*[-.):\s]+\s*([A-Fa-fأبجدهو](?:\s*[,&+/و،]\s*[A-Fa-fأبجدهو])*)', caseSensitive: false).allMatches(line).toList();
        if (inlinePairs.length >= 2) {
          for (final p in inlinePairs) {
            final idxs = parseAnswerTokens(p.group(2));
            if (idxs.isNotEmpty) answerKeyMap[int.parse(p.group(1)!)] = idxs;
          }
          continue;
        }
      }

      final cm = reCaseStart.firstMatch(line);
      if (cm != null && !reRudaQ.hasMatch(line)) {
        pushCur();
        inAnswerKeySection = false;
        final inlineTxt = (cm.group(1) ?? '').trim();
        final title = inlineTxt.isNotEmpty && inlineTxt.length < 70
            ? inlineTxt
            : 'حالة سريرية ${cases.length + 1}';
        activeCase = ClinicalCase(
          id: 'case_${appState.nextCaseId++}',
          title: title,
          vignette: inlineTxt.length >= 70 ? inlineTxt : '',
          topic: curSectionTopic,
        );
        cases.add(activeCase);
        continue;
      }

      if (reSection.hasMatch(line) && !RegExp(r'^#{1,3}\s*\d').hasMatch(line)) {
        final secTxt = reSection.firstMatch(line)!.group(1)!.trim();
        if (secTxt.length < 70 && !RegExp(r'^(Question|Answer)', caseSensitive: false).hasMatch(secTxt)) {
          pushCur();
          activeCase = null;
          if (RegExp(r'(easy|سهل)', caseSensitive: false).hasMatch(secTxt)) curSectionDiff = 'easy';
          if (RegExp(r'(medium|moderate|متوسط)', caseSensitive: false).hasMatch(secTxt)) curSectionDiff = 'medium';
          if (RegExp(r'(hard|difficult|صعب)', caseSensitive: false).hasMatch(secTxt)) curSectionDiff = 'hard';
          final cleanedTopic = secTxt
              .replaceAll(RegExp(r'\b(questions?|mcq|easy|medium|hard)\b', caseSensitive: false), '')
              .replaceAll(RegExp(r'(أسئلة|سهل|متوسط|صعب)'), '')
              .replaceAll(RegExp(r'[-:|()]+'), ' ')
              .trim();
          if (cleanedTopic.length > 2) curSectionTopic = cleanedTopic;
          continue;
        }
      }

      final rudaM = reRudaQ.firstMatch(line);
      if (rudaM != null) {
        pushCur();
        inAnswerKeySection = false;
        curQ = McqQuestion(
          uid: appState.nextUid++,
          sourceNum: questions.length + 1,
          sourceName: sourceName,
          stem: rudaM.group(1)!.trim(),
          options: [],
          answerIndices: [],
          caseId: activeCase?.id,
          difficulty: curSectionDiff.isNotEmpty ? curSectionDiff : 'medium',
          topic: curSectionTopic.isNotEmpty ? curSectionTopic : 'General Medicine',
        );
        continue;
      }

      final optM = reOpt.firstMatch(line);
      if (optM != null && curQ != null) {
        final letter = (optM.group(1) ?? optM.group(2) ?? optM.group(3) ?? optM.group(5) ?? '').trim();
        final idx = parseLetterToken(letter);
        var optBody = (optM.group(6) ?? '').trim();
        final hasStar = (optM.group(4) != null) ||
            RegExp(r'(?:^|\s)(?:\*|✓|✔|☑|\(correct\)|\[correct\]|\(صحيح\))\s*$', caseSensitive: false).hasMatch(optBody);
        optBody = optBody.replaceAll(RegExp(r'(?:\s*(?:\*|✓|✔|☑|\(correct\)|\[correct\]|\(صحيح\)))+\s*$', caseSensitive: false), '').trim();
        if (idx >= 0) {
          while (curQ!.options.length < idx) {
            curQ!.options.add('');
          }
          if (idx == curQ!.options.length) {
            curQ!.options.add(optBody);
          } else {
            curQ!.options[idx] = optBody;
          }
          curOptIdx = idx;
          if (hasStar) {
            final cur = curQ!.getCorrectIndices();
            if (!cur.contains(idx)) curQ!.setCorrectIndices([...cur, idx]);
          }
          continue;
        }
      }

      final ansM = reAns.firstMatch(line);
      if (ansM != null && curQ != null) {
        final idxs = parseAnswerTokens(ansM.group(1), optsLen: max(6, curQ!.options.length));
        if (idxs.isNotEmpty) {
          curQ!.setCorrectIndices(idxs);
        } else {
          final ansTxt = ansM.group(1)!.trim().toLowerCase();
          final matched = curQ!.options.indexWhere((o) => o.toLowerCase() == ansTxt || o.toLowerCase().contains(ansTxt));
          if (matched >= 0) curQ!.setCorrectIndices([matched]);
        }
        curOptIdx = -1;
        continue;
      }

      final expM = reExp.firstMatch(line);
      if (expM != null && curQ != null) {
        curQ!.explanation = (curQ!.explanation.isNotEmpty ? '${curQ!.explanation} ' : '') + expM.group(1)!.trim();
        curOptIdx = -1;
        continue;
      }

      final diffM = reDiffMeta.firstMatch(line);
      if (diffM != null && curQ != null) {
        curQ!.difficulty = detectDifficulty(curQ!.stem, curQ!.options, diffM.group(1));
        continue;
      }

      final topM = reTopicMeta.firstMatch(line);
      if (topM != null && curQ != null) {
        curQ!.topic = topM.group(1)!.trim();
        continue;
      }

      final arQM = reArabicQPrefix.firstMatch(line);
      final numQM = reNumQ.firstMatch(line);
      if (arQM != null || numQM != null) {
        final qNum = int.tryParse((arQM?.group(1) ?? arQM?.group(2) ?? numQM?.group(1) ?? '').trim()) ?? (questions.length + 1);
        final qStem = (arQM?.group(3) ?? numQM?.group(2) ?? '').trim();
        final looksLikeShortKey = qStem.length <= 8 && parseAnswerTokens(qStem).isNotEmpty;
        if (looksLikeShortKey && questions.isNotEmpty) {
          answerKeyMap[qNum] = parseAnswerTokens(qStem);
          continue;
        }
        pushCur();
        inAnswerKeySection = false;
        curQ = McqQuestion(
          uid: appState.nextUid++,
          sourceNum: qNum,
          sourceName: sourceName,
          stem: qStem,
          options: [],
          answerIndices: [],
          caseId: activeCase?.id,
          difficulty: curSectionDiff.isNotEmpty ? curSectionDiff : 'medium',
          topic: curSectionTopic.isNotEmpty ? curSectionTopic : 'General Medicine',
        );
        continue;
      }

      if (activeCase != null && curQ == null) {
        activeCase!.vignette = (activeCase!.vignette.isNotEmpty ? '${activeCase!.vignette}\n' : '') + line;
        continue;
      }

      if (curQ != null) {
        if (curOptIdx >= 0 && curQ!.options.isNotEmpty) {
          curQ!.options[curOptIdx] = '${curQ!.options[curOptIdx]} $line'.trim();
        } else if (curQ!.options.isEmpty) {
          curQ!.stem = (curQ!.stem.isNotEmpty ? '${curQ!.stem}\n' : '') + line;
        } else {
          curQ!.explanation = (curQ!.explanation.isNotEmpty ? '${curQ!.explanation} ' : '') + line;
        }
      } else {
        final inlineKey = reAnswerKeyLine.firstMatch(line);
        if (inlineKey != null) {
          answerKeyMap[int.parse(inlineKey.group(1)!)] = parseAnswerTokens(inlineKey.group(2));
        }
      }
    }
    pushCur();

    final normalized = <McqQuestion>[];
    for (var idx = 0; idx < questions.length; idx++) {
      final q = questions[idx];
      final keyArr = answerKeyMap[q.sourceNum] ?? answerKeyMap[idx + 1] ?? [];
      if (q.getCorrectIndices().isEmpty && keyArr.isNotEmpty) {
        q.setCorrectIndices(keyArr);
      }
      q.difficulty = detectDifficulty(q.stem, q.options, q.difficulty);
      q.topic = detectTopic(q.stem, q.options, q.topic);
      if (q.stem.trim().isNotEmpty) normalized.add(q);
    }

    return ParsedBundle(normalized, cases);
  }

  static List<McqQuestion> _tryParseCsv(AppDataState appState, String txt, String sourceName) {
    final rows = <List<String>>[];
    for (final rawLine in txt.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('\t') && !line.contains(',')) {
        rows.add(line.split('\t').map((c) => c.trim()).toList());
      } else {
        final cols = <String>[];
        var cur = '';
        var inQ = false;
        for (var i = 0; i < line.length; i++) {
          final ch = line[i];
          if (ch == '"') {
            if (inQ && i + 1 < line.length && line[i + 1] == '"') {
              cur += '"';
              i++;
            } else {
              inQ = !inQ;
            }
          } else if (ch == ',' && !inQ) {
            cols.add(cur.trim());
            cur = '';
          } else {
            cur += ch;
          }
        }
        cols.add(cur.trim());
        rows.add(cols);
      }
    }
    if (rows.length < 2) return [];
    final hdr = rows.first.map((h) => h.toLowerCase()).toList();
    final qCol = hdr.indexWhere((h) => RegExp(r'question|stem|سؤال').hasMatch(h));
    if (qCol < 0) return [];
    final ansCol = hdr.indexWhere((h) => RegExp(r'answer|correct|key|إجابة').hasMatch(h));
    final diffCol = hdr.indexWhere((h) => RegExp(r'diff|level|صعوبة').hasMatch(h));
    final topCol = hdr.indexWhere((h) => RegExp(r'topic|subject|category|موضوع').hasMatch(h));
    final expCol = hdr.indexWhere((h) => RegExp(r'exp|rationale|تفسير|تعليل').hasMatch(h));
    final optCols = <int>[];
    for (var idx = 0; idx < hdr.length; idx++) {
      if (RegExp(r'^(opt|option|choice|[a-f]$)').hasMatch(hdr[idx])) optCols.add(idx);
    }

    final out = <McqQuestion>[];
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final opts = optCols.map((c) => c < r.length ? r[c] : '').where((v) => v.isNotEmpty).toList();
      final rawAns = (ansCol >= 0 && ansCol < r.length) ? r[ansCol] : '';
      var ansIndices = parseAnswerTokens(rawAns, optsLen: max(6, opts.length));
      if (ansIndices.isEmpty && rawAns.isNotEmpty) {
        final m = opts.indexWhere((o) => o.toLowerCase() == rawAns.toLowerCase());
        if (m >= 0) ansIndices = [m];
      }
      final q = buildQuestion(
        appState,
        sourceNum: i,
        sourceName: sourceName,
        stem: qCol < r.length ? r[qCol] : '',
        options: opts,
        answerIndices: ansIndices,
        explicitDiff: (diffCol >= 0 && diffCol < r.length) ? r[diffCol] : null,
        explicitTopic: (topCol >= 0 && topCol < r.length) ? r[topCol] : null,
        explanation: (expCol >= 0 && expCol < r.length) ? r[expCol] : '',
      );
      if (q.stem.isNotEmpty) out.add(q);
    }
    return out;
  }

  static Map<int, List<int>> parseAnswerSequence(String rawText) {
    final txt = rawText.trim();
    final mapped = <int, List<int>>{};
    final pairs = RegExp(r'(?:Q?\s*(\d+))\s*[-.):\s]+\s*([A-Fa-fأبجدهو](?:\s*[,&+/و،]\s*[A-Fa-fأبجدهو])*)', caseSensitive: false).allMatches(txt).toList();
    if (pairs.length >= 2 || RegExp(r'\d+\s*[-.):]').hasMatch(txt)) {
      for (final p in pairs) {
        final idxs = parseAnswerTokens(p.group(2));
        if (idxs.isNotEmpty) mapped[int.parse(p.group(1)!)] = idxs;
      }
      return mapped;
    }
    final tokens = txt.split(RegExp(r'[\s;]+')).where((e) => e.isNotEmpty).toList();
    var seq = <List<int>>[];
    if (tokens.length == 1 && RegExp(r'^[A-Fa-f]{2,}$', caseSensitive: false).hasMatch(tokens.first)) {
      seq = tokens.first.split('').map((c) => parseAnswerTokens(c)).where((a) => a.isNotEmpty).toList();
    } else {
      seq = tokens.map((t) => parseAnswerTokens(t)).where((a) => a.isNotEmpty).toList();
    }
    for (var i = 0; i < seq.length; i++) {
      mapped[i + 1] = seq[i];
    }
    return mapped;
  }

  static int smartBalanceAnswers(List<McqQuestion> questions) {
    final counts = [0, 0, 0, 0];
    final rng = Random();
    var adjusted = 0;
    for (final q in questions) {
      if (q.hasIssue || q.isMultiAnswer) continue;
      if (q.options.length < 3 || q.options.length > 4) continue;
      final curAns = q.getCorrectIndices().first;
      final limit = q.options.length;
      final minVal = counts.take(limit).reduce(min);
      final targets = [for (var i = 0; i < limit; i++) if (counts[i] == minVal) i];
      final targetIdx = targets[rng.nextInt(targets.length)];
      if (targetIdx != curAns) {
        final tmp = q.options[curAns];
        q.options[curAns] = q.options[targetIdx];
        q.options[targetIdx] = tmp;
        q.setCorrectIndices([targetIdx]);
        adjusted++;
      }
      counts[targetIdx]++;
    }
    return adjusted;
  }

  static void shuffleQuestionOptions(McqQuestion q) {
    final rng = Random();
    final corrSet = q.getCorrectIndices().toSet();
    final tagged = [
      for (var i = 0; i < q.options.length; i++)
        {'text': q.options[i], 'ok': corrSet.contains(i)}
    ]..shuffle(rng);
    q.options = tagged.map((e) => e['text'] as String).toList();
    final newAns = [for (var i = 0; i < tagged.length; i++) if (tagged[i]['ok'] == true) i];
    q.setCorrectIndices(newAns, keepMultiFlag: q.isMulti);
  }

  static const String sampleText = '''=== Clinical Case 1: Acute Chest Pain ===
A 58-year-old male smoker with hypertension presents to the ER with severe retrosternal crushing chest pain radiating to the left arm for 40 minutes, accompanied by diaphoresis. ECG shows ST-segment elevation in leads II, III, and aVF.

1. Which coronary artery is most likely occluded in this patient?
A) Left anterior descending artery
B) Right coronary artery
C) Left circumflex artery
D) Internal mammary artery
Answer: B
Explanation: ST elevation in II, III, and aVF indicates an inferior STEMI, most commonly caused by right coronary artery (RCA) occlusion.

2. Which of the following are appropriate immediate initial management steps? (Select all that apply)
A) Chewable aspirin
B) Sublingual nitroglycerin (if BP stable and no RV infarct)
C) Immediate oral beta-blocker regardless of heart failure signs
D) Urgent PCI / reperfusion evaluation
Answer: A, B, D
Explanation: Aspirin, careful nitrates, and urgent reperfusion (PCI) are cornerstones of STEMI care.

=== Standalone Questions ===
3. Which enzyme catalyzes the rate-limiting step of glycolysis?
A) Hexokinase
B) Phosphofructokinase-1 (PFK-1)
C) Pyruvate kinase
D) Lactate dehydrogenase
Answer: B
Explanation: PFK-1 converts fructose-6-phosphate to fructose-1,6-bisphosphate and is the primary regulatory step of glycolysis.

4. المفكر الذي أكد على "الحقوق الطبيعية للمواطن" في دراسته لمفهوم المواطنة هو:
أ. توماس هوبز
ب. جون لوك
ج. ماكس فيبر
د. أرسطو
الإجابة: ب
التعليل: أكد جون لوك على أن حماية الحقوق الطبيعية للمواطن (الحياة والحرية والملكية) هي أساس العقد الاجتماعي.
''';
}
