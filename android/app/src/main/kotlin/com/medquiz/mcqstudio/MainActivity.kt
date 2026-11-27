package com.medquiz.mcqstudio

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.Settings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.medquiz.mcqstudio/native"
        private const val SAVE_FILE_REQ = 2101
        private const val NOTIF_PERM_REQ = 2102
    }

    private var channel: MethodChannel? = null
    private var pendingSaveContent: String = ""
    private var pendingSaveResult: MethodChannel.Result? = null
    private var printWebView: WebView? = null
    private var pendingOpenTab: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleOpenIntent(intent)
        ReminderReceiver.ensureChannel(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleOpenIntent(intent)
    }

    private fun handleOpenIntent(intent: Intent?) {
        val tab = intent?.getStringExtra("open_tab")
        if (!tab.isNullOrEmpty()) {
            pendingOpenTab = tab
            channel?.invokeMethod("openTab", tab)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingTab" -> {
                    val t = pendingOpenTab
                    pendingOpenTab = null
                    result.success(t)
                }
                "getNotifStatus" -> result.success(getNotifStatus())
                "openNotifSettings" -> {
                    openNotifSettings()
                    result.success(true)
                }
                "scheduleReminder" -> {
                    ensureNotifPermission()
                    val triggerAtMs = (call.argument<Number>("triggerAtMs")?.toLong()) ?: 0L
                    val intervalMs = (call.argument<Number>("intervalMs")?.toLong()) ?: 0L
                    val title = call.argument<String>("title") ?: "Batch 27 — تذكير المراجعة"
                    val body = call.argument<String>("body") ?: "حان وقت مراجعة الفلاش كاردز 🃏"
                    ReminderReceiver.scheduleAlarm(this, triggerAtMs, intervalMs, title, body)
                    result.success(getNotifStatus())
                }
                "cancelReminder" -> {
                    ReminderReceiver.cancelAlarm(this)
                    result.success(true)
                }
                "testNotification" -> {
                    val st = getNotifStatus()
                    if (st == "no_perm") {
                        ensureNotifPermission()
                        result.success("asking")
                    } else if (st == "blocked" || st == "channel_muted") {
                        result.success(st)
                    } else {
                        val title = call.argument<String>("title") ?: "Batch 27 — تذكير تجريبي"
                        val body = call.argument<String>("body") ?: "الإشعارات تعمل بنجاح 🔔"
                        ReminderReceiver.showNotification(this, title, body)
                        result.success(st)
                    }
                }
                "saveFile" -> {
                    val filename = call.argument<String>("filename") ?: "batch27-export.txt"
                    val content = call.argument<String>("content") ?: ""
                    startSaveDocument(filename, content, result)
                }
                "printHtml" -> {
                    val html = call.argument<String>("html") ?: ""
                    val jobName = call.argument<String>("jobName") ?: "Batch27-Exam"
                    printHtml(html, jobName)
                    result.success(true)
                }
                "playSound" -> {
                    val kind = call.argument<String>("kind") ?: "correct"
                    playSynthTone(kind)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureNotifPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), NOTIF_PERM_REQ)
                return false
            }
        }
        return true
    }

    private fun getNotifStatus(): String {
        ReminderReceiver.ensureChannel(this)
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                return "no_perm"
            }
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return "ok"
        if (Build.VERSION.SDK_INT >= 24 && !nm.areNotificationsEnabled()) return "blocked"
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = nm.getNotificationChannel(ReminderReceiver.CHANNEL_ID)
            if (ch != null) {
                if (ch.importance == NotificationManager.IMPORTANCE_NONE) return "channel_muted"
                if (ch.importance < NotificationManager.IMPORTANCE_HIGH) return "no_heads_up"
            }
        }
        return "ok"
    }

    private fun openNotifSettings() {
        ReminderReceiver.ensureChannel(this)
        try {
            val intent = if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, ReminderReceiver.CHANNEL_ID)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            } catch (_: Exception) {}
        }
    }

    private fun startSaveDocument(filename: String, content: String, result: MethodChannel.Result) {
        pendingSaveContent = content
        pendingSaveResult = result
        val lower = filename.lowercase()
        val mime = when {
            lower.endsWith(".html") -> "text/html"
            lower.endsWith(".json") -> "application/json"
            lower.endsWith(".csv") -> "text/csv"
            else -> "text/plain"
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        try {
            startActivityForResult(intent, SAVE_FILE_REQ)
        } catch (e: Exception) {
            pendingSaveResult?.success(false)
            pendingSaveResult = null
            Toast.makeText(this, "تعذر فتح نافذة حفظ الملف", Toast.LENGTH_SHORT).show()
        }
    }

    private fun printHtml(htmlContent: String, jobName: String) {
        runOnUiThread {
            try {
                val pv = WebView(this)
                pv.settings.javaScriptEnabled = false
                printWebView = pv
                pv.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String) {
                        try {
                            val pm = getSystemService(Context.PRINT_SERVICE) as? PrintManager
                            if (pm != null) {
                                pm.print(
                                    jobName,
                                    view.createPrintDocumentAdapter(jobName),
                                    PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).build()
                                )
                            }
                        } catch (e: Exception) {
                            Toast.makeText(this@MainActivity, "تعذر بدء الطباعة: ${e.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                }
                pv.loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
            } catch (e: Exception) {
                Toast.makeText(this, "خطأ في الطباعة: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun playSynthTone(kind: String) {
        Thread {
            try {
                val sr = 22050
                val notes: List<Pair<Double, Int>> = when (kind) {
                    "correct" -> listOf(523.25 to 95, 659.25 to 95, 783.99 to 170)
                    "wrong" -> listOf(230.0 to 120, 165.0 to 180)
                    "notify" -> listOf(880.0 to 100, 1108.73 to 120, 1318.51 to 180)
                    else -> listOf(420.0 to 45)
                }
                val totalSamples = notes.sumOf { (sr * it.second) / 1000 }
                val pcm = ShortArray(totalSamples)
                var pos = 0
                for ((freq, ms) in notes) {
                    val count = (sr * ms) / 1000
                    for (i in 0 until count) {
                        val t = i.toDouble() / sr
                        val env = exp(-4.5 * i / count.toDouble())
                        val sample = sin(2.0 * PI * freq * t) * env * 0.35
                        pcm[pos++] = (sample * Short.MAX_VALUE).toInt().toShort()
                    }
                }
                val track = if (Build.VERSION.SDK_INT >= 21) {
                    AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(sr)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .build()
                        )
                        .setBufferSizeInBytes(pcm.size * 2)
                        .setTransferMode(AudioTrack.MODE_STATIC)
                        .build()
                } else {
                    @Suppress("DEPRECATION")
                    AudioTrack(
                        AudioManager.STREAM_MUSIC, sr,
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        pcm.size * 2,
                        AudioTrack.MODE_STATIC
                    )
                }
                track.write(pcm, 0, pcm.size)
                track.play()
                Thread.sleep(450)
                track.release()
            } catch (_: Exception) {}
        }.start()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_FILE_REQ) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    contentResolver.openOutputStream(data.data!!)?.use { os ->
                        os.write(pendingSaveContent.toByteArray(Charsets.UTF_8))
                        os.flush()
                    }
                    pendingSaveResult?.success(true)
                    Toast.makeText(this, "تم حفظ الملف بنجاح", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    pendingSaveResult?.success(false)
                    Toast.makeText(this, "فشل حفظ الملف: ${e.message}", Toast.LENGTH_LONG).show()
                }
            } else {
                pendingSaveResult?.success(false)
            }
            pendingSaveContent = ""
            pendingSaveResult = null
        }
    }
}
