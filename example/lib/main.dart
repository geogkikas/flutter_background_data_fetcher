import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_engine/flutter_background_engine.dart';
import 'package:device_context/device_context.dart';

// =================================================================
// TOP-LEVEL CALLBACK FOR BACKGROUND ENGINE
// =================================================================
@pragma('vm:entry-point')
Future<Map<String, dynamic>> fetchDeviceDataCallback() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final data = await DeviceContext.getSensorData(
      fetchDeviceInfo: true,
      fetchBasic: true,
      fetchThermal: true,
      fetchElectrical: true,
      fetchHealth: true,
      fetchEnvironment: true,
      fetchLocation: true,
      fetchMotion: true,
      fetchActivity: true,
    );

    return {
      // Device Info
      'manufacturer': data.deviceInfo?.manufacturer ?? 'N/A',
      'model': data.deviceInfo?.model ?? 'N/A',
      'brand': data.deviceInfo?.brand ?? 'N/A',
      'board': data.deviceInfo?.board ?? 'N/A',
      'hardware': data.deviceInfo?.hardware ?? 'N/A',
      'osName': data.deviceInfo?.osName ?? 'N/A',
      'osVersion': data.deviceInfo?.osVersion ?? 'N/A',
      'deviceId': data.deviceInfo?.deviceId ?? 'Unknown',

      // Basic Power
      'batteryLevel': data.basic?.batteryLevel ?? -1,
      'chargingStatus': data.basic?.status ?? -1,
      'pluggedStatus': data.basic?.pluggedStatus ?? -1,

      // Thermal
      'batteryTemp': data.thermal?.batteryTemp ?? 'N/A',
      'cpuTemp': data.thermal?.cpuTemp ?? 'N/A',
      'thermalStatus': data.thermal?.thermalStatus ?? -1,

      // Electrical
      'currentDraw_mA': data.electrical?.currentNowMA ?? 'N/A',
      'voltage_mV': data.electrical?.voltage ?? 'N/A',

      // Health
      'batteryHealth': data.health?.health ?? -1,
      'cycleCount': data.health?.cycleCount ?? 'N/A',
      'chargeCounter_mAh': data.health?.chargeCounterMAh ?? 'N/A',

      // Environment
      'lightLux': data.environment?.lightLux ?? 'N/A',

      // Location
      'latitude': data.location?.latitude ?? 'N/A',
      'longitude': data.location?.longitude ?? 'N/A',
      'altitude': data.location?.altitude ?? 'N/A',

      // Motion
      'posture': data.motion?.posture ?? 'N/A',
      'motionState': data.motion?.motionState ?? 'UNKNOWN',
      'proximity_cm': data.motion?.proximityCm ?? 'N/A',
      'isCovered': data.motion?.isCovered ?? false,
      'accelX': data.motion?.accelX ?? 'N/A',
      'accelY': data.motion?.accelY ?? 'N/A',
      'accelZ': data.motion?.accelZ ?? 'N/A',

      // Activity
      'activityType': data.activity?.activityType ?? 'UNKNOWN',
      'activityConfidence': data.activity?.activityConfidence ?? 'N/A',
    };
  } catch (e) {
    debugPrint("Background Fetch Error: $e");
    return {'error': e.toString()};
  }
}
// =================================================================

void main() async {
  // 1. Just ensure bindings are ready
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Run the app without starting the engine
  runApp(const SensorKitExampleApp());
}

class SensorKitExampleApp extends StatelessWidget {
  const SensorKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Kit Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<BackgroundLog> _logs = [];
  bool _isLoading = false;
  bool _isServiceRunning = false;
  int _currentInterval = 15;

  Timer? _uiHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _checkServiceStatus();
    _fetchData();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _uiHeartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkServiceStatus();
      _fetchData();
    }
  }

  void _startHeartbeat() {
    _uiHeartbeat = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isServiceRunning && mounted) {
        _fetchData(silent: true);
      }
    });
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await FlutterBackgroundEngine.isRunning();
    final interval = await FlutterBackgroundEngine.getSavedInterval();

    if (mounted) {
      setState(() {
        _isServiceRunning = isRunning;
        _currentInterval = interval;
      });
    }
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isLoading = true);

    await _checkServiceStatus();
    final logs = await FlutterBackgroundEngine.getUnsyncedLogs();

    if (mounted) {
      if (_logs.length != logs.length || !silent) {
        setState(() {
          _logs = logs.reversed.toList();
          _isLoading = false;
        });
      } else {
        if (!silent) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncDataToServer() async {
    if (_logs.isEmpty) return;
    setState(() => _isLoading = true);

    List<int> idsToSync = _logs.map((log) => log.sqliteId!).toList();
    await FlutterBackgroundEngine.markAsSynced(idsToSync);
    await _fetchData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Data successfully synced!')),
      );
    }
  }

  Future<void> _revertSync() async {
    setState(() => _isLoading = true);
    await FlutterBackgroundEngine.revertAllSynced();
    await _fetchData();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('⏪ Synced logs reverted!')));
    }
  }

  Future<void> _deleteHistory() async {
    setState(() => _isLoading = true);
    await FlutterBackgroundEngine.clearHistory();
    await _fetchData();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🗑️ All history deleted!')));
    }
  }

  Future<void> _showIntervalDialog() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Logging Interval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [1, 5, 15, 30, 60].map((min) {
              return ListTile(
                title: Text('$min Minute${min > 1 ? 's' : ''}'),
                trailing: _currentInterval == min
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, min),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selected != null && selected != _currentInterval) {
      setState(() => _isLoading = true);
      await FlutterBackgroundEngine.updateInterval(selected);
      await _checkServiceStatus();
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⏱️ Interval updated to $selected minutes.')),
        );
      }
    }
  }

  // =================================================================
  // START SERVICE & HANDLE PERMISSIONS MANUALLY
  // =================================================================
  Future<void> _startService() async {
    setState(() => _isLoading = true);

    // --- 1. Request Engine Permissions ---
    var notifStatus = await Permission.notification.request();
    bool exactAlarmGranted = true;

    if (Platform.isAndroid) {
      var alarmStatus = await Permission.scheduleExactAlarm.request();
      exactAlarmGranted = alarmStatus.isGranted;
    }

    if (!notifStatus.isGranted || !exactAlarmGranted) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Cannot start: Core engine permissions denied!'),
          ),
        );
      }
      return;
    }

    // --- 2. Request Hardware Permissions (for device_context) ---
    var locStatus = await Permission.locationWhenInUse.request();
    if (locStatus.isGranted) {
      await Permission.locationAlways.request(); // Try to upgrade
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Cannot start: Location permission required!'),
          ),
        );
      }
      return;
    }

    await Permission.activityRecognition.request();
    if (Platform.isIOS) {
      await Permission.sensors.request();
    }

    // --- 3. Start the Engine ---
    bool started = await FlutterBackgroundEngine.initAndStart(
      fetchCallback: fetchDeviceDataCallback,
      config: BackgroundConfig(intervalMinutes: _currentInterval),
    );

    setState(() {
      _isServiceRunning = started;
      _isLoading = false;
    });

    if (mounted && started) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🚀 Engine Started.')));
    }
  }

  Future<void> _stopService() async {
    setState(() => _isLoading = true);
    FlutterBackgroundEngine.stop();

    setState(() {
      _isServiceRunning = false;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🛑 Engine Stopped.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Engine'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Local Logs",
            onPressed: () => _fetchData(silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: "Simulate Server Sync",
            onPressed: _syncDataToServer,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'interval') _showIntervalDialog();
              if (value == 'revert') _revertSync();
              if (value == 'delete') _deleteHistory();
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'interval',
                child: Row(
                  children: [
                    Icon(Icons.timer, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Change Interval'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'revert',
                child: Row(
                  children: [
                    Icon(Icons.undo, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Revert Synced Logs'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete All History'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isServiceRunning
                ? Colors.green.shade100
                : Colors.red.shade100,
            child: Text(
              _isServiceRunning
                  ? "🟢 Engine Active ($_currentInterval min interval)."
                  : "🔴 Engine is currently Stopped.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // Log List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                ? const Center(
                    child: Text(
                      "No unsynced logs.\nMinimize the app and wait for an interval.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 80,
                    ), // Padding for FAB
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final payload = log.payload;

                      final time = DateTime.parse(log.timestamp).toLocal();
                      final formattedTime =
                          "${time.hour}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";

                      // Safely format raw accelerometer doubles
                      final ax = payload['accelX'] is num
                          ? (payload['accelX'] as num).toStringAsFixed(2)
                          : payload['accelX'];
                      final ay = payload['accelY'] is num
                          ? (payload['accelY'] as num).toStringAsFixed(2)
                          : payload['accelY'];
                      final az = payload['accelZ'] is num
                          ? (payload['accelZ'] as num).toStringAsFixed(2)
                          : payload['accelZ'];

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- HEADER ---
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Log at $formattedTime",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    child: Text(
                                      "${payload['batteryLevel'] ?? '?'}%",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "📱 ${payload['manufacturer']} ${payload['model']}  •  🔑 ${payload['deviceId']}",
                                style: const TextStyle(fontSize: 12),
                              ),
                              const Divider(height: 24),

                              // --- POWER & HEALTH ---
                              _buildSectionHeader("Power & Health"),
                              _buildInfoRow(
                                "🔋 Status",
                                "State: ${payload['chargingStatus']} • Plug: ${payload['pluggedStatus']}",
                              ),
                              _buildInfoRow(
                                "⚡ Draw",
                                "${payload['currentDraw_mA']} mA • ${payload['voltage_mV']} mV",
                              ),
                              _buildInfoRow(
                                "❤️ Health",
                                "Health: ${payload['batteryHealth']} • Cyc: ${payload['cycleCount']} • Cap: ${payload['chargeCounter_mAh']} mAh",
                              ),

                              // --- ENVIRONMENT & LOCATION ---
                              _buildSectionHeader("Environment & Location"),
                              _buildInfoRow(
                                "🌡️ Temp",
                                "Bat: ${payload['batteryTemp']}°C • CPU: ${payload['cpuTemp']}°C (Thrml: ${payload['thermalStatus']})",
                              ),
                              _buildInfoRow(
                                "☀️ Light",
                                "${payload['lightLux']} lux",
                              ),
                              _buildInfoRow(
                                "📍 GPS",
                                "${payload['latitude']}, ${payload['longitude']} (Alt: ${payload['altitude']}m)",
                              ),

                              // --- MOTION & AI ---
                              _buildSectionHeader("Motion & AI"),
                              _buildInfoRow(
                                "🧠 AI",
                                "${payload['activityType']} (${payload['activityConfidence']})",
                              ),
                              _buildInfoRow(
                                "🏃 Motion",
                                "${payload['motionState']} • ${payload['posture']}",
                              ),
                              _buildInfoRow(
                                "🙈 Proximity",
                                "${payload['proximity_cm']} cm (Covered: ${payload['isCovered']})",
                              ),
                              _buildInfoRow(
                                "📐 Accel",
                                "X: $ax • Y: $ay • Z: $az",
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _isServiceRunning
          ? FloatingActionButton.extended(
              onPressed: _stopService,
              backgroundColor: Colors.red.shade300,
              icon: const Icon(Icons.stop),
              label: const Text("Stop Engine"),
            )
          : FloatingActionButton.extended(
              onPressed: _startService,
              backgroundColor: Colors.green.shade400,
              icon: const Icon(Icons.play_arrow),
              label: const Text("Start Engine"),
            ),
    );
  }

  // --- UI Helpers for the Log Cards ---
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, top: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
