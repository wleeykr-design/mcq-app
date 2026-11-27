import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'mcq_parser.dart';

class GeneratedFlashcardDraft {
  final String front;
  final String back;
  final String hint;
  final String topic;
  GeneratedFlashcardDraft({
    required this.front,
    required this.back,
    required this.hint,
    required this.topic,
  });
}

class LectureAnalysisResult {
  final List<McqQuestion> questions;
  final List<GeneratedFlashcardDraft> flashcards;
  LectureAnalysisResult(this.questions, this.flashcards);
}

class _PairFact {
  final String term;
  final String def;
  final String topic;
  final String kind;
  _PairFact(this.term, this.def, this.topic, this.kind);
}

class _ListFact {
  final String heading;
  final List<String> items;
  final String topic;
  _ListFact(this.heading, this.items, this.topic);
}

class LectureAnalyzer {
  static LectureAnalysisResult analyze(
    AppDataState appState,
    String rawText, {
    String sourceName = 'Lecture',
  }) {
    final rawLines = rawText
        .replaceFirst('\uFEFF', '')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .split('\n')
        .map((l) => l.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final lineFreq = <String, int>{};
    for (final l in rawLines) {
      if (RegExp(r'^#\s*Slide\s*\d+\s*:', caseSensitive: false).hasMatch(l)) continue;
      final nl = McqParser.normalizeStem(l);
      if (nl.isNotEmpty && l.length <= 75) {
        lineFreq[nl] = (lineFreq[nl] ?? 0) + 1;
      }
    }

    bool isNoiseOrMetaLine(String l) {
      if (l.length < 3) return true;
      if (RegExp(r'^(?:page|slide)\s*\d+(?:\s*(?:of|/)\s*\d+)?$', caseSensitive: false).hasMatch(l)) return true;
      if (RegExp(r'^\d{1,3}\s*(?:/\s*\d{1,3})?$').hasMatch(l)) return true;
      if (RegExp(r'^(?:https?://|www\.|mailto:)', caseSensitive: false).hasMatch(l)) return true;
      if (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+').hasMatch(l)) return true;
      if (RegExp(r'^(?:©|\(c\)|all rights reserved)', caseSensitive: false).hasMatch(l)) return true;
      if (RegExp(r'^(?:fig(?:ure)?|table|chart|diagram|image|ref(?:erences?)?)\s*\.?\s*\d*\s*:?\s*$', caseSensitive: false).hasMatch(l)) return true;

      final nl = McqParser.normalizeStem(l);
      if (nl.isNotEmpty && l.length <= 75 && (lineFreq[nl] ?? 0) >= 3) return true;

      if (RegExp(r'^(?:dr|prof|mr|mrs|ms|eng)\.?\s+[a-z]', caseSensitive: false).hasMatch(l)) return true;
      if (RegExp(r'^(?:د|أ\.د|أ|م|بروف|دكتور|الدكتور|أستاذ|الأستاذ|محاضر|المحاضر)\.?\s+[\u0600-\u06FF]').hasMatch(l)) return true;
      if (RegExp(r'^(?:prepared\s*by|presented\s*by|taught\s*by|lecturer|instructor|professor|faculty|presenter|author|supervised\s*by|submitted\s*by|department\s*of|dept\.?\s*of|faculty\s*of|school\s*of|college\s*of|university\s*of|course\s*(?:name|title|code)|subject|module|semester|academic\s*year|batch|date|lecture\s*(?:no|number|#)|session)\b\s*[:\-–—]?', caseSensitive: false).hasMatch(l)) return true;
      if (RegExp(r'^(?:إعداد|اعداد|تقديم|إشراف|اشراف|شرح|محاضرة|المحاضرة|المادة|المقرر|اسم\s*المادة|اسم\s*الدكتور|أستاذ\s*المادة|دكتور\s*المادة|كلية|جامعة|قسم|الفرقة|الدفعة|المستوى|الفصل\s*الدراسي|العام\s*الدراسي|التاريخ|بواسطة)\b\s*[:\-–—]?').hasMatch(l)) return true;
      if (l.length < 95 && RegExp(r'(?:faculty\s+of\s+medicine|university\s+of|college\s+of\s+medicine|كلية\s+الطب|جامعة\s+[\u0600-\u06FF]+|العلوم\s+الصحية|شكراً\s+لحسن|thank\s+you(?:\s+for\s+(?:listening|your\s+attention))?|any\s+questions\s*\??)', caseSensitive: false).hasMatch(l)) return true;
      return false;
    }

    bool isSkipSectionHeading(String h) {
      final clean = h.replaceAll(RegExp(r'[:\-–—]+$'), '').trim();
      return RegExp(
        r'^(?:learning\s+objectives?|objectives?|intended\s+learning\s+outcomes?|ilos?|outcomes?|outline|agenda|table\s+of\s+contents?|contents?|syllabus|overview|references?|bibliography|further\s+reading|acknowledg?ments?|thank\s+you|q\s*&\s*a|questions?\s*\??|contact(?:\s+info)?|الأهداف|أهداف\s+المحاضرة|الأهداف\s+التعليمية|مخرجات\s+التعلم|عناصر\s+المحاضرة|محتويات\s+المحاضرة|الفهرس|المراجع|المصادر|شكراً(?:\s+لكم)?|شكر\s+وتقدير|أسئلة\s*؟?)$',
        caseSensitive: false,
      ).hasMatch(clean);
    }

    bool isIntroHeading(String h) {
      final clean = h.replaceAll(RegExp(r'[:\-–—]+$'), '').trim();
      return RegExp(r'^(?:introduction|intro|welcome|background|overview|مقدمة|تمهيد|مدخل|نبذة\s+عامة)$', caseSensitive: false).hasMatch(clean);
    }

    bool isMetaKey(String k) {
      final clean = k.replaceAll(RegExp(r'[:\-–—]+$'), '').trim();
      if (clean.length < 2 || clean.length > 62) return true;
      if (RegExp(
        r'^(?:dr|prof|lecturer|instructor|presenter|prepared\s*by|presented\s*by|author|department|faculty|university|college|course|subject|module|batch|semester|year|date|time|email|phone|slide|page|fig|figure|table|note|notes|example|examples|e\.g|i\.e|reference|references|objective|objectives|outline|introduction|intro|summary|conclusion|د|أ\.د|دكتور|أستاذ|إعداد|تقديم|إشراف|المادة|المقرر|كلية|جامعة|قسم|الفرقة|الدفعة|التاريخ|ملاحظة|تنبيه|مثال|أمثلة|مراجع|المراجع|مقدمة|تمهيد|أهداف|الأهداف|الخلاصة|ملخص)$',
        caseSensitive: false,
      ).hasMatch(clean)) return true;
      if (RegExp(r'^(?:in\s+this|we\s+will|today\s+we|this\s+lecture|by\s+the\s+end|في\s+هذه\s+المحاضرة|سنتناول|سنتعرف|بنهاية\s+المحاضرة)', caseSensitive: false).hasMatch(clean)) return true;
      return false;
    }

    bool isWeakIntroSentence(String s) {
      return RegExp(
        r'(?:in\s+this\s+(?:lecture|session|chapter|course)|we\s+(?:will|shall)\s+(?:discuss|cover|learn|study|explore)|by\s+the\s+end\s+of\s+this|welcome\s+to|objectives?\s+of\s+this|في\s+هذه\s+المحاضرة|سنتناول\s+في|سنتعرف\s+على|تهدف\s+هذه\s+المحاضرة|بنهاية\s+هذه\s+المحاضرة|أهلاً\s+بكم)',
        caseSensitive: false,
      ).hasMatch(s);
    }

    final cleanLines = rawLines.where((l) => RegExp(r'^#\s*Slide\s*\d+\s*:', caseSensitive: false).hasMatch(l) || !isNoiseOrMetaLine(l)).toList();

    String cleanBulletPrefix(String s) => s
        .replaceFirst(RegExp(r'^[•●▪▫‣◦▸►◆◇✓✔☑*+\-]+\s*'), '')
        .replaceFirst(RegExp(r'^\d{1,2}\s*[.)\-:]\s+'), '')
        .trim();

    bool isBullet(String s) => RegExp(r'^[•●▪▫‣◦▸►◆◇✓✔☑*]|^-\s+|\d{1,2}\s*[.)\-:]\s+').hasMatch(s);

    var curTopic = sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    if (curTopic.length > 42) curTopic = curTopic.substring(0, 42);
    if (curTopic.isEmpty) curTopic = 'محاضرة';

    final pairs = <_PairFact>[];
    final lists = <_ListFact>[];
    final seenFacts = <String>{};

    void addPair(String term, String def, String topic, [String kind = 'kv']) {
      final t = term.replaceFirst(RegExp(r'^#+\s*'), '').replaceFirst(RegExp(r'[:\-–—=؛;]+$'), '').trim();
      final d = def.replaceFirst(RegExp(r'^[:\-–—=؛;]+'), '').trim();
      if (isMetaKey(t) || isWeakIntroSentence(t) || isWeakIntroSentence(d) || isNoiseOrMetaLine(d)) return;
      if (t.length < 2 || t.length > 68 || d.length < 8 || d.length > 360) return;
      if (t.split(RegExp(r'\s+')).length > 9) return;
      if (McqParser.normalizeStem(t) == McqParser.normalizeStem(d)) return;
      final k = McqParser.normalizeStem('$t|$d');
      if (seenFacts.contains(k)) return;
      seenFacts.add(k);
      pairs.add(_PairFact(t, d, topic.isNotEmpty ? topic : curTopic, kind));
    }

    var skipCurrentSlide = false;
    var inIntroSlide = false;
    var skipNextMetaLine = false;
    var pendingHeading = '';
    final pendingBullets = <String>[];

    void flushBullets() {
      if (pendingHeading.isNotEmpty &&
          !isSkipSectionHeading(pendingHeading) &&
          !isIntroHeading(pendingHeading) &&
          !isMetaKey(pendingHeading) &&
          pendingBullets.length >= 2) {
        final cleanItems = pendingBullets
            .where((it) => it.length >= 6 && it.length <= 150 && !isWeakIntroSentence(it) && !isNoiseOrMetaLine(it))
            .toList();
        if (cleanItems.length >= 2) {
          lists.add(_ListFact(pendingHeading, cleanItems, curTopic));
        }
      }
      pendingHeading = '';
      pendingBullets.clear();
    }

    for (final line in cleanLines) {
      final slideM = RegExp(r'^#\s*Slide\s*(\d+)\s*:\s*(.+)$', caseSensitive: false).firstMatch(line);
      if (slideM != null) {
        flushBullets();
        skipNextMetaLine = false;
        final slideNo = int.parse(slideM.group(1)!);
        final heading = slideM.group(2)!.trim().replaceFirst(RegExp(r'[:\-]+$'), '').trim();
        skipCurrentSlide = isSkipSectionHeading(heading);
        inIntroSlide = isIntroHeading(heading);
        if (slideNo == 1 && (isNoiseOrMetaLine(heading) || isSkipSectionHeading(heading))) {
          skipCurrentSlide = true;
        }
        if (!skipCurrentSlide && !inIntroSlide && heading.isNotEmpty && heading.length <= 70 && !isMetaKey(heading)) {
          curTopic = heading;
          pendingHeading = curTopic;
        } else {
          pendingHeading = '';
        }
        continue;
      }

      if (skipCurrentSlide) continue;

      if (RegExp(r'^(?:prepared\s*by|presented\s*by|taught\s*by|lecturer|instructor|professor|author|supervised\s*by|إعداد|اعداد|تقديم|إشراف|اشراف|شرح|أستاذ\s*المادة|دكتور\s*المادة)\s*[:\-–—]?\s*$', caseSensitive: false).hasMatch(line)) {
        skipNextMetaLine = true;
        continue;
      }
      if (skipNextMetaLine) {
        skipNextMetaLine = false;
        if (line.split(RegExp(r'\s+')).length <= 6 && !RegExp(r'[.:؟?]$').hasMatch(line)) continue;
      }

      final stripped = cleanBulletPrefix(line);
      if (stripped.isEmpty || isWeakIntroSentence(stripped) || isNoiseOrMetaLine(stripped)) continue;

      final sepM = RegExp(r'^(.{2,64}?)\s*(?:::|\t|\|\s*|=>|->|؛)\s*(.{8,})$').firstMatch(line);
      if (sepM != null) {
        flushBullets();
        addPair(cleanBulletPrefix(sepM.group(1)!), sepM.group(2)!.trim(), curTopic, 'kv');
        continue;
      }

      final kvM = RegExp(r'^([^:–—]{2,58}?)\s*(?::|—|–)\s+(.{8,})$').firstMatch(line);
      if (kvM != null && !RegExp(r'^(?:http|slide\s*\d+|page\s*\d+)', caseSensitive: false).hasMatch(kvM.group(1)!)) {
        final kCand = cleanBulletPrefix(kvM.group(1)!);
        final vCand = kvM.group(2)!.trim();
        if (!isMetaKey(kCand) && !RegExp(r'[.؟?]$').hasMatch(kCand)) {
          flushBullets();
          addPair(kCand, vCand, curTopic, 'kv');
          continue;
        }
      }

      final enDef = RegExp(r'^([A-Za-z][A-Za-z0-9\s\-()/]{1,54}?)\s+(?:is\s+defined\s+as|refers\s+to|means|denotes|is\s+(?:a|an|the))\s+(.{10,}\.?)$', caseSensitive: false).firstMatch(stripped);
      if (enDef != null) {
        addPair(enDef.group(1)!, enDef.group(2)!.replaceFirst(RegExp(r'\.$'), ''), curTopic, 'def');
      } else {
        final arDef = RegExp(r'^(?:يُ?عرف\s+|المقصود\s+بـ?\s*)?([\u0600-\u06FF][\u0600-\u06FF\s]{2,48}?)\s+(?:هو|هي|بأنه|بأنها|تتمثل\s+في|عبارة\s+عن|يُعرف\s+بأنه)\s+(.{10,})$').firstMatch(stripped);
        if (arDef != null) {
          addPair(arDef.group(1)!, arDef.group(2)!, curTopic, 'def');
        }
      }

      final ruleM = RegExp(r'^(?:The\s+)?(?:most\s+common|main|primary|gold\s+standard|drug\s+of\s+choice|first[- ]line|treatment\s+of\s+choice|hallmark|classic\s+feature|diagnostic\s+test|major\s+cause)\s+(?:cause|test|therapy|treatment|agent|feature|sign|symptom|finding|enzyme|marker)?\s*(?:of|for|in)\s+([^:]{3,52}?)\s+(?:is|are)\s+(.{3,100})$', caseSensitive: false).firstMatch(stripped);
      if (ruleM != null) {
        final subj = stripped.split(RegExp(r'\s+(?:is|are)\s+', caseSensitive: false)).first;
        addPair(subj, ruleM.group(2)!.replaceFirst(RegExp(r'\.$'), ''), curTopic, 'feature');
      } else {
        final enRel = RegExp(r'^([A-Za-z][A-Za-z0-9\s\-()/]{2,48}?)\s+(causes|leads to|results in|inhibits|blocks|stimulates|activates|treats|prevents|produces|consists of|is characterized by|is contraindicated in)\s+(.{6,120}?)\.?$', caseSensitive: false).firstMatch(stripped);
        if (enRel != null) {
          addPair('${enRel.group(1)!.trim()} (${enRel.group(2)!.toLowerCase()})', enRel.group(3)!.trim(), curTopic, 'mechanism');
        } else {
          final arRel = RegExp(r'^([\u0600-\u06FF][\u0600-\u06FF\s]{2,46}?)\s+(?:يؤدي إلى|تؤدي إلى|يسبب|تسبب|ينتج عن|تنتج عن|يعالج بـ|يتميز بـ|تتميز بـ|يتكون من|تتكون من|يثبط|يمنع)\s+(.{6,130})$').firstMatch(stripped);
          if (arRel != null) {
            addPair(arRel.group(1)!.trim(), arRel.group(2)!.trim(), curTopic, 'mechanism');
          }
        }
      }

      if (isBullet(line)) {
        if (!inIntroSlide && stripped.length >= 6) {
          if (pendingHeading.isEmpty) pendingHeading = curTopic;
          pendingBullets.add(stripped);
        }
      } else {
        final wordCount = line.split(RegExp(r'\s+')).length;
        if (wordCount <= 7 && line.length <= 62 && !RegExp(r'[.؟?,;]$').hasMatch(line)) {
          flushBullets();
          final cleanHead = line.replaceFirst(RegExp(r'[:\-–—]+$'), '').trim();
          skipCurrentSlide = isSkipSectionHeading(cleanHead);
          inIntroSlide = isIntroHeading(cleanHead);
          if (!skipCurrentSlide && !inIntroSlide && cleanHead.length >= 3 && !isMetaKey(cleanHead)) {
            curTopic = cleanHead;
            pendingHeading = cleanHead;
          }
        } else {
          flushBullets();
        }
      }
    }
    flushBullets();

    // Flashcards
    final flashcards = <GeneratedFlashcardDraft>[];
    final fcSeen = <String>{};
    for (final p in pairs) {
      final fk = McqParser.normalizeStem(p.term);
      if (fcSeen.add(fk)) {
        flashcards.add(GeneratedFlashcardDraft(front: p.term, back: p.def, hint: p.topic, topic: p.topic));
      }
    }
    for (final l in lists) {
      final headingClean = l.heading.replaceFirst(RegExp(r'[:\-–—]+$'), '').trim();
      final front = detectTextDirection(headingClean) == TextDirection.rtl
          ? 'ما هي أبرز نقاط ($headingClean)؟'
          : 'Key points: $headingClean';
      final fk = McqParser.normalizeStem(front);
      if (l.items.length >= 2 && fcSeen.add(fk)) {
        flashcards.add(GeneratedFlashcardDraft(
          front: front,
          back: l.items.take(7).map((it) => '• $it').join('\n'),
          hint: l.topic,
          topic: l.topic,
        ));
      }
    }

    // MCQs
    final rng = Random();
    final questions = <McqQuestion>[];
    final allTerms = pairs.map((p) => p.term).toList();
    final allDefs = pairs.map((p) => p.def).toList();
    final allListEntries = [
      for (final l in lists)
        for (final it in l.items) {'text': it, 'heading': l.heading}
    ];
    final slotUsage = [0, 0, 0, 0];

    List<String> pickMatchedDistractors(String correctText, List<String> candItems, List<String> excludeArr) {
      final cDir = detectTextDirection(correctText);
      final cLen = correctText.length;
      final used = <String>{McqParser.normalizeStem(correctText)};
      for (final ex in excludeArr) {
        used.add(McqParser.normalizeStem(ex));
      }

      List<String> collect(bool checkLen) {
        final out = <String>[];
        final shuffled = [...candItems]..shuffle(rng);
        for (final txt in shuffled) {
          if (out.length >= 3) break;
          if (detectTextDirection(txt) != cDir) continue;
          final n = McqParser.normalizeStem(txt);
          if (n.isEmpty || used.contains(n) || txt.length > 135) continue;
          if (checkLen) {
            final ratio = txt.length / max(1, cLen);
            if (ratio < 0.35 || ratio > 2.6) continue;
          }
          used.add(n);
          out.add(txt);
        }
        return out;
      }

      final out = collect(true);
      if (out.length < 3) {
        for (final x in collect(false)) {
          if (out.length >= 3) break;
          out.add(x);
        }
      }
      return out;
    }

    McqQuestion packBalancedMcq(String stem, String correctOpt, List<String> distOpts, String topic, String exp) {
      final minCnt = slotUsage.reduce(min);
      final minSlots = [for (var i = 0; i < 4; i++) if (slotUsage[i] == minCnt) i];
      final ansIdx = minSlots[rng.nextInt(minSlots.length)];
      slotUsage[ansIdx]++;
      final opts = [...distOpts]..insert(ansIdx, correctOpt);
      return McqParser.buildQuestion(
        appState,
        sourceNum: questions.length + 1,
        sourceName: sourceName,
        stem: stem,
        options: opts,
        answerIndices: [ansIdx],
        explicitTopic: topic,
        explicitDiff: 'medium',
        explanation: exp,
      );
    }

    for (final p in pairs) {
      if (questions.length >= 45) break;
      final isRtl = detectTextDirection(p.def) == TextDirection.rtl;

      if (p.term.length <= 48 && p.def.length >= 14) {
        final dists = pickMatchedDistractors(p.term, allTerms, [p.def]);
        if (dists.length == 3) {
          final stem = isRtl
              ? 'أيّ من الآتي يطابق الوصف التالي:\n«${p.def}»؟'
              : 'Which of the following best matches:\n"${p.def}"?';
          questions.add(packBalancedMcq(stem, p.term, dists, p.topic, '${p.term}: ${p.def}'));
          continue;
        }
      }

      if (p.def.length <= 130) {
        final dists = pickMatchedDistractors(p.def, allDefs, [p.term]);
        if (dists.length == 3) {
          final stem = detectTextDirection(p.term) == TextDirection.rtl
              ? 'بخصوص (${p.term})، أي العبارات التالية صحيحة؟'
              : 'Regarding "${p.term}", which of the following is accurate?';
          questions.add(packBalancedMcq(stem, p.def, dists, p.topic, '${p.term}: ${p.def}'));
        }
      }
    }

    for (final l in lists) {
      if (questions.length >= 55) break;
      final validItems = l.items.where((it) => it.length >= 6 && it.length <= 120).toList();
      if (validItems.isEmpty) continue;
      final isRtl = detectTextDirection(l.heading) == TextDirection.rtl;
      final otherTexts = allListEntries
          .where((e) => McqParser.normalizeStem(e['heading']!) != McqParser.normalizeStem(l.heading))
          .map((e) => e['text']!)
          .toList();

      if (validItems.length >= 4 && otherTexts.isNotEmpty) {
        final wrongItem = otherTexts.firstWhere(
          (t) =>
              detectTextDirection(t) == (isRtl ? TextDirection.rtl : TextDirection.ltr) &&
              t.length >= 6 &&
              t.length <= 120 &&
              !l.items.any((x) => McqParser.normalizeStem(x) == McqParser.normalizeStem(t)),
          orElse: () => '',
        );
        if (wrongItem.isNotEmpty) {
          final threeTrue = validItems.take(3).toList();
          final stem = isRtl
              ? 'كل مما يلي يرتبط بـ (${l.heading}) ما عدا:'
              : 'All of the following are associated with "${l.heading}" EXCEPT:';
          questions.add(packBalancedMcq(stem, wrongItem, threeTrue, l.topic, '${l.heading}: ${validItems.take(4).join(" • ")}'));
          continue;
        }
      }

      final validItem = validItems.first;
      final dists = pickMatchedDistractors(validItem, otherTexts, l.items);
      if (dists.length == 3) {
        final stem = isRtl
            ? 'أيّ من الآتي يندرج ضمن (${l.heading})؟'
            : 'Which of the following is associated with "${l.heading}"?';
        questions.add(packBalancedMcq(stem, validItem, dists, l.topic, '${l.heading}: ${l.items.take(4).join(" • ")}'));
      }
    }

    if (questions.length < 3 && pairs.length >= 2) {
      final limit = min(pairs.length, 8);
      for (var idx = 0; idx < limit; idx++) {
        final p = pairs[idx];
        final isRtl = detectTextDirection('${p.term} ${p.def}') == TextDirection.rtl;
        var shownDef = p.def;
        var ansIdx = 0;
        if (idx.isOdd) {
          final swap = pairs.where((other) =>
              other != p &&
              detectTextDirection(other.def) == detectTextDirection(p.def) &&
              McqParser.normalizeStem(other.def) != McqParser.normalizeStem(p.def));
          if (swap.isNotEmpty) {
            shownDef = swap.first.def;
            ansIdx = 1;
          }
        }
        final stem = isRtl
            ? 'صح أم خطأ — بخصوص (${p.term}):\n«$shownDef»'
            : 'True or False — regarding "${p.term}":\n"$shownDef"';
        final opts = isRtl ? ['صحيح', 'خطأ'] : ['True', 'False'];
        questions.add(McqParser.buildQuestion(
          appState,
          sourceNum: questions.length + 1,
          sourceName: sourceName,
          stem: stem,
          options: opts,
          answerIndices: [ansIdx],
          explicitTopic: p.topic,
          explicitDiff: 'easy',
          explanation: '${p.term}: ${p.def}',
        ));
      }
    }

    return LectureAnalysisResult(questions, flashcards);
  }
}
