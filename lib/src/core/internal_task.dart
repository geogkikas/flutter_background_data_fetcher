import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'flutter_background_engine_impl.dart';

@pragma('vm:entry-point')
Future<void> performAlarmDataCollection() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  DateTime exactActualTime = DateTime.now();

  debugPrint("\n=================================================");
  debugPrint("⚡ [Background Isolate] AWAKE AND RUNNING!");
  debugPrint("⏰ Actual Wake-Up Time: $exactActualTime");
  debugPrint("=================================================");

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // 1. Retrieve the Function Handle saved by the user
    final handleRaw = prefs.getInt('fbe_callback_handle');
    if (handleRaw == null) {
      debugPrint(
        "❌ [Background Isolate] No callback function registered! Aborting.",
      );
      return;
    }

    // 2. Reconstruct and execute the user's function
    final callbackHandle = CallbackHandle.fromRawHandle(handleRaw);
    final fetchFunction =
        PluginUtilities.getCallbackFromHandle(callbackHandle)
            as Future<Map<String, dynamic>> Function()?;

    if (fetchFunction != null) {
      debugPrint("⚙️ [Background Isolate] Executing developer callback...");
      final Map<String, dynamic> payload = await fetchFunction();

      debugPrint("📦 [Background Isolate] Payload Fetched:");
      debugPrint(jsonEncode(payload)); // Prints the actual JSON fetched!

      // 3. Save the result
      await LibraryStorage.saveLog(payload);
      FlutterBackgroundService().invoke('logUpdated');
    }

    // 4. Reschedule for Android
    if (Platform.isAndroid) {
      int interval = await LibraryStorage.getInterval();
      DateTime nextTrigger = exactActualTime.add(Duration(minutes: interval));

      await AndroidAlarmManager.oneShotAt(
        nextTrigger,
        FlutterBackgroundEngine.alarmId,
        performAlarmDataCollection,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }
  } catch (err) {
    debugPrint("❌ [Background Isolate] Fatal task error: $err");
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  debugPrint("🍏 [iOS Background] Triggered by BGTaskScheduler.");
  await performAlarmDataCollection();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  debugPrint("🛡️ [Foreground Service] Started successfully.");
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Background Engine Active",
      content: "Running scheduled background tasks...",
    );
  }
  service.on('stopService').listen((event) {
    debugPrint("🛑 [Foreground Service] Stop command received.");
    service.stopSelf();
  });
}
