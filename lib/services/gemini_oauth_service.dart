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

  Future<Map<String, dynamic>> callGeminiJson(String systemPrompt, String userText) async {
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
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': userText}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 65));

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
