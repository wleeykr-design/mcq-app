import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';
import '../models/models.dart';

class FileExtractor {
  static Future<String> extractText(String filename, Uint8List bytes) async {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.docx')) {
      return _extractDocx(bytes);
    }
    if (lower.endsWith('.pptx') || lower.endsWith('.ppsx') || lower.endsWith('.potx')) {
      return _extractPptx(bytes);
    }
    if (lower.endsWith('.ppt')) {
      throw Exception('صيغة .PPT القديمة غير مدعومة مباشرة؛ احفظ العرض بصيغة .PPTX أو PDF ثم ارفعه.');
    }
    if (lower.endsWith('.pdf')) {
      return _extractPdf(bytes);
    }
    final text = _decodeSmartText(bytes);
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return _stripHtml(text);
    }
    return text;
  }

  static List<SourceChunk> parseTextIntoChunks(String sourceName, String rawText) {
    final lines = rawText
        .replaceFirst('\uFEFF', '')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .split('\n');

    final markerRe = RegExp(r'^#\s*(Slide|Page|Section)\s*(\d+)\s*:\s*(.*)$', caseSensitive: false);
    final mdHeadRe = RegExp(r'^#{1,3}\s+(.+)$');

    final chunks = <SourceChunk>[];
    String? curMarker;
    String curTitle = '';
    final curBuf = StringBuffer();

    void flushChunk() {
      final body = curBuf.toString().trim();
      curBuf.clear();
      if (body.length < 18) return;
      final cleanSource = sourceName.trim().isEmpty ? 'Notes' : sourceName.trim();
      final title = curTitle.isNotEmpty ? curTitle : (curMarker ?? 'Section ${chunks.length + 1}');
      final cite = curMarker != null
          ? '$cleanSource • $curMarker${curTitle.isNotEmpty ? ": $curTitle" : ""}'
          : '$cleanSource • ${title.isNotEmpty ? title : "Section ${chunks.length + 1}"}';
      chunks.add(SourceChunk(
        id: 'ch_${DateTime.now().microsecondsSinceEpoch}_${chunks.length}',
        sourceName: cleanSource,
        citation: cite,
        sectionTitle: title,
        text: body,
      ));
    }

    for (final raw in lines) {
      final l = raw.trim();
      final mm = markerRe.firstMatch(l);
      if (mm != null) {
        flushChunk();
        final kind = mm.group(1)!;
        final num = mm.group(2)!;
        final heading = mm.group(3)!.trim();
        curMarker = '$kind $num';
        curTitle = heading.isNotEmpty ? heading : curMarker!;
        continue;
      }
      final hm = mdHeadRe.firstMatch(l);
      if (hm != null && curBuf.length > 160) {
        flushChunk();
        curMarker = 'Section ${chunks.length + 1}';
        curTitle = hm.group(1)!.trim();
        continue;
      }
      if (l.isNotEmpty) {
        curBuf.writeln(l);
      } else if (curMarker == null && curBuf.length > 750) {
        flushChunk();
        curMarker = 'Section ${chunks.length + 1}';
        curTitle = 'Excerpt ${chunks.length + 1}';
      }
    }
    flushChunk();

    // If raw pasted text was one continuous block > 900 chars, split into balanced cited sections
    if (chunks.length <= 1 && rawText.trim().length > 900) {
      chunks.clear();
      final cleanLines = lines.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final buf = StringBuffer();
      var sec = 1;
      for (final l in cleanLines) {
        buf.writeln(l);
        if (buf.length >= 650) {
          chunks.add(SourceChunk(
            id: 'ch_${DateTime.now().microsecondsSinceEpoch}_$sec',
            sourceName: sourceName,
            citation: '$sourceName • Section $sec',
            sectionTitle: 'Section $sec',
            text: buf.toString().trim(),
          ));
          buf.clear();
          sec++;
        }
      }
      if (buf.isNotEmpty) {
        chunks.add(SourceChunk(
          id: 'ch_${DateTime.now().microsecondsSinceEpoch}_$sec',
          sourceName: sourceName,
          citation: '$sourceName • Section $sec',
          sectionTitle: 'Section $sec',
          text: buf.toString().trim(),
        ));
      }
    }

    if (chunks.isEmpty && rawText.trim().isNotEmpty) {
      chunks.add(SourceChunk(
        id: 'ch_${DateTime.now().microsecondsSinceEpoch}_0',
        sourceName: sourceName,
        citation: '$sourceName • Section 1',
        sectionTitle: sourceName,
        text: rawText.trim(),
      ));
    }
    return chunks;
  }

  static String _decodeSmartText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _stripHtml(String html) {
    var s = html.replaceAll(RegExp(r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>|</tr>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    return s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static List<String> _extractParagraphsFromXml(String xmlStr) {
    final doc = XmlDocument.parse(xmlStr);
    final lines = <String>[];
    for (final p in doc.findAllElements('*').where((e) => e.name.local == 'p')) {
      final buf = StringBuffer();
      void walk(XmlNode node) {
        if (node is XmlElement) {
          final local = node.name.local;
          if (local == 't') {
            buf.write(node.innerText);
            return;
          } else if (local == 'tab') {
            buf.write(' ');
            return;
          } else if (local == 'br' || local == 'cr') {
            buf.write('\n');
            return;
          }
        }
        for (final ch in node.children) {
          walk(ch);
        }
      }
      walk(p);
      final trimmed = buf.toString().trim();
      if (trimmed.isNotEmpty) lines.add(trimmed);
    }
    return lines;
  }

  static String _extractDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        final xmlStr = utf8.decode(file.content as List<int>);
        final paras = _extractParagraphsFromXml(xmlStr);
        if (paras.isEmpty) return '';
        final out = <String>[];
        var sec = 1;
        for (var i = 0; i < paras.length; i += 10) {
          final slice = paras.sublist(i, (i + 10 > paras.length) ? paras.length : i + 10);
          final title = slice.first.length <= 65 ? slice.first : 'Part $sec';
          out.add('# Section $sec: $title\n${slice.join('\n')}');
          sec++;
        }
        return out.join('\n\n');
      }
    }
    throw Exception('لم يتم العثور على word/document.xml داخل ملف DOCX.');
  }

  static String _extractPptx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slideRe = RegExp(r'^ppt/slides/slide(\d+)\.xml$', caseSensitive: false);
    final noteRe = RegExp(r'^ppt/notesSlides/notesSlide(\d+)\.xml$', caseSensitive: false);

    final slides = <int, List<String>>{};
    final notes = <int, List<String>>{};

    for (final file in archive) {
      final sm = slideRe.firstMatch(file.name);
      if (sm != null) {
        final num = int.parse(sm.group(1)!);
        final xmlStr = utf8.decode(file.content as List<int>);
        slides[num] = _extractParagraphsFromXml(xmlStr)
            .where((l) => !RegExp(r'^\d{1,3}$').hasMatch(l))
            .toList();
        continue;
      }
      final nm = noteRe.firstMatch(file.name);
      if (nm != null) {
        final num = int.parse(nm.group(1)!);
        final xmlStr = utf8.decode(file.content as List<int>);
        notes[num] = _extractParagraphsFromXml(xmlStr)
            .where((l) => !RegExp(r'^\d{1,3}$').hasMatch(l))
            .toList();
      }
    }

    if (slides.isEmpty) {
      throw Exception('لم يتم العثور على شرائح داخل ملف PowerPoint (.pptx).');
    }

    final keys = slides.keys.toList()..sort();
    final blocks = <String>[];
    for (final k in keys) {
      final allLines = <String>[...?slides[k], ...?notes[k]];
      if (allLines.isEmpty) continue;
      blocks.add('# Slide $k: ${allLines.first}\n${allLines.skip(1).join('\n')}');
    }
    final joined = blocks.join('\n\n').trim();
    if (joined.isEmpty) {
      throw Exception('شرائح PowerPoint فارغة أو تحتوي صوراً فقط بدون نص.');
    }
    return joined;
  }

  static String _extractPdf(Uint8List bytes) {
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final pageBlocks = <String>[];
      for (var p = 0; p < doc.pages.count; p++) {
        final pgTxt = extractor.extractText(startPageIndex: p, endPageIndex: p).trim();
        if (pgTxt.isEmpty) continue;
        final lines = pgTxt.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final firstHead = (lines.isNotEmpty && lines.first.length <= 70) ? lines.first : 'Page ${p + 1}';
        pageBlocks.add('# Page ${p + 1}: $firstHead\n$pgTxt');
      }
      doc.dispose();
      final combined = pageBlocks.join('\n\n').trim();
      if (combined.length >= 25) return combined;
    } catch (_) {}

    // Offline raw PDF stream fallback
    final latin = latin1.decode(bytes);
    final chunks = <String>[];
    final streamRe = RegExp(r'stream(?:\r\n|\n|\r)([\s\S]*?)endstream');
    for (final m in streamRe.allMatches(latin)) {
      final raw = m.group(1) ?? '';
      final btRe = RegExp(r'BT[\s\S]*?ET');
      for (final bm in btRe.allMatches(raw)) {
        final block = bm.group(0) ?? '';
        final litRe = RegExp(r'\(((?:\\.|[^\\()])*)\)');
        final line = litRe.allMatches(block).map((x) => x.group(1) ?? '').join(' ').trim();
        if (line.isNotEmpty) chunks.add(line);
      }
    }
    final fallback = chunks.join('\n').trim();
    if (fallback.length >= 25) return '# Page 1: Document\n$fallback';
    throw Exception('ملف PDF هذا مصوّر (Scanned) أو لا يحتوي طبقة نصية قابلة للاستخراج.');
  }
}
