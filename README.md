# Batch 27 MCQ Studio — Flutter Edition (v6.0.0)

إعادة بناء كاملة لتطبيق **Batch 27 — منصة أسئلة MCQ** بلغة **Dart / Flutter** مع الحفاظ على جميع المميزات:

## المميزات المدمجة
- **مجلدات المواد الدراسية**: فصل كامل للأسئلة والحالات السريرية والفلاش كاردز، مع حفظ تلقائي ونسخ احتياطي JSON شامل.
- **قراءة الشيتات والملفات**: استخراج النصوص من `.pdf` (`syncfusion_flutter_pdf` + محرك احتياطي)، و`.pptx/.ppsx/.potx` (مع ملاحظات المحاضر)، و`.docx`، و`.txt/.csv/.json/.html`.
- **محرك التحليل المحلي الذكي (`LectureAnalyzer`)**: تصفية الترويسات المتكررة وأسماء الدكاترة/الكليات والمقدمات والأهداف والمراجع تلقائياً، وتوليد فلاش كاردز وMCQ متوازنة (شاملة أسئلة *ما عدا EXCEPT* ومشتتات متناسقة الطول).
- **ربط Gemini بحساب Google (`OAuth 2.0 PKCE`)**: تسجيل دخول آمن عبر `com.medquiz.mcqstudio:/oauth2redirect` مع تجديد تلقائي للتوكن واستخراج ذكي بـ `gemini-2.5-flash` / `gemini-2.5-pro`.
- **منظومة الاختبار المتكاملة**: وضع التدريب الفوري (بإشعار تصحيح مضمّن لا يغطي الأزرار)، وضع الامتحان، المؤقت، الحالات السريرية المتتابعة، الأسئلة متعددة الإجابات، والمؤثرات الصوتية الأصلية.
- **خطة المذاكرة + الفلاش كاردز 3D + تذكيرات الأندرويد**: تقليب ثلاثي الأبعاد، تحويل الأسئلة والأخطاء إلى بطاقات، وتذكيرات مجدولة عبر `AlarmManager` + `ReminderReceiver`.
- **التصدير والطباعة ومصحح الأجوبة**: تصدير TXT/CSV/JSON/Anki CSV، طباعة ورقة امتحان A4 بمفتاح إجابات منفصل، وتقارير التوازن.

## طريقة البناء إلى APK
### 1. تلقائياً عبر GitHub Actions (موصى به)
ارفع مجلد `batch27_flutter` إلى مستودع GitHub، وسيتولى ملف `.github/workflows/build_apk.yml` تنفيذ `flutter pub get` و`flutter analyze` و`flutter build apk --release` وإرفاق الـ APK جاهزاً للتحميل.

### 2. محلياً على جهاز كمبيوتر مثبت عليه Flutter SDK
```bash
flutter create --platforms android --org com.medquiz --project-name batch27_flutter .
flutter pub get
flutter build apk --release
```
*(تأكد من عدم استبدال ملفات `android/app/src/main/` أو `android/app/build.gradle.kts` عند تشغيل `flutter create`، أو شغّل `flutter create` في مجلد مؤقت لنسخ `gradlew` و`gradle/wrapper` فقط كما في ملف GitHub Actions).*
