import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../models/background_config.dart';
import '../models/background_log.dart';
import 'storage_service.dart';
import 'internal_task.dart';

class FlutterBackgroundEngine {
  static const int alarmId = 42;
  FlutterBackgroundEngine._();

  /// Pass a top-level function that returns a Map<String, dynamic>.
  /// NOTE: Ensure your host app has requested Notification and Exact Alarm permissions
  /// before calling this, otherwise the background service may fail to start.
  static Future<bool> initAndStart({
    required Future<Map<String, dynamic>> Function() fetchCallback,
    BackgroundConfig config = const BackgroundConfig(),
  }) async {
    // Get a raw integer handle to pass the function across Isolate boundaries
    final callbackHandle = PluginUtilities.getCallbackHandle(fetchCallback);
    if (callbackHandle == null) {
      throw Exception(
        "The fetchCallback MUST be a top-level or static function.",
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fbe_callback_handle', callbackHandle.toRawHandle());

    // We just initialize and start.
    await initialize(config: config);
    await start();
    return true;
  }

  static Future<void> initialize({required BackgroundConfig config}) async {
    final prefs = await SharedPreferences.getInstance();
    final existingInterval = prefs.getInt('sampling_interval');
    final intervalToUse = existingInterval ?? config.intervalMinutes;

    await prefs.setString('fbe_config', jsonEncode(config.toJson()));
    await LibraryStorage.setInterval(intervalToUse);

    if (Platform.isAndroid) await AndroidAlarmManager.initialize();

    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      await _scheduleNextExactAlarm(intervalToUse);
      return;
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    if (!(await FlutterBackgroundService().isRunning())) {
      await FlutterBackgroundService().startService();
      final interval = await LibraryStorage.getInterval();
      await _scheduleNextExactAlarm(interval);
    }
  }

  static void stop() {
    if (Platform.isAndroid) AndroidAlarmManager.cancel(alarmId);
    FlutterBackgroundService().invoke('stopService');
  }

  static Future<void> updateInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final configRaw = prefs.getString('fbe_config');

    if (configRaw != null) {
      final updatedConfig = BackgroundConfig(intervalMinutes: minutes);
      await prefs.setString('fbe_config', jsonEncode(updatedConfig.toJson()));
    }

    await LibraryStorage.setInterval(minutes);
    await _scheduleNextExactAlarm(minutes);
  }

  static Future<List<BackgroundLog>> getHistory() async {
    final rawLogs = await LibraryStorage.getLogs();
    return rawLogs.map((log) => BackgroundLog.fromJson(log)).toList();
  }

  static Future<List<BackgroundLog>> getUnsyncedLogs() async {
    final rawLogs = await LibraryStorage.getUnsyncedLogs();
    return rawLogs.map((log) => BackgroundLog.fromJson(log)).toList();
  }

  static Future<void> markAsSynced(List<int> ids) {
    return LibraryStorage.markAsSynced(ids);
  }

  static Future<void> clearHistory() {
    return LibraryStorage.clearLogs();
  }

  static Future<void> revertAllSynced() {
    return LibraryStorage.revertAllSynced();
  }

  static Future<bool> isRunning() async {
    return await FlutterBackgroundService().isRunning();
  }

  static Future<int> getSavedInterval() {
    return LibraryStorage.getInterval();
  }

  static Future<void> _scheduleNextExactAlarm(int minutes) async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(alarmId);
      final now = DateTime.now();
      final int minutesToNext = minutes - (now.minute % minutes);
      DateTime targetTime = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + minutesToNext,
      );

      // If the math pushes it to exactly right now (or slightly past), add the interval
      if (targetTime.isBefore(now) || targetTime.isAtSameMomentAs(now)) {
        targetTime = targetTime.add(Duration(minutes: minutes));
      }

      debugPrint("\n=================================================");
      debugPrint("📅 [FlutterBackgroundEngine] OS ALARM SCHEDULED");
      debugPrint("🎯 Target Execution Time: $targetTime");
      debugPrint("=================================================\n");

      await AndroidAlarmManager.oneShotAt(
        targetTime,
        alarmId,
        performAlarmDataCollection,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }
  }
}
