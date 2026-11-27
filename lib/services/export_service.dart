import 'dart:convert';
import '../models/models.dart';

class ExportService {
  static String _escHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _csvCell(String s) {
    final v = s.replaceAll('"', '""');
    return RegExp(r'[,"\n\r]').hasMatch(v) ? '"$v"' : v;
  }

  static String buildExportText(
    SubjectFolder folder,
    String format, {
    bool validOnly = false,
  }) {
    final qs = validOnly ? folder.questions.where((q) => !q.hasIssue).toList() : folder.questions;
    if (qs.isEmpty) return '';

    if (format == 'json') {
      return const JsonEncoder.withIndent('  ').convert({
        'folder': folder.name,
        'exportedAt': DateTime.now().toIso8601String(),
        'cases': folder.cases.map((c) => c.toJson()).toList(),
        'questions': qs.map((q) => q.toJson()).toList(),
      });
    }

    if (format == 'csv') {
      final rows = <String>['Number,CaseId,Topic,Difficulty,Question,A,B,C,D,E,Answer,Explanation'];
      for (var i = 0; i < qs.length; i++) {
        final q = qs[i];
        final ans = q.getCorrectIndices().map((x) => kMcqLetters[x]).join(';');
        rows.add([
          '${i + 1}',
          q.caseId ?? '',
          q.topic,
          q.difficulty,
          q.stem,
          q.options.isNotEmpty ? q.options[0] : '',
          q.options.length > 1 ? q.options[1] : '',
          q.options.length > 2 ? q.options[2] : '',
          q.options.length > 3 ? q.options[3] : '',
          q.options.length > 4 ? q.options[4] : '',
          ans,
          q.explanation,
        ].map(_csvCell).join(','));
      }
      return rows.join('\n');
    }

    // Ruda or Numbered TXT
    final out = StringBuffer();
    String? lastCase;
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      if (q.caseId != null && q.caseId != lastCase) {
        final c = folder.caseById(q.caseId);
        if (c != null) {
          out.writeln('=== ${c.title} ===');
          out.writeln(c.vignette);
          out.writeln();
        }
        lastCase = q.caseId;
      }
      if (format == 'ruda') {
        out.writeln('Question: ${q.stem}');
        for (var oi = 0; oi < q.options.length; oi++) {
          out.writeln('${kMcqLetters[oi]}: ${q.options[oi]}');
        }
        final ans = q.getCorrectIndices().map((x) => kMcqLetters[x]).join(', ');
        if (ans.isNotEmpty) out.writeln('Answer: $ans');
        if (q.explanation.isNotEmpty) out.writeln('Explanation: ${q.explanation}');
      } else {
        out.writeln('${i + 1}. ${q.stem}');
        for (var oi = 0; oi < q.options.length; oi++) {
          out.writeln('${kMcqLetters[oi]}) ${q.options[oi]}');
        }
        final ans = q.getCorrectIndices().map((x) => kMcqLetters[x]).join(', ');
        if (ans.isNotEmpty) out.writeln('Answer: $ans');
        if (q.explanation.isNotEmpty) out.writeln('Explanation: ${q.explanation}');
      }
      out.writeln();
    }
    return out.toString().trim();
  }

  static String buildPrintableExamHtml(
    SubjectFolder folder, {
    String examTitle = '',
    bool includeHeader = true,
    bool separateKey = true,
    bool includeExplanations = true,
    bool includeBubbleSheet = true,
  }) {
    final qs = folder.questions.where((q) => !q.hasIssue).toList();
    final title = examTitle.trim().isEmpty ? folder.name : examTitle.trim();
    final buf = StringBuffer()
      ..writeln('<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"><style>')
      ..writeln('body{font-family:sans-serif;padding:20px;color:#0F2942;line-height:1.55;}')
      ..writeln('.hdr{border-bottom:2px solid #0F2942;padding-bottom:10px;margin-bottom:16px;}')
      ..writeln('.q{margin-bottom:14px;page-break-inside:avoid;}')
      ..writeln('.case{background:#FFFBEB;border:1px solid #C59B27;padding:10px;border-radius:8px;margin:10px 0;}')
      ..writeln('.pb{page-break-before:always;}')
      ..writeln('table{width:100%;border-collapse:collapse;font-size:13px;}th,td{border:1px solid #CBD5E1;padding:6px;text-align:center;}')
      ..writeln('</style></head><body>');

    if (includeHeader) {
      buf.writeln('<div class="hdr"><h2>Batch 27 — ${_escHtml(title)}</h2>'
          '<p>الاسم: ______________________ &nbsp;|&nbsp; الرقم الجامعي: ______________ &nbsp;|&nbsp; عدد الأسئلة: ${qs.length}</p></div>');
    }

    String? lastCase;
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      if (q.caseId != null && q.caseId != lastCase) {
        final c = folder.caseById(q.caseId);
        if (c != null) {
          buf.writeln('<div class="case"><strong>🏥 ${_escHtml(c.title)}</strong><div>${_escHtml(c.vignette)}</div></div>');
        }
        lastCase = q.caseId;
      }
      buf.writeln('<div class="q"><div><strong>${i + 1}.</strong> ${_escHtml(q.stem)}</div><ul>');
      for (var oi = 0; oi < q.options.length; oi++) {
        buf.writeln('<li><strong>${kMcqLetters[oi]})</strong> ${_escHtml(q.options[oi])}</li>');
      }
      buf.writeln('</ul></div>');
    }

    if (includeBubbleSheet) {
      buf.writeln('<div class="pb"><h3>ورقة التظليل (Bubble Sheet)</h3><table><tr><th>#</th><th>A</th><th>B</th><th>C</th><th>D</th></tr>');
      for (var i = 0; i < qs.length; i++) {
        buf.writeln('<tr><td>${i + 1}</td><td>◯</td><td>◯</td><td>◯</td><td>◯</td></tr>');
      }
      buf.writeln('</table></div>');
    }

    if (separateKey) {
      buf.writeln('<div class="pb"><h3>مفتاح الإجابات (${_escHtml(title)})</h3><table><tr><th>#</th><th>الإجابة</th>${includeExplanations ? "<th>التعليل</th>" : ""}</tr>');
      for (var i = 0; i < qs.length; i++) {
        final q = qs[i];
        final ans = q.getCorrectIndices().map((x) => kMcqLetters[x]).join(', ');
        buf.writeln('<tr><td>${i + 1}</td><td><strong>$ans</strong></td>${includeExplanations ? "<td style='text-align:right'>${_escHtml(q.explanation)}</td>" : ""}</tr>');
      }
      buf.writeln('</table></div>');
    }

    buf.writeln('</body></html>');
    return buf.toString();
  }

  static String buildFlashcardsAnkiCsv(SubjectFolder folder) {
    final rows = <String>['Front,Back,Topic'];
    for (final c in folder.flashcards) {
      rows.add([c.front, c.back, c.topic].map(_csvCell).join(','));
    }
    return rows.join('\n');
  }
}
