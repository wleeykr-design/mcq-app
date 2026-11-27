package com.medquiz.mcqstudio;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;

public class ReminderReceiver extends BroadcastReceiver {
    public static final String ACTION_REMINDER = "com.medquiz.mcqstudio.ACTION_FLASHCARD_REMINDER";
    public static final String CHANNEL_ID = "batch27_fc_heads_up_v2";
    private static final String PREFS_NAME = "batch27_reminder_prefs";
    private static final int ALARM_REQ_CODE = 2700;
    private static final int NOTIF_ID = 2701;

    @Override
    public void onReceive(Context context, Intent intent) {
        PowerManager.WakeLock wl = null;
        try {
            PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Batch27:ReminderWake");
                wl.acquire(4500L);
            }
        } catch (Exception ignored) {}

        try {
            String action = (intent != null) ? intent.getAction() : null;
            SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);

            if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
                if (!prefs.getBoolean("enabled", false)) return;
                long triggerAt = prefs.getLong("triggerAtMs", 0L);
                long intervalMs = prefs.getLong("intervalMs", 0L);
                String title = prefs.getString("title", "Batch 27 — تذكير مراجعة الفلاش كاردز");
                String body = prefs.getString("body", "حان وقت مراجعة بطاقاتك الطبية 🃏");
                long now = System.currentTimeMillis();
                if (triggerAt <= now) {
                    if (intervalMs > 0) {
                        long missed = ((now - triggerAt) / intervalMs) + 1;
                        triggerAt = triggerAt + missed * intervalMs;
                    } else {
                        triggerAt = now + 5000L;
                    }
                }
                scheduleAlarm(context, triggerAt, intervalMs, title, body);
                return;
            }

            String title = (intent != null && intent.getStringExtra("title") != null)
                    ? intent.getStringExtra("title")
                    : prefs.getString("title", "Batch 27 — تذكير مراجعة الفلاش كاردز");
            String body = (intent != null && intent.getStringExtra("body") != null)
                    ? intent.getStringExtra("body")
                    : prefs.getString("body", "حان وقت مراجعة بطاقاتك الطبية 🃏");

            showNotification(context, title, body);

            long intervalMs = prefs.getLong("intervalMs", 0L);
            if (intervalMs > 0 && prefs.getBoolean("enabled", false)) {
                scheduleAlarm(context, System.currentTimeMillis() + intervalMs, intervalMs, title, body);
            } else {
                prefs.edit().putBoolean("enabled", false).apply();
            }
        } finally {
            if (wl != null) {
                try {
                    if (wl.isHeld()) wl.release();
                } catch (Exception ignored) {}
            }
        }
    }

    public static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID,
                "تذكير مراجعة الفلاش كاردز (أعلى الشاشة)",
                NotificationManager.IMPORTANCE_HIGH
        );
        ch.setDescription("إشعارات التذكير المنبثقة لمراجعة الفلاش كاردز والأسئلة في Batch 27");
        ch.enableVibration(true);
        ch.setVibrationPattern(new long[] { 0L, 250L, 120L, 250L });
        ch.enableLights(true);
        ch.setShowBadge(true);
        ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);

        Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (soundUri != null) {
            AudioAttributes aa = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build();
            ch.setSound(soundUri, aa);
        }
        nm.createNotificationChannel(ch);
    }

    public static boolean showNotification(Context context, String title, String body) {
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return false;

        ensureChannel(context);

        if (Build.VERSION.SDK_INT >= 24 && !nm.areNotificationsEnabled()) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel existing = nm.getNotificationChannel(CHANNEL_ID);
            if (existing != null && existing.getImportance() == NotificationManager.IMPORTANCE_NONE) {
                return false;
            }
        }

        String safeTitle = (title != null && title.length() > 0) ? title : "Batch 27 — تذكير المراجعة";
        String safeBody = (body != null && body.length() > 0) ? body : "حان وقت مراجعة الفلاش كاردز 🃏";

        PendingIntent contentPi = buildOpenAppIntent(context);
        Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);

        Notification.Builder nb = (Build.VERSION.SDK_INT >= 26)
                ? new Notification.Builder(context, CHANNEL_ID)
                : new Notification.Builder(context);

        nb.setSmallIcon(R.drawable.ic_notif_bell);
        try {
            Bitmap large = BitmapFactory.decodeResource(context.getResources(), R.mipmap.ic_launcher);
            if (large != null) nb.setLargeIcon(large);
        } catch (Exception ignored) {}

        nb.setContentTitle(safeTitle);
        nb.setContentText(safeBody);
        nb.setTicker(safeTitle);
        nb.setStyle(new Notification.BigTextStyle().setBigContentTitle(safeTitle).bigText(safeBody));
        nb.setAutoCancel(true);
        nb.setOnlyAlertOnce(false);
        nb.setCategory(Notification.CATEGORY_REMINDER);
        nb.setVisibility(Notification.VISIBILITY_PUBLIC);
        nb.setPriority(Notification.PRIORITY_HIGH);
        nb.setVibrate(new long[] { 0L, 250L, 120L, 250L });
        if (soundUri != null) {
            nb.setSound(soundUri);
        } else {
            nb.setDefaults(Notification.DEFAULT_ALL);
        }
        nb.setContentIntent(contentPi);

        // Cancel any previous banner before notifying so Android / MIUI triggers a fresh heads-up banner
        nm.cancel(NOTIF_ID);
        nm.notify(NOTIF_ID, nb.build());
        return true;
    }

    public static void scheduleAlarm(Context context, long triggerAtMs, long intervalMs, String title, String body) {
        ensureChannel(context);
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putBoolean("enabled", true)
                .putLong("triggerAtMs", triggerAtMs)
                .putLong("intervalMs", intervalMs)
                .putString("title", title)
                .putString("body", body)
                .apply();

        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;

        PendingIntent pi = buildAlarmIntent(context, title, body);
        am.cancel(pi);

        // Prefer AlarmClockInfo on API 21+ so OEMs (e.g. Xiaomi MIUI/HyperOS) don't throttle background reminders
        if (Build.VERSION.SDK_INT >= 21) {
            try {
                PendingIntent showPi = buildOpenAppIntent(context);
                am.setAlarmClock(new AlarmManager.AlarmClockInfo(triggerAtMs, showPi), pi);
                return;
            } catch (SecurityException ignored) {
            } catch (Exception ignored) {}
        }

        if (Build.VERSION.SDK_INT >= 23) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
            } catch (SecurityException se) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
            }
        } else if (Build.VERSION.SDK_INT >= 19) {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
        } else {
            am.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
        }
    }

    public static void cancelAlarm(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putBoolean("enabled", false).apply();
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.cancel(buildAlarmIntent(context, "", ""));
    }

    private static PendingIntent buildOpenAppIntent(Context context) {
        Intent openIntent = new Intent(context, com.medquiz.mcqstudio.MainActivity.class);
        openIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        openIntent.putExtra("open_tab", "flashcards");
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getActivity(context, 2702, openIntent, flags);
    }

    private static PendingIntent buildAlarmIntent(Context context, String title, String body) {
        Intent i = new Intent(context, ReminderReceiver.class);
        i.setAction(ACTION_REMINDER);
        i.putExtra("title", title);
        i.putExtra("body", body);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getBroadcast(context, ALARM_REQ_CODE, i, flags);
    }
}
