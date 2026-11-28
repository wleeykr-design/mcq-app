import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import 'lecture_analyzer.dart';
import 'mcq_parser.dart';

class GoogleGeminiConfig {
  String clientId;
  String projectId;
  String scopeMode; // 'gen' | 'cloud'
  String model;
  String accessToken;
  String refreshToken;
  int expiresAtMs;
  String userEmail;
  String userName;

  GoogleGeminiConfig({
    this.clientId = '',
    this.projectId = '',
    this.scopeMode = 'gen',
    this.model = 'gemini-2.5-flash',
    this.accessToken = '',
    this.refreshToken = '',
    this.expiresAtMs = 0,
    this.userEmail = '',
    this.userName = '',
  });

  bool get isSignedIn =>
      (accessToken.isNotEmpty && DateTime.now().millisecondsSinceEpoch < expiresAtMs) ||
      refreshToken.isNotEmpty;

  factory GoogleGeminiConfig.fromJson(Map<String, dynamic> j) => GoogleGeminiConfig(
        clientId: j['clientId']?.toString() ?? '',
        projectId: j['projectId']?.toString() ?? '',
        scopeMode: j['scopeMode']?.toString() ?? 'gen',
        model: j['model']?.toString() ?? 'gemini-2.5-flash',
        accessToken: j['accessToken']?.toString() ?? '',
        refreshToken: j['refreshToken']?.toString() ?? '',
        expiresAtMs: (j['expiresAtMs'] as num?)?.toInt() ?? 0,
        userEmail: j['userEmail']?.toString() ?? '',
        userName: j['userName']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'projectId': projectId,
        'scopeMode': scopeMode,
        'model': model,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAtMs': expiresAtMs,
        'userEmail': userEmail,
        'userName': userName,
      };
}

class GeminiOAuthService {
  static const String packageName = 'com.medquiz.mcqstudio';
  static const String redirectUri = 'com.medquiz.mcqstudio:/oauth2redirect';
  static const String certSha1 = '8B:DC:30:1D:8D:9D:A2:F6:A9:35:6E:0E:1B:58:58:2A:B1:41:E1:B2';

  static const String _prefsKey = 'medquiz_google_oauth_flutter_v1';
  static const String _verifierKey = 'medquiz_pkce_verifier';
  static const String _stateKey = 'medquiz_oauth_state';
  static const String _pendingClientKey = 'medquiz_oauth_pending_client';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  GoogleGeminiConfig config = GoogleGeminiConfig();

  Future<void> init(void Function(GoogleGeminiConfig cfg, String? error) onAuthChanged) async {
    await load();
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && initial.scheme == packageName) {
        await _handleRedirectUri(initial, onAuthChanged);
      }
    } catch (_) {}

    _linkSub?.cancel();
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == packageName) {
        _handleRedirectUri(uri, onAuthChanged);
      }
    });
  }

  void dispose() {
    _linkSub?.cancel();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          config = GoogleGeminiConfig.fromJson(decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  String _b64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<int> _randomBytes(int count) {
    final rng = Random.secure();
    return List<int>.generate(count, (_) => rng.nextInt(256));
  }

  Future<void> startSignIn({
    required String clientId,
    required String projectId,
    required String scopeMode,
    required String model,
  }) async {
    final cleanClient = clientId.trim();
    if (!cleanClient.contains('.apps.googleusercontent.com')) {
      throw Exception('أدخل Google OAuth Client ID صحيحاً ينتهي بـ .apps.googleusercontent.com');
    }
    config.clientId = cleanClient;
    config.projectId = projectId.trim();
    config.scopeMode = scopeMode;
    config.model = model;
    await save();

    final verifier = _b64UrlNoPad(_randomBytes(32));
    final challenge = _b64UrlNoPad(sha256.convert(ascii.encode(verifier)).bytes);
    final oauthState = _b64UrlNoPad(_randomBytes(16));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verifierKey, verifier);
    await prefs.setString(_stateKey, oauthState);
    await prefs.setString(_pendingClientKey, cleanClient);

    final apiScope = scopeMode == 'cloud'
        ? 'https://www.googleapis.com/auth/cloud-platform'
        : 'https://www.googleapis.com/auth/generative-language';
    final scopes = '$apiScope openid email profile';

    final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': cleanClient,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': oauthState,
    });

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw Exception('تعذر فتح متصفح النظام لتسجيل الدخول.');
    }
  }

  Future<void> _handleRedirectUri(
    Uri uri,
    void Function(GoogleGeminiConfig cfg, String? error) onAuthChanged,
  ) async {
    final err = uri.queryParameters['error'];
    if (err != null && err.isNotEmpty) {
      final desc = uri.queryParameters['error_description'] ?? '';
      onAuthChanged(config, 'فشل تسجيل الدخول بقوقل: $err ${desc.isNotEmpty ? "($desc)" : ""}');
      return;
    }

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final savedState = prefs.getString(_stateKey) ?? '';
    final verifier = prefs.getString(_verifierKey) ?? '';
    final clientId = prefs.getString(_pendingClientKey) ?? config.clientId;

    if (savedState.isNotEmpty && savedState != state) {
      onAuthChanged(config, 'تعذر التحقق من أمان الجلسة (OAuth state mismatch).');
      return;
    }

    try {
      final tokenRes = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
        },
      );
      if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
        onAuthChanged(config, 'فشل استلام توكن Google (${tokenRes.statusCode}): ${_extractError(tokenRes.body)}');
        return;
      }

      final tok = jsonDecode(tokenRes.body) as Map<String, dynamic>;
      final access = tok['access_token']?.toString() ?? '';
      final refresh = tok['refresh_token']?.toString() ?? '';
      final expiresIn = (tok['expires_in'] as num?)?.toInt() ?? 3600;

      config.accessToken = access;
      if (refresh.isNotEmpty) config.refreshToken = refresh;
      config.expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;

      try {
        final infoRes = await http.get(
          Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
          headers: {'Authorization': 'Bearer $access'},
        );
        if (infoRes.statusCode >= 200 && infoRes.statusCode < 300) {
          final info = jsonDecode(infoRes.body) as Map<String, dynamic>;
          config.userEmail = info['email']?.toString() ?? '';
          config.userName = info['name']?.toString() ?? '';
        }
      } catch (_) {}

      await prefs.remove(_verifierKey);
      await prefs.remove(_stateKey);
      await save();
      onAuthChanged(config, null);
    } catch (e) {
      onAuthChanged(config, 'خطأ أثناء إكمال تسجيل الدخول بقوقل: $e');
    }
  }

  Future<void> signOut() async {
    config.accessToken = '';
    config.refreshToken = '';
    config.expiresAtMs = 0;
    config.userEmail = '';
    config.userName = '';
    await save();
  }

  Future<String> _ensureValidToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (config.accessToken.isNotEmpty && now < config.expiresAtMs - 60000) {
      return config.accessToken;
    }
    if (config.refreshToken.isEmpty || config.clientId.isEmpty) {
      throw Exception('انتهت جلسة Google — يرجى تسجيل الدخول بحساب Google مجدداً.');
    }

    final res = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': config.refreshToken,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('تعذر تجديد الجلسة (${res.statusCode}): ${_extractError(res.body)}');
    }
    final tok = jsonDecode(res.body) as Map<String, dynamic>;
    final newAccess = tok['access_token']?.toString() ?? '';
    final expiresIn = (tok['expires_in'] as num?)?.toInt() ?? 3600;
    if (newAccess.isEmpty) throw Exception('استجابة غير مكتملة من Google OAuth.');
    config.accessToken = newAccess;
    config.expiresAtMs = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
    await save();
    return newAccess;
  }

  Future<Map<String, dynamic>> callGeminiJson(String systemPrompt, String userText) {
    return callGeminiChatJson(systemPrompt, [
      {
        'role': 'user',
        'parts': [
          {'text': userText}
        ]
      }
    ]);
  }

  Future<Map<String, dynamic>> callGeminiChatJson(
    String systemPrompt,
    List<Map<String, dynamic>> contents, {
    double temperature = 0.25,
  }) async {
    final token = await _ensureValidToken();
    final safeModel = config.model.trim().isEmpty ? 'gemini-2.5-flash' : config.model.trim();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=UTF-8',
    };
    if (config.projectId.trim().isNotEmpty) {
      headers['x-goog-user-project'] = config.projectId.trim();
    }

    final res = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$safeModel:generateContent'),
          headers: headers,
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt}
              ]
            },
            'contents': contents,
            'generationConfig': {
              'temperature': temperature,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 75));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('خطأ من Gemini API (${res.statusCode}): ${_extractError(res.body)}');
    }

    final outer = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = outer['candidates'] as List? ?? [];
    if (candidates.isEmpty) throw Exception('أرجع Gemini استجابة فارغة.');
    final parts = (candidates.first['content']?['parts'] as List?) ?? [];
    final text = parts.map((p) => p['text']?.toString() ?? '').join().trim();
    if (text.isEmpty) throw Exception('أرجع Gemini نصاً فارغاً.');
    final cleaned = text
        .replaceFirst(RegExp(r'^```json\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  Future<LectureAnalysisResult> generateFromLecture(
    AppDataState appState,
    String rawText, {
    String sourceName = 'Lecture',
  }) async {
    final clipped = rawText.trim();
    final slice = clipped.length > 32000 ? clipped.substring(0, 32000) : clipped;
    if (slice.length < 30) {
      throw Exception('النص المستخرج قصير جداً.');
    }

    const sysPrompt = 'You are an expert medical & university exam writer. '
        'Analyze the lecture text and generate high-yield MCQs and concise Flashcards in the SAME language as the lecture (Arabic or English). '
        'STRICT EXCLUSION RULES: Completely IGNORE cover slides, doctor/professor/lecturer names, university/college/department names, dates, course codes, introductions, learning objectives/ILOs, outlines, references, and thank-you slides. '
        'MCQ RULES: Generate 8 to 20 single-best-answer MCQs with 4 plausible options of similar length and style, answerIndex (0..3), difficulty (easy|medium|hard), concise topic, and brief explanation. Vary answerIndex evenly across 0,1,2,3. '
        'FLASHCARD RULES: Generate 8 to 25 crisp active-recall flashcards (front, back, topic). '
        'Return ONLY valid JSON: {"questions":[{"stem":"...","options":["A","B","C","D"],"answerIndex":0,"difficulty":"medium","topic":"...","explanation":"..."}],"flashcards":[{"front":"...","back":"...","topic":"..."}]}';

    final data = await callGeminiJson(sysPrompt, 'Source: $sourceName\n\n$slice');
    final qs = <McqQuestion>[];
    final rawQs = data['questions'] as List? ?? [];
    for (var i = 0; i < rawQs.length; i++) {
      final item = rawQs[i];
      if (item is! Map) continue;
      final opts = (item['options'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).take(6).toList() ?? [];
      if (opts.length < 2) continue;
      var ans = (item['answerIndex'] as num?)?.toInt() ?? 0;
      if (ans < 0 || ans >= opts.length) ans = 0;
      qs.add(McqParser.buildQuestion(
        appState,
        sourceNum: i + 1,
        sourceName: sourceName,
        stem: item['stem']?.toString() ?? '',
        options: opts,
        answerIndices: [ans],
        explicitTopic: item['topic']?.toString(),
        explicitDiff: item['difficulty']?.toString(),
        explanation: item['explanation']?.toString() ?? '',
      ));
    }

    final fcs = <GeneratedFlashcardDraft>[];
    final rawFcs = data['flashcards'] as List? ?? [];
    for (final item in rawFcs) {
      if (item is! Map) continue;
      final front = item['front']?.toString().trim() ?? '';
      final back = item['back']?.toString().trim() ?? '';
      final topic = item['topic']?.toString().trim() ?? sourceName;
      if (front.isNotEmpty && back.isNotEmpty) {
        fcs.add(GeneratedFlashcardDraft(front: front, back: back, hint: topic, topic: topic));
      }
    }
    return LectureAnalysisResult(qs.where((q) => q.stem.isNotEmpty).toList(), fcs);
  }

  Future<List<MicroLesson>> generateMicroCurriculum(
    AppDataState appState,
    List<SourceChunk> chunks, {
    required String sourceName,
    String language = 'bilingual',
  }) async {
    final buf = StringBuffer();
    for (final c in chunks.take(18)) {
      buf.writeln('[${c.citation}] ${c.sectionTitle}');
      buf.writeln(c.text);
      buf.writeln('---');
      if (buf.length > 26000) break;
    }

    final langRule = switch (language) {
      'ar' => 'Explain objectives, summaries, rationales, and hints in clear Arabic while keeping accurate English medical/technical terminology in parentheses.',
      'en' => 'Write all lessons, quizzes, rationales, flashcards, and games in crisp clinical English matching the source.',
      _ => 'Write concise bilingual explanations (clear Arabic explanations paired with exact English technical terminology from the source).',
    };

    final sysPrompt =
        'You are the LearnKata AI Curriculum Architect. Transform the provided source chunks into 3 to 6 sequential, bite-sized Micro-Lessons (Duolingo-style roadmap). '
        'STRICT GROUNDING: Every fact, MCQ, flashcard, match pair, and fill-in-the-blank MUST be 100% grounded in the provided chunks with exact "sourceCitation" (copied verbatim from [Citation]). Never invent outside facts or metadata slides (ignore cover/author/references). '
        '$langRule '
        'Return ONLY valid JSON: '
        '{"lessons":[{'
        '"title":"...",'
        '"topic":"...",'
        '"objective":"One clear actionable learning objective",'
        '"summary":"Concise 2-4 sentence concept summary",'
        '"keyTakeaways":["point 1","point 2","point 3"],'
        '"sourceCitation":"...",'
        '"sourceExcerpt":"short verbatim quote from source",'
        '"estimatedMinutes":4,'
        '"quizzes":[{"stem":"...","options":["A","B","C","D"],"answerIndex":0,"optionRationales":["Why A is right/wrong","Why B is right/wrong","Why C is right/wrong","Why D is right/wrong"],"explanation":"...","citation":"..."}],'
        '"flashcards":[{"front":"...","back":"...","hint":"...","citation":"..."}],'
        '"matchPairs":[{"left":"Term","right":"Mechanism/Definition","citation":"..."}],'
        '"fillBlanks":[{"sentenceWithBlank":"Sentence containing _____ blank","answer":"missing term","choices":["missing term","distractor 1","distractor 2"],"hint":"...","citation":"..."}]'
        '}]}';

    final res = await callGeminiJson(sysPrompt, 'Course Source: $sourceName\n\n$buf', );
    final rawLessons = res['lessons'] as List? ?? [];
    final out = <MicroLesson>[];
    for (var i = 0; i < rawLessons.length; i++) {
      final ml = rawLessons[i];
      if (ml is! Map) continue;
      final topic = ml['topic']?.toString().trim() ?? sourceName;
      final cite = ml['sourceCitation']?.toString().trim() ?? (chunks.isNotEmpty ? chunks.first.citation : sourceName);

      final quizzes = <McqQuestion>[];
      for (final rq in (ml['quizzes'] as List? ?? [])) {
        if (rq is! Map) continue;
        final opts = (rq['options'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).take(5).toList() ?? [];
        if (opts.length < 2) continue;
        var ans = (rq['answerIndex'] as num?)?.toInt() ?? 0;
        if (ans < 0 || ans >= opts.length) ans = 0;
        final rats = (rq['optionRationales'] as List?)?.map((e) => e.toString().trim()).toList() ?? <String>[];
        final q = McqParser.buildQuestion(
          appState,
          sourceNum: quizzes.length + 1,
          sourceName: sourceName,
          stem: rq['stem']?.toString().trim() ?? '',
          options: opts,
          answerIndices: [ans],
          explicitTopic: topic,
          explanation: rq['explanation']?.toString().trim() ?? '',
        );
        q.sourceCitation = rq['citation']?.toString().trim().isNotEmpty == true ? rq['citation'].toString().trim() : cite;
        q.optionRationales = rats;
        if (q.stem.isNotEmpty) quizzes.add(q);
      }

      final flashcards = <FlashcardItem>[];
      for (final rf in (ml['flashcards'] as List? ?? [])) {
        if (rf is! Map) continue;
        final f = rf['front']?.toString().trim() ?? '';
        final b = rf['back']?.toString().trim() ?? '';
        if (f.isNotEmpty && b.isNotEmpty) {
          flashcards.add(FlashcardItem(
            uid: appState.nextCardUid++,
            front: f,
            back: b,
            hint: rf['hint']?.toString().trim() ?? topic,
            topic: topic,
            sourceCitation: rf['citation']?.toString().trim() ?? cite,
          ));
        }
      }

      final pairs = <MatchPairItem>[];
      for (var pi = 0; pi < (ml['matchPairs'] as List? ?? []).length; pi++) {
        final rp = (ml['matchPairs'] as List)[pi];
        if (rp is! Map) continue;
        final l = rp['left']?.toString().trim() ?? '';
        final r = rp['right']?.toString().trim() ?? '';
        if (l.isNotEmpty && r.isNotEmpty) {
          pairs.add(MatchPairItem(
            id: 'mp_${i}_$pi',
            left: l,
            right: r,
            citation: rp['citation']?.toString().trim() ?? cite,
          ));
        }
      }

      final blanks = <FillBlankItem>[];
      for (var bi = 0; bi < (ml['fillBlanks'] as List? ?? []).length; bi++) {
        final rb = (ml['fillBlanks'] as List)[bi];
        if (rb is! Map) continue;
        final sent = rb['sentenceWithBlank']?.toString().trim() ?? '';
        final ans = rb['answer']?.toString().trim() ?? '';
        final choices = (rb['choices'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? [];
        if (ans.isNotEmpty && !choices.contains(ans)) choices.insert(0, ans);
        if (sent.isNotEmpty && ans.isNotEmpty && choices.isNotEmpty) {
          blanks.add(FillBlankItem(
            id: 'fb_${i}_$bi',
            sentenceWithBlank: sent,
            answer: ans,
            choices: choices,
            hint: rb['hint']?.toString().trim() ?? topic,
            citation: rb['citation']?.toString().trim() ?? cite,
          ));
        }
      }

      out.add(MicroLesson(
        id: 'ml_${DateTime.now().microsecondsSinceEpoch}_$i',
        orderIndex: i,
        title: ml['title']?.toString().trim() ?? 'Lesson ${i + 1}: $topic',
        topic: topic,
        objective: ml['objective']?.toString().trim() ?? 'Master core mechanisms of $topic',
        summary: ml['summary']?.toString().trim() ?? '',
        keyTakeaways: (ml['keyTakeaways'] as List?)?.map((e) => e.toString()).toList() ?? [],
        sourceCitation: cite,
        sourceExcerpt: ml['sourceExcerpt']?.toString().trim() ?? (chunks.isNotEmpty ? chunks.first.text : ''),
        estimatedMinutes: (ml['estimatedMinutes'] as num?)?.toInt() ?? 4,
        quizzes: quizzes,
        flashcards: flashcards,
        matchPairs: pairs,
        fillBlanks: blanks,
      ));
    }
    return out;
  }

  Future<TutorMessage> askSocraticTutor({
    required List<TutorMessage> history,
    required String userMessage,
    required List<SourceChunk> citedChunks,
    MicroLesson? activeLesson,
    String? wrongQuestionContext,
    String language = 'bilingual',
  }) async {
    final srcBuf = StringBuffer();
    if (activeLesson != null) {
      srcBuf.writeln('ACTIVE LESSON: ${activeLesson.title} [${activeLesson.sourceCitation}]');
      srcBuf.writeln('OBJECTIVE: ${activeLesson.objective}');
      if (activeLesson.sourceExcerpt.isNotEmpty) {
        srcBuf.writeln('LESSON EXCERPT: ${activeLesson.sourceExcerpt}');
      }
      srcBuf.writeln('---');
    }
    for (final c in citedChunks) {
      srcBuf.writeln('[${c.citation}] ${c.text}');
      srcBuf.writeln('---');
    }
    if (wrongQuestionContext != null && wrongQuestionContext.trim().isNotEmpty) {
      srcBuf.writeln('STUDENT CURRENT STRUGGLE / WRONG ATTEMPT: $wrongQuestionContext');
    }

    final langInstr = switch (language) {
      'ar' => 'Respond in clear, encouraging Arabic while preserving exact English medical/scientific terminology in parentheses.',
      'en' => 'Respond in crisp, encouraging clinical English.',
      _ => 'Respond in clear Arabic paired with key English medical terminology (bilingual), matching how medical students study.',
    };

    final sysPrompt =
        'You are the LearnKata Step-by-Step Socratic AI Tutor. '
        'CRITICAL PEDAGOGICAL RULES: '
        '1. TEACH, NEVER JUST DUMP THE ANSWER: When a student asks for help on a concept or got a quiz question wrong, DO NOT immediately give away the final letter/answer. '
        '2. Guide step-by-step using a relatable analogy or physiological hint, followed by ONE focused leading question prompting the student to reason out the next step. '
        '3. If the student clearly demonstrates understanding or explicitly asks after trying, affirm why it is correct. '
        '4. STRICT SOURCE GROUNDING & CITATIONS: Base EVERY claim strictly on the provided source chunks below. Cite exact source references from [brackets]. If the uploaded material does not contain an answer, say so honestly instead of hallucinating. '
        '5. $langInstr '
        'Return ONLY valid JSON: '
        '{"reply":"Your Socratic guidance + analogy + leading question ending smoothly","citations":["exact citation string 1"],"suggestedPrompt":"short helpful student reply chip e.g. أتوقع السبب هو..."}';

    final contents = <Map<String, dynamic>>[];
    contents.add({
      'role': 'user',
      'parts': [
        {'text': 'GROUNDED STUDY MATERIAL:\n$srcBuf'}
      ]
    });
    contents.add({
      'role': 'model',
      'parts': [
        {
          'text': jsonEncode({
            'reply': 'أنا جاهز لمساعدتك خطوة بخطوة بالاعتماد على مصادرك المرفوعة فقط.',
            'citations': citedChunks.map((e) => e.citation).take(2).toList(),
            'suggestedPrompt': 'أعطني تلميحاً فقط',
          })
        }
      ]
    });
    for (final m in history.take(10)) {
      contents.add({
        'role': m.role == 'user' ? 'user' : 'model',
        'parts': [
          {
            'text': m.role == 'user'
                ? m.text
                : jsonEncode({
                    'reply': m.text,
                    'citations': m.citations,
                    'suggestedPrompt': m.suggestedPrompt ?? '',
                  })
          }
        ]
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ]
    });

    final res = await callGeminiChatJson(sysPrompt, contents, temperature: 0.35);
    return TutorMessage(
      role: 'tutor',
      text: res['reply']?.toString().trim() ?? 'فكر معي في الآلية الأساسية داخل المقطع المقتبس، ما الخطوة الأولى التي تحدث؟',
      citations: (res['citations'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ??
          citedChunks.take(2).map((e) => e.citation).toList(),
      suggestedPrompt: res['suggestedPrompt']?.toString().trim(),
    );
  }

  String _extractError(String body) {
    try {
      final obj = jsonDecode(body);
      if (obj is Map) {
        if (obj['error_description'] != null) return obj['error_description'].toString();
        if (obj['error'] is Map && obj['error']['message'] != null) {
          return obj['error']['message'].toString();
        }
        if (obj['error'] != null) return obj['error'].toString();
      }
    } catch (_) {}
    return body.length > 180 ? body.substring(0, 180) : body;
  }
}
