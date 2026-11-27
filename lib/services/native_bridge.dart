import 'package:flutter/services.dart';

class PickedNativeFile {
  final String name;
  final Uint8List bytes;
  PickedNativeFile(this.name, this.bytes);
}

class NativeBridge {
  static const MethodChannel _ch = MethodChannel('com.medquiz.mcqstudio/native');

  static void listenOpenTab(void Function(String tab) onOpenTab) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openTab' && call.arguments is String) {
        onOpenTab(call.arguments as String);
      }
    });
  }

  static Future<String?> consumePendingTab() async {
    try {
      return await _ch.invokeMethod<String>('consumePendingTab');
    } catch (_) {
      return null;
    }
  }

  static Future<void> playSound(String kind) async {
    try {
      await _ch.invokeMethod('playSound', {'kind': kind});
    } catch (_) {}
  }

  static Future<String> getNotifStatus() async {
    try {
      return await _ch.invokeMethod<String>('getNotifStatus') ?? 'ok';
    } catch (_) {
      return 'web';
    }
  }

  static Future<void> openNotifSettings() async {
    try {
      await _ch.invokeMethod('openNotifSettings');
    } catch (_) {}
  }

  static Future<String> scheduleReminder({
    required int triggerAtMs,
    required int intervalMs,
    required String title,
    required String body,
  }) async {
    try {
      return await _ch.invokeMethod<String>('scheduleReminder', {
            'triggerAtMs': triggerAtMs,
            'intervalMs': intervalMs,
            'title': title,
            'body': body,
          }) ??
          'ok';
    } catch (_) {
      return 'error';
    }
  }

  static Future<void> cancelReminder() async {
    try {
      await _ch.invokeMethod('cancelReminder');
    } catch (_) {}
  }

  static Future<String> testNotification(String title, String body) async {
    try {
      return await _ch.invokeMethod<String>('testNotification', {
            'title': title,
            'body': body,
          }) ??
          'ok';
    } catch (_) {
      return 'error';
    }
  }

  static Future<bool> saveFile(String filename, String content) async {
    try {
      return await _ch.invokeMethod<bool>('saveFile', {
            'filename': filename,
            'content': content,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<PickedNativeFile>> pickFiles({bool allowMultiple = true}) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('pickFiles', {
        'allowMultiple': allowMultiple,
      });
      if (raw == null) return [];
      final out = <PickedNativeFile>[];
      for (final item in raw) {
        if (item is Map) {
          final name = item['name']?.toString() ?? 'file.bin';
          final bytes = item['bytes'];
          if (bytes is Uint8List) {
            out.add(PickedNativeFile(name, bytes));
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> printHtml(String html, String jobName) async {
    try {
      await _ch.invokeMethod('printHtml', {'html': html, 'jobName': jobName});
    } catch (_) {}
  }
}
