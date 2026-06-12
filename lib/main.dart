import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';


const String activeTripKey = 'active_trip_v2';
const String nativeChannelName = 'gps_trip_meter/native';

Map<String, dynamic> positionToMap(Position? p) {
  if (p == null) return {};
  return {
    'latitude': p.latitude,
    'longitude': p.longitude,
    'timestamp': p.timestamp.millisecondsSinceEpoch,
    'accuracy': p.accuracy,
    'altitude': p.altitude,
    'altitudeAccuracy': p.altitudeAccuracy,
    'heading': p.heading,
    'headingAccuracy': p.headingAccuracy,
    'speed': p.speed,
    'speedAccuracy': p.speedAccuracy,
  };
}

Position? positionFromMap(dynamic raw) {
  if (raw is! Map) return null;
  try {
    final m = Map<String, dynamic>.from(raw);
    return Position(
      latitude: (m['latitude'] ?? 0).toDouble(),
      longitude: (m['longitude'] ?? 0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      accuracy: (m['accuracy'] ?? 999).toDouble(),
      altitude: (m['altitude'] ?? 0).toDouble(),
      altitudeAccuracy: (m['altitudeAccuracy'] ?? 0).toDouble(),
      heading: (m['heading'] ?? 0).toDouble(),
      headingAccuracy: (m['headingAccuracy'] ?? 0).toDouble(),
      speed: (m['speed'] ?? 0).toDouble(),
      speedAccuracy: (m['speedAccuracy'] ?? 0).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

ModeInfo infoFromName(String name) {
  final mode = TripMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => TripMode.walk,
  );
  return modeInfo[mode]!;
}

double bgDistanceKm(Position a, Position b) {
  return Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) / 1000.0;
}

double bgSpeedFromPositions(Position oldPos, Position newPos) {
  final d = bgDistanceKm(oldPos, newPos);
  final hours = newPos.timestamp.difference(oldPos.timestamp).inMilliseconds / 3600000.0;
  return hours > 0 ? d / hours : 0;
}

Future<void> updateActiveTripFromBackground() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(activeTripKey);
  if (raw == null) return;

  Map<String, dynamic> state;
  try {
    state = Map<String, dynamic>.from(jsonDecode(raw));
  } catch (_) {
    return;
  }

  if (state['running'] != true) return;

  Position pos;
  try {
    pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 8),
      ),
    );
  } catch (_) {
    return;
  }

  final startMs = state['startTime'] ?? DateTime.now().millisecondsSinceEpoch;
  final elapsedMs = DateTime.now().millisecondsSinceEpoch - startMs;
  final modeName = state['mode'] ?? TripMode.walk.name;
  final info = infoFromName(modeName);
  final oldPos = positionFromMap(state['lastPos']);
  int points = (state['pointsCount'] ?? 0) + 1;
  double bestAccuracy = (state['bestAccuracy'] ?? 999999).toDouble();
  double totalDistanceKm = (state['totalDistanceKm'] ?? 0).toDouble();
  double maxSpeed = (state['maxSpeed'] ?? 0).toDouble();

  if (pos.accuracy > 0 && pos.accuracy < bestAccuracy) {
    bestAccuracy = pos.accuracy;
  }

  double kmh = 0;
  if (pos.speed >= 0) {
    kmh = pos.speed * 3.6;
  } else if (oldPos != null) {
    kmh = bgSpeedFromPositions(oldPos, pos);
  }
  kmh = max(0, kmh);

  final warmingUp = elapsedMs < 8000 || points < 4;
  final badAccuracy = pos.accuracy > 40;
  final impossibleSpeed = kmh > info.maxValidSpeed;

  final valid = !warmingUp && !badAccuracy && !impossibleSpeed && oldPos != null;

  if (valid && oldPos != null) {
    if (kmh > maxSpeed) maxSpeed = kmh;
    final d = bgDistanceKm(oldPos, pos);
    final dtSeconds = pos.timestamp.difference(oldPos.timestamp).inMilliseconds / 1000.0;
    if (dtSeconds >= 1) {
      final jumpSpeed = d / (dtSeconds / 3600.0);
      if (d < 0.30 && jumpSpeed <= info.maxValidSpeed) {
        totalDistanceKm += d;
      }
    }
  } else {
    kmh = 0;
  }

  state['lastPos'] = positionToMap(pos);
  state['pointsCount'] = points;
  state['bestAccuracy'] = bestAccuracy;
  state['totalDistanceKm'] = totalDistanceKm;
  state['maxSpeed'] = maxSpeed;
  state['currentSpeed'] = kmh;
  state['lastBackgroundUpdate'] = DateTime.now().millisecondsSinceEpoch;

  await prefs.setString(activeTripKey, jsonEncode(state));
}


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const GpsTripApp());
}

@pragma('vm:entry-point')
void startCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}

class GpsTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await updateActiveTripFromBackground();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    updateActiveTripFromBackground();
    FlutterForegroundTask.updateService(
      notificationTitle: 'عداد رحلات GPS يعمل في الخلفية',
      notificationText: 'لا تغلق التطبيق من التطبيقات الأخيرة',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}

class GpsTripApp extends StatelessWidget {
  const GpsTripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'عداد رحلات GPS',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0077FF)),
          fontFamily: 'Roboto',
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

enum TripMode { walk, bike, car }

class ModeInfo {
  final String name;
  final String icon;
  final double maxValidSpeed;
  final double slow;
  final double mid;
  final String slowText;
  final String midText;
  final String fastText;

  const ModeInfo({
    required this.name,
    required this.icon,
    required this.maxValidSpeed,
    required this.slow,
    required this.mid,
    required this.slowText,
    required this.midText,
    required this.fastText,
  });
}

const Map<TripMode, ModeInfo> modeInfo = {
  TripMode.walk: ModeInfo(
    name: 'مشي',
    icon: '🚶',
    maxValidSpeed: 25,
    slow: 7,
    mid: 12,
    slowText: 'مشي طبيعي',
    midText: 'مشي سريع',
    fastText: 'سرعة غير معتادة للمشي',
  ),
  TripMode.bike: ModeInfo(
    name: 'دراجة',
    icon: '🚴',
    maxValidSpeed: 80,
    slow: 15,
    mid: 30,
    slowText: 'دراجة هادئة',
    midText: 'دراجة متوسطة',
    fastText: 'دراجة سريعة',
  ),
  TripMode.car: ModeInfo(
    name: 'سيارة',
    icon: '🚗',
    maxValidSpeed: 180,
    slow: 60,
    mid: 100,
    slowText: 'سرعة منخفضة',
    midText: 'سرعة متوسطة',
    fastText: 'سرعة عالية',
  ),
};

class TripRecord {
  final String mode;
  final String modeName;
  final String modeIcon;
  final int timestamp;
  final int durationMs;
  final double distanceKm;
  final double maxSpeed;
  final double avgSpeed;

  TripRecord({
    required this.mode,
    required this.modeName,
    required this.modeIcon,
    required this.timestamp,
    required this.durationMs,
    required this.distanceKm,
    required this.maxSpeed,
    required this.avgSpeed,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'modeName': modeName,
        'modeIcon': modeIcon,
        'timestamp': timestamp,
        'durationMs': durationMs,
        'distanceKm': distanceKm,
        'maxSpeed': maxSpeed,
        'avgSpeed': avgSpeed,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) => TripRecord(
        mode: json['mode'] ?? 'walk',
        modeName: json['modeName'] ?? 'مشي',
        modeIcon: json['modeIcon'] ?? '🚶',
        timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        durationMs: json['durationMs'] ?? 0,
        distanceKm: (json['distanceKm'] ?? 0).toDouble(),
        maxSpeed: (json['maxSpeed'] ?? 0).toDouble(),
        avgSpeed: (json['avgSpeed'] ?? 0).toDouble(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const MethodChannel native = MethodChannel(nativeChannelName);
  static const int maxTrips = 20;
  static const int warmupMs = 8000;
  static const int warmupPoints = 4;

  TripMode selectedMode = TripMode.walk;
  StreamSubscription<Position>? positionSub;
  Timer? timer;
  Timer? activeSaveTimer;

  bool running = false;
  bool restoredUnclosedTrip = false;
  String status = 'اضغط تشغيل للبدء';

  DateTime? startTime;
  Position? lastPos;
  int pointsCount = 0;

  double currentSpeed = 0;
  double totalDistanceKm = 0;
  double maxSpeed = 0;
  double bestAccuracy = 999999;

  List<TripRecord> trips = [];

  @override
  void initState() {
    super.initState();
    initForegroundTask();
    loadTrips();
    loadActiveTrip();
  }

  @override
  void dispose() {
    positionSub?.cancel();
    timer?.cancel();
    activeSaveTimer?.cancel();
    super.dispose();
  }

  void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gps_trip_meter_channel',
        channelName: 'عداد رحلات GPS',
        channelDescription: 'إشعار تتبع الرحلات بالخلفية',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(7000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> startForeground() async {
    await FlutterForegroundTask.requestNotificationPermission();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'عداد رحلات GPS يعمل الآن',
        notificationText: 'يتم حساب السرعة والمسافة في الخلفية',
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'عداد رحلات GPS يعمل الآن',
        notificationText: 'يتم حساب السرعة والمسافة في الخلفية',
        callback: startCallback,
      );
    }
  }

  Future<void> stopForeground() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }


  Future<void> openBatterySettings() async {
    try {
      await native.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      try {
        await native.invokeMethod('openBatterySettings');
      } catch (_) {
        showSnack('افتح إعدادات البطارية واجعل التطبيق غير مقيّد');
      }
    }
  }

  Future<void> openAppSettings() async {
    try {
      await native.invokeMethod('openAppSettings');
    } catch (_) {
      showSnack('افتح إعدادات التطبيق يدويًا');
    }
  }

  Future<void> saveActiveTrip() async {
    if (!running || startTime == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeTripKey, jsonEncode({
      'running': true,
      'mode': selectedMode.name,
      'startTime': startTime!.millisecondsSinceEpoch,
      'lastPos': positionToMap(lastPos),
      'pointsCount': pointsCount,
      'currentSpeed': currentSpeed,
      'totalDistanceKm': totalDistanceKm,
      'maxSpeed': maxSpeed,
      'bestAccuracy': bestAccuracy,
      'lastSavedAt': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  Future<void> clearActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(activeTripKey);
  }

  Future<void> loadActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(activeTripKey);
    if (raw == null) return;

    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      if (m['running'] != true) return;

      final modeName = m['mode'] ?? TripMode.walk.name;
      selectedMode = TripMode.values.firstWhere(
        (x) => x.name == modeName,
        orElse: () => TripMode.walk,
      );
      startTime = DateTime.fromMillisecondsSinceEpoch(m['startTime'] ?? DateTime.now().millisecondsSinceEpoch);
      lastPos = positionFromMap(m['lastPos']);
      pointsCount = m['pointsCount'] ?? 0;
      currentSpeed = (m['currentSpeed'] ?? 0).toDouble();
      totalDistanceKm = (m['totalDistanceKm'] ?? 0).toDouble();
      maxSpeed = (m['maxSpeed'] ?? 0).toDouble();
      bestAccuracy = (m['bestAccuracy'] ?? 999999).toDouble();
      restoredUnclosedTrip = true;

      if (mounted) {
        setState(() {
          running = false;
          status = 'تم العثور على رحلة غير مغلقة';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => showRestoreDialog());
      }
    } catch (_) {}
  }

  Future<void> showRestoreDialog() async {
    if (!mounted || !restoredUnclosedTrip) return;
    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة رحلة سابقة'),
          content: const Text(
            'يبدو أن التطبيق توقف أو أُغلق أثناء رحلة. هل تريد استكمال الرحلة من آخر بيانات محفوظة؟',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await clearActiveTrip();
                if (!mounted) return;
                Navigator.pop(context);
                await resetCurrent();
              },
              child: const Text('تصفير'),
            ),
            TextButton(
              onPressed: () async {
                if (!mounted) return;
                Navigator.pop(context);
                await saveRestoredAsTrip();
              },
              child: const Text('حفظها الآن'),
            ),
            FilledButton(
              onPressed: () async {
                if (!mounted) return;
                Navigator.pop(context);
                await resumeGps();
              },
              child: const Text('استكمال'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> resumeGps() async {
    if (!await ensureLocationPermission()) return;
    await startForeground();

    setState(() {
      running = true;
      status = 'تم استكمال الرحلة';
    });

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await refreshFromActiveTrip();
      if (mounted && running) setState(() {});
    });

    activeSaveTimer?.cancel();
    activeSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => saveActiveTrip());

    positionSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      onPosition,
      onError: (_) {
        setState(() {
          running = false;
          status = 'خطأ في GPS';
        });
      },
    );

    await saveActiveTrip();
    showSnack('تم استكمال GPS...');
  }

  Future<void> refreshFromActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(activeTripKey);
    if (raw == null || !running) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      final bgUpdate = m['lastBackgroundUpdate'];
      if (bgUpdate == null) return;

      lastPos = positionFromMap(m['lastPos']) ?? lastPos;
      pointsCount = m['pointsCount'] ?? pointsCount;
      currentSpeed = (m['currentSpeed'] ?? currentSpeed).toDouble();
      totalDistanceKm = (m['totalDistanceKm'] ?? totalDistanceKm).toDouble();
      maxSpeed = (m['maxSpeed'] ?? maxSpeed).toDouble();
      bestAccuracy = (m['bestAccuracy'] ?? bestAccuracy).toDouble();
    } catch (_) {}
  }

  Future<void> saveRestoredAsTrip() async {
    if (startTime == null) return;
    final durationMs = DateTime.now().difference(startTime!).inMilliseconds;
    final hours = durationMs / 3600000.0;
    final avg = hours > 0 ? totalDistanceKm / hours : 0.0;
    final info = modeInfo[selectedMode]!;

    trips.add(
      TripRecord(
        mode: selectedMode.name,
        modeName: info.name,
        modeIcon: info.icon,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        durationMs: durationMs,
        distanceKm: round2(totalDistanceKm),
        maxSpeed: round1(maxSpeed),
        avgSpeed: round1(avg),
      ),
    );
    await saveTrips();
    await clearActiveTrip();

    setState(() {
      running = false;
      status = 'تم حفظ الرحلة المستعادة';
      currentSpeed = 0;
      startTime = null;
      lastPos = null;
      pointsCount = 0;
    });

    showSnack('تم حفظ الرحلة');
  }


  Future<void> loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('trips_v1');
    if (raw == null) return;

    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => TripRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.maxSpeed <= 180 && t.distanceKm >= 0)
          .toList();

      setState(() => trips = list);
    } catch (_) {}
  }

  Future<void> saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        trips.length > maxTrips ? trips.sublist(trips.length - maxTrips) : trips;
    await prefs.setString(
      'trips_v1',
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
    setState(() => trips = trimmed);
  }

  Future<bool> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showSnack('فعّل GPS من إعدادات الهاتف');
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      showSnack('اسمح للتطبيق باستخدام الموقع');
      return false;
    }

    return true;
  }

  Future<void> startGps() async {
    if (!await ensureLocationPermission()) return;

    await startForeground();

    setState(() {
      running = true;
      status = 'تثبيت إشارة GPS...';
      startTime = DateTime.now();
      lastPos = null;
      pointsCount = 0;
      currentSpeed = 0;
      totalDistanceKm = 0;
      maxSpeed = 0;
      bestAccuracy = 999999;
    });

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await refreshFromActiveTrip();
      if (mounted && running) setState(() {});
    });

    activeSaveTimer?.cancel();
    activeSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => saveActiveTrip());
    await saveActiveTrip();

    positionSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      onPosition,
      onError: (_) {
        setState(() {
          running = false;
          status = 'خطأ في GPS';
        });
      },
    );

    showSnack('جاري تشغيل GPS...');
  }

  Future<void> stopGps() async {
    if (!running) return;

    await positionSub?.cancel();
    positionSub = null;
    timer?.cancel();
    activeSaveTimer?.cancel();
    await stopForeground();

    final durationMs =
        DateTime.now().difference(startTime ?? DateTime.now()).inMilliseconds;
    final hours = durationMs / 3600000.0;
    final avg = hours > 0 ? totalDistanceKm / hours : 0.0;
    final info = modeInfo[selectedMode]!;

    if (totalDistanceKm > 0 || durationMs >= 10000) {
      trips.add(
        TripRecord(
          mode: selectedMode.name,
          modeName: info.name,
          modeIcon: info.icon,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          durationMs: durationMs,
          distanceKm: round2(totalDistanceKm),
          maxSpeed: round1(maxSpeed),
          avgSpeed: round1(avg),
        ),
      );
      await saveTrips();
    }

    await clearActiveTrip();

    setState(() {
      running = false;
      status = 'تم حفظ الرحلة ✓';
      currentSpeed = 0;
    });

    showSnack('تم إيقاف GPS وحفظ الرحلة');
  }

  Future<void> resetCurrent() async {
    await positionSub?.cancel();
    positionSub = null;
    timer?.cancel();
    activeSaveTimer?.cancel();
    await stopForeground();

    setState(() {
      running = false;
      status = 'اضغط تشغيل للبدء';
      startTime = null;
      lastPos = null;
      pointsCount = 0;
      currentSpeed = 0;
      totalDistanceKm = 0;
      maxSpeed = 0;
      bestAccuracy = 999999;
    });

    showSnack('تم التصفير بدون حفظ');
  }

  void onPosition(Position pos) {
    final info = modeInfo[selectedMode]!;
    pointsCount++;

    if (pos.accuracy > 0 && pos.accuracy < bestAccuracy) {
      bestAccuracy = pos.accuracy;
    }

    double kmh = 0;
    if (pos.speed >= 0) {
      kmh = pos.speed * 3.6;
    } else if (lastPos != null) {
      kmh = calcSpeedFromPositions(lastPos!, pos);
    }

    kmh = max(0, kmh);

    final elapsedMs =
        DateTime.now().difference(startTime ?? DateTime.now()).inMilliseconds;

    final warmingUp = elapsedMs < warmupMs || pointsCount < warmupPoints;
    final badAccuracy = pos.accuracy > 40;
    final impossibleSpeed = kmh > info.maxValidSpeed;

    bool valid = true;

    if (warmingUp || badAccuracy || impossibleSpeed || lastPos == null) {
      valid = false;
      kmh = 0;
    }

    if (valid && lastPos != null) {
      if (kmh > maxSpeed) maxSpeed = kmh;

      final d = distanceKm(lastPos!, pos);
      final dtSeconds =
          pos.timestamp.difference(lastPos!.timestamp).inMilliseconds / 1000.0;

      if (dtSeconds >= 1) {
        final jumpSpeed = d / (dtSeconds / 3600.0);
        if (d < 0.30 && jumpSpeed <= info.maxValidSpeed) {
          totalDistanceKm += d;
        }
      }
    }

    lastPos = pos;

    setState(() {
      currentSpeed = kmh;
      status = buildStatusText(warmingUp, badAccuracy, pos.accuracy);
    });
    saveActiveTrip();
  }

  String buildStatusText(bool warmingUp, bool badAccuracy, double accuracy) {
    if (warmingUp) return 'تثبيت إشارة GPS...';
    if (badAccuracy) return 'دقة ضعيفة • ${accuracy.round()}م';
    if (accuracy <= 10) return 'دقة ممتازة • ${accuracy.round()}م';
    if (accuracy <= 40) return 'دقة جيدة • ${accuracy.round()}م';
    return 'GPS يعمل الآن';
  }

  double calcSpeedFromPositions(Position oldPos, Position newPos) {
    final d = distanceKm(oldPos, newPos);
    final hours =
        newPos.timestamp.difference(oldPos.timestamp).inMilliseconds / 3600000.0;
    return hours > 0 ? d / hours : 0;
  }

  double distanceKm(Position a, Position b) {
    return Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) /
        1000.0;
  }

  String durationText() {
    if (startTime == null) return '00:00';
    final ms = DateTime.now().difference(startTime!).inMilliseconds;
    return formatMs(ms);
  }

  double avgSpeed() {
    if (startTime == null) return 0;
    final hours = DateTime.now().difference(startTime!).inMilliseconds / 3600000.0;
    return hours > 0 ? totalDistanceKm / hours : 0;
  }

  void changeMode(TripMode mode) {
    if (running) {
      showSnack('لا يمكن تغيير النوع أثناء تشغيل GPS');
      return;
    }
    setState(() => selectedMode = mode);
  }

  void showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, textAlign: TextAlign.center),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double round1(double v) => double.parse(v.toStringAsFixed(1));
  double round2(double v) => double.parse(v.toStringAsFixed(2));

  String formatMs(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(sec)}';
    return '${two(m)}:${two(sec)}';
  }

  String dateText(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final info = modeInfo[selectedMode]!;
    final speedColor = currentSpeed < info.slow
        ? const Color(0xFF00A96B)
        : currentSpeed < info.mid
            ? const Color(0xFFF0A400)
            : const Color(0xFFE63946);

    final totalDistance = trips.fold<double>(0, (a, t) => a + t.distanceKm);
    final totalTime = trips.fold<int>(0, (a, t) => a + t.durationMs);
    final longest = trips.fold<double>(0, (m, t) => max(m, t.distanceKm));
    final fastest = trips.fold<double>(0, (m, t) => max(m, t.maxSpeed));
    final bestAvg = trips.fold<double>(0, (m, t) => max(m, t.avgSpeed));
    final avgDist = trips.isEmpty ? 0.0 : totalDistance / trips.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2FAFF),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text(
                  '🛰️ عداد رحلات GPS',
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF063B63),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'للمشي والدراجة والسيارة مع حفظ الرحلات والإحصاءات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF5C7188),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                mainCard(speedColor),
                const SizedBox(height: 14),
                backgroundHelpPanel(),
                const SizedBox(height: 14),
                summaryPanel(
                  totalDistance: totalDistance,
                  totalTime: totalTime,
                  longest: longest,
                  fastest: fastest,
                  avgDist: avgDist,
                  bestAvg: bestAvg,
                ),
                const SizedBox(height: 14),
                typePanel(),
                const SizedBox(height: 14),
                chartPanel(),
                const SizedBox(height: 14),
                tripsPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget mainCard(Color speedColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(32),
      child: Column(
        children: [
          statusBar(),
          const SizedBox(height: 12),
          modeButtons(),
          const SizedBox(height: 14),
          speedBox(speedColor),
          const SizedBox(height: 14),
          actionButtons(),
          const SizedBox(height: 14),
          statsGrid(),
          const SizedBox(height: 12),
          accuracyBox(),
          const SizedBox(height: 10),
          const Text(
            'عند التشغيل سيأخذ GPS ثواني قليلة لتثبيت الإشارة، وبعدها يبدأ الحساب.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B8198),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget statusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: lightBoxDecoration(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFF50677E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: running ? const Color(0xFF00C875) : const Color(0xFFB8C7D6),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: running
                      ? const Color(0xFF00C875).withOpacity(0.25)
                      : const Color(0xFFB8C7D6).withOpacity(0.25),
                  blurRadius: 10,
                  spreadRadius: 5,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget modeButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر نوع الرحلة',
          style: TextStyle(
            color: Color(0xFF5C7188),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            modeButton(TripMode.walk),
            const SizedBox(width: 8),
            modeButton(TripMode.bike),
            const SizedBox(width: 8),
            modeButton(TripMode.car),
          ],
        ),
      ],
    );
  }

  Widget modeButton(TripMode mode) {
    final info = modeInfo[mode]!;
    final active = selectedMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => changeMode(mode),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF00A8FF), Color(0xFF0066FF)],
                  )
                : null,
            color: active ? null : Colors.white,
            border: Border.all(color: active ? const Color(0xFF00A8FF) : const Color(0xFFD7EAF5)),
          ),
          child: Text(
            '${info.icon} ${info.name}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF50677E),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget speedBox(Color speedColor) {
    final info = modeInfo[selectedMode]!;
    final hint = currentSpeed < info.slow
        ? info.slowText
        : currentSpeed < info.mid
            ? info.midText
            : info.fastText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
      decoration: lightBoxDecoration(30),
      child: Column(
        children: [
          const Text(
            'السرعة الحالية',
            style: TextStyle(
              color: Color(0xFF6B8198),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentSpeed.round().toString(),
            style: TextStyle(
              fontSize: 118,
              height: 0.92,
              fontWeight: FontWeight.w900,
              color: speedColor,
            ),
          ),
          const Text(
            'كم/ساعة',
            style: TextStyle(
              color: Color(0xFF0099CC),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              color: Color(0xFF7C8FA3),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget actionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: running ? null : startGps,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: const Color(0xFF0077FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text(
              '▶ تشغيل GPS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: running ? stopGps : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: const Color(0xFFD90429),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text(
              '⏹ إيقاف وحفظ الرحلة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: resetCurrent,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              foregroundColor: const Color(0xFF50677E),
              side: const BorderSide(color: Color(0xFFD8EAF5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text(
              '↺ تصفير بدون حفظ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: openBatterySettings,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: const Color(0xFF0077B6),
              side: const BorderSide(color: Color(0xFFBFE8FF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text(
              '🔋 السماح بالتشغيل في الخلفية',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget statsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.65,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        statCard('المسافة', totalDistanceKm.toStringAsFixed(2), 'كم'),
        statCard('أعلى سرعة', maxSpeed.toStringAsFixed(1), 'كم/س'),
        statCard('المدة', durationText(), ''),
        statCard('متوسط السرعة', avgSpeed().toStringAsFixed(1), 'كم/س'),
      ],
    );
  }

  Widget statCard(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: lightBoxDecoration(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B8198),
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Color(0xFF102033),
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: Color(0xFF7C8FA3),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget accuracyBox() {
    final acc = bestAccuracy == 999999 ? 0 : bestAccuracy;
    final pct = acc <= 0 ? 0.0 : max(0.0, min(1.0, (100 - acc) / 100));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: lightBoxDecoration(22),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '📡 أفضل دقة GPS',
                style: TextStyle(
                  color: Color(0xFF5D748C),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                acc == 0 ? '--' : '${acc.round()} متر',
                style: const TextStyle(
                  color: Color(0xFF0077B6),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: pct,
              backgroundColor: const Color(0xFFDCEEFA),
              color: const Color(0xFF00C875),
            ),
          ),
        ],
      ),
    );
  }


  Widget backgroundHelpPanel() {
    return panel(
      title: '🔋 تشغيل الخلفية',
      pill: 'مهم',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: lightBoxDecoration(20),
            child: const Text(
              'لرحلات طويلة: اضغط زر السماح بالتشغيل في الخلفية، ثم اجعل التطبيق غير مقيّد أو غير محسّن من إعدادات البطارية. لا تغلقه من التطبيقات الأخيرة أثناء الرحلة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF5C7188),
                fontWeight: FontWeight.w800,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: openBatterySettings,
            icon: const Icon(Icons.battery_saver_rounded),
            label: const Text('فتح إعدادات البطارية'),
          ),
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_applications_rounded),
            label: const Text('فتح إعدادات التطبيق'),
          ),
        ],
      ),
    );
  }

  Widget summaryPanel({
    required double totalDistance,
    required int totalTime,
    required double longest,
    required double fastest,
    required double avgDist,
    required double bestAvg,
  }) {
    return panel(
      title: '📊 ملخص كل الرحلات',
      pill: '${trips.length} رحلة',
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.55,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          summaryCard('إجمالي المسافة', totalDistance.toStringAsFixed(2), 'كم'),
          summaryCard('إجمالي الوقت', formatMs(totalTime), ''),
          summaryCard('أطول رحلة', longest.toStringAsFixed(2), 'كم'),
          summaryCard('أعلى سرعة', fastest.toStringAsFixed(1), 'كم/س'),
          summaryCard('متوسط المسافة', avgDist.toStringAsFixed(2), 'كم'),
          summaryCard('أفضل متوسط', bestAvg.toStringAsFixed(1), 'كم/س'),
        ],
      ),
    );
  }

  Widget summaryCard(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: lightBoxDecoration(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900)),
          const Spacer(),
          Text(
            unit.isEmpty ? value : '$value $unit',
            style: const TextStyle(color: Color(0xFF102033), fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget typePanel() {
    final total = trips.fold<double>(0, (a, t) => a + t.distanceKm);

    return panel(
      title: '🚶🚴🚗 حسب نوع الرحلة',
      child: Column(
        children: TripMode.values.map((mode) {
          final info = modeInfo[mode]!;
          final key = mode.name;
          final list = trips.where((t) => t.mode == key).toList();
          final dist = list.fold<double>(0, (a, t) => a + t.distanceKm);
          final pct = total > 0 ? dist / total : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: lightBoxDecoration(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('${info.icon} ${info.name}',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF063B63))),
                      const Spacer(),
                      Text('${list.length} رحلة • ${dist.toStringAsFixed(2)} كم',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0077B6))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: pct,
                      backgroundColor: const Color(0xFFDCEEFA),
                      color: const Color(0xFF00A8FF),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget chartPanel() {
    final reversed = trips.reversed.toList();
    final maxDist = reversed.fold<double>(0, (m, t) => max(m, t.distanceKm));

    return panel(
      title: '📈 رسم المسافات',
      pill: 'آخر 20',
      child: reversed.isEmpty
          ? const emptyBox('لا يوجد بيانات للرسم بعد.')
          : Column(
              children: reversed.map((t) {
                final pct = maxDist > 0 ? max(0.03, t.distanceKm / maxDist) : 0.03;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: lightBoxDecoration(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t.modeIcon} ${dateText(t.timestamp)}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF063B63),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${t.distanceKm.toStringAsFixed(2)} كم',
                              style: const TextStyle(
                                color: Color(0xFF0077B6),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 9,
                            value: pct,
                            backgroundColor: const Color(0xFFDCEEFA),
                            color: const Color(0xFF0077FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget tripsPanel() {
    final reversed = trips.reversed.toList();

    return panel(
      title: '📋 آخر الرحلات',
      pill: '${trips.length} / $maxTrips',
      child: reversed.isEmpty
          ? const emptyBox('🗺️\nلا توجد رحلات محفوظة بعد.\nابدأ رحلة وسيتم حفظها هنا.')
          : Column(
              children: reversed.map((t) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: lightBoxDecoration(22),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8FF),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: const Color(0xFFC9EDFF)),
                        ),
                        child: Center(child: Text(t.modeIcon, style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateText(t.timestamp),
                                style: const TextStyle(
                                  color: Color(0xFF6B8198),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                )),
                            const SizedBox(height: 3),
                            Text('⏱ ${formatMs(t.durationMs)} • متوسط ${t.avgSpeed.toStringAsFixed(1)} كم/س',
                                style: const TextStyle(
                                  color: Color(0xFF102033),
                                  fontWeight: FontWeight.w900,
                                )),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7F7FF),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                t.modeName,
                                style: const TextStyle(
                                  color: Color(0xFF0077B6),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${t.distanceKm.toStringAsFixed(2)} كم',
                              style: const TextStyle(
                                color: Color(0xFF0077FF),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              )),
                          const SizedBox(height: 4),
                          Text('⚡ ${t.maxSpeed.toStringAsFixed(1)} كم/س',
                              style: const TextStyle(
                                color: Color(0xFF6B8198),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              )),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget panel({required String title, String? pill, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(28),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF063B63),
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ),
              if (pill != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F7FF),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFC6EDFF)),
                  ),
                  child: Text(
                    pill,
                    style: const TextStyle(
                      color: Color(0xFF0077B6),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  BoxDecoration cardDecoration(double radius) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFFDCEEFA)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0069AA).withOpacity(0.10),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  BoxDecoration lightBoxDecoration(double radius) {
    return BoxDecoration(
      color: const Color(0xFFF7FCFF),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFFDCEEFA)),
    );
  }
}

class emptyBox extends StatelessWidget {
  final String text;
  const emptyBox(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFC6DCEC), style: BorderStyle.solid),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF6B8198),
          fontWeight: FontWeight.w800,
          height: 1.8,
        ),
      ),
    );
  }
}
