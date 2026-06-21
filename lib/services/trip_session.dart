import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_mode.dart';
import '../models/trip_record.dart';
import 'geo_utils.dart';

const String activeTripKey = 'active_trip_practical_v3';
const String _tripsStorageKey = 'trips_v1';

/// Owns every piece of mutable trip-tracking state and all the GPS /
/// persistence / background-service logic that used to live inline inside
/// a single giant State.build() call.
///
/// Two separate notification channels are exposed on purpose:
///  - `TripSession` itself (a [ChangeNotifier]) fires on "live" changes
///    that happen up to once per second while a trip is running (speed,
///    duration, status...).
///  - [tripsNotifier] only fires when the *saved trip history* changes,
///    which happens at most a few times per trip (start/stop/restore).
///
/// Keeping these separate lets the UI rebuild only the small "live" widgets
/// every second instead of re-laying-out the entire screen (including
/// potentially 20 history cards and a chart) on every tick.
class TripSession extends ChangeNotifier {
  static const int maxTrips = 20;
  static const int warmupMs = 8000;
  static const int warmupPoints = 4;

  TripMode selectedMode = TripMode.walk;
  bool running = false;
  String status = 'اضغط تشغيل للبدء';

  DateTime? startTime;
  Position? lastPos;
  int pointsCount = 0;

  double currentSpeed = 0;
  double totalDistanceKm = 0;
  double maxSpeed = 0;
  double bestAccuracy = 999999;

  final ValueNotifier<List<TripRecord>> tripsNotifier =
      ValueNotifier<List<TripRecord>>(const []);
  List<TripRecord> get trips => tripsNotifier.value;

  StreamSubscription<Position>? _positionSub;
  Timer? _uiTicker;
  Timer? _diskSaveTimer;
  DateTime? _lastDiskSaveAt;

  Future<void> init() async {
    _initForegroundTask();
    await loadTrips();
  }

  void _initForegroundTask() {
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
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Foreground service
  // ---------------------------------------------------------------------

  Future<void> startForeground() async {
    await FlutterForegroundTask.requestNotificationPermission();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'عداد رحلات GPS يعمل بهدوء',
        notificationText: 'يتم حفظ الرحلة تلقائيًا عند التوقف',
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'عداد رحلات GPS يعمل بهدوء',
        notificationText: 'يتم حفظ الرحلة تلقائيًا عند التوقف',
        callback: startCallback,
      );
    }
  }

  Future<void> stopForeground() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ---------------------------------------------------------------------
  // Permissions (battery optimization + background location), now backed
  // by the permission_handler plugin instead of a custom native
  // MethodChannel that had no platform-side implementation.
  // ---------------------------------------------------------------------

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  Future<bool> ensureLocationPermission({
    required ValueChanged<String> onMessage,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      onMessage('فعّل GPS من إعدادات الهاتف');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      onMessage('اسمح للتطبيق باستخدام الموقع');
      return false;
    }

    if (Platform.isAndroid) {
      try {
        final bg = await Permission.locationAlways.status;
        if (!bg.isGranted) {
          // Best-effort upgrade to "Allow all the time" so tracking
          // survives the app being minimized. Foreground tracking still
          // works even if the user declines this.
          await Permission.locationAlways.request();
        }
      } catch (_) {}
    }

    return true;
  }

  // ---------------------------------------------------------------------
  // Active trip persistence (crash / kill recovery)
  // ---------------------------------------------------------------------

  Future<void> saveActiveTrip({bool force = false}) async {
    if (!running || startTime == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastDiskSaveAt != null &&
        now.difference(_lastDiskSaveAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastDiskSaveAt = now;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      activeTripKey,
      jsonEncode({
        'running': true,
        'mode': selectedMode.name,
        'startTime': startTime!.millisecondsSinceEpoch,
        'lastPos': positionToMap(lastPos),
        'pointsCount': pointsCount,
        'currentSpeed': currentSpeed,
        'totalDistanceKm': totalDistanceKm,
        'maxSpeed': maxSpeed,
        'bestAccuracy': bestAccuracy,
        'lastSavedAt': now.millisecondsSinceEpoch,
        'appAliveAt': now.millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> clearActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(activeTripKey);
  }

  /// Looks for a trip that was running but never closed (app/process was
  /// killed). Populates the session fields (still paused) and returns
  /// true so the UI can offer to resume / save / discard it.
  Future<bool> tryLoadUnclosedTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(activeTripKey);
    if (raw == null) return false;

    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      if (m['running'] != true) return false;

      final modeName = m['mode'] ?? TripMode.walk.name;
      selectedMode = TripMode.values.firstWhere(
        (x) => x.name == modeName,
        orElse: () => TripMode.walk,
      );
      startTime = DateTime.fromMillisecondsSinceEpoch(
        m['startTime'] ?? DateTime.now().millisecondsSinceEpoch,
      );
      lastPos = positionFromMap(m['lastPos']);
      pointsCount = m['pointsCount'] ?? 0;
      currentSpeed = (m['currentSpeed'] ?? 0).toDouble();
      totalDistanceKm = (m['totalDistanceKm'] ?? 0).toDouble();
      maxSpeed = (m['maxSpeed'] ?? 0).toDouble();
      bestAccuracy = (m['bestAccuracy'] ?? 999999).toDouble();

      running = false;
      status = 'تم العثور على رحلة غير مغلقة';
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> discardUnclosed() async {
    await clearActiveTrip();
    await resetCurrent();
  }

  Future<void> saveUnclosedAsTrip() async {
    if (startTime == null) return;
    final durationMs = DateTime.now().difference(startTime!).inMilliseconds;
    final hours = durationMs / 3600000.0;
    final avg = hours > 0 ? totalDistanceKm / hours : 0.0;
    final info = modeInfo[selectedMode]!;

    final list = List<TripRecord>.from(tripsNotifier.value)
      ..add(TripRecord(
        mode: selectedMode.name,
        modeName: info.name,
        modeIcon: info.icon,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        durationMs: durationMs,
        distanceKm: round2(totalDistanceKm),
        maxSpeed: round1(maxSpeed),
        avgSpeed: round1(avg),
      ));
    await _persistTrips(list);
    await clearActiveTrip();

    running = false;
    status = 'تم حفظ الرحلة المستعادة';
    currentSpeed = 0;
    startTime = null;
    lastPos = null;
    pointsCount = 0;
    notifyListeners();
  }

  /// Pulls any progress the background isolate made while this UI isolate
  /// was suspended. Called once when the app comes back to the
  /// foreground rather than polled every second, which is the single
  /// biggest disk-I/O reduction in this app.
  Future<void> refreshFromActiveTrip() async {
    if (!running) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(activeTripKey);
    if (raw == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      if (m['lastBackgroundUpdate'] == null) return;

      lastPos = positionFromMap(m['lastPos']) ?? lastPos;
      pointsCount = m['pointsCount'] ?? pointsCount;
      currentSpeed = (m['currentSpeed'] ?? currentSpeed).toDouble();
      totalDistanceKm = (m['totalDistanceKm'] ?? totalDistanceKm).toDouble();
      maxSpeed = (m['maxSpeed'] ?? maxSpeed).toDouble();
      bestAccuracy = (m['bestAccuracy'] ?? bestAccuracy).toDouble();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Trip history
  // ---------------------------------------------------------------------

  Future<void> loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tripsStorageKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => TripRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.maxSpeed <= 180 && t.distanceKm >= 0)
          .toList();
      tripsNotifier.value = list;
    } catch (_) {}
  }

  Future<void> _persistTrips(List<TripRecord> list) async {
    final trimmed =
        list.length > maxTrips ? list.sublist(list.length - maxTrips) : list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tripsStorageKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
    tripsNotifier.value = trimmed;
  }

  // ---------------------------------------------------------------------
  // Tracking lifecycle
  // ---------------------------------------------------------------------

  void _startTimers() {
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });

    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      saveActiveTrip(force: true);
    });
  }

  void _stopTimers() {
    _uiTicker?.cancel();
    _uiTicker = null;
    _diskSaveTimer?.cancel();
    _diskSaveTimer = null;
  }

  LocationSettings _locationSettingsForMode() {
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: modeInfo[selectedMode]!.distanceFilterMeters,
    );
  }

  Future<bool> startGps({required ValueChanged<String> onMessage}) async {
    if (!await ensureLocationPermission(onMessage: onMessage)) return false;

    await startForeground();

    running = true;
    status = 'تثبيت إشارة GPS...';
    startTime = DateTime.now();
    lastPos = null;
    pointsCount = 0;
    currentSpeed = 0;
    totalDistanceKm = 0;
    maxSpeed = 0;
    bestAccuracy = 999999;
    notifyListeners();

    _startTimers();
    await saveActiveTrip(force: true);

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettingsForMode(),
    ).listen(onPosition, onError: _onPositionError);

    onMessage('جاري تشغيل GPS...');
    return true;
  }

  Future<bool> resumeUnclosed({required ValueChanged<String> onMessage}) async {
    if (!await ensureLocationPermission(onMessage: onMessage)) return false;

    await startForeground();

    running = true;
    status = 'تم استكمال الرحلة';
    notifyListeners();

    _startTimers();

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettingsForMode(),
    ).listen(onPosition, onError: _onPositionError);

    await saveActiveTrip(force: true);
    onMessage('تم استكمال GPS...');
    return true;
  }

  void _onPositionError(Object error) {
    running = false;
    status = 'خطأ في GPS';
    _stopTimers();
    notifyListeners();
  }

  Future<void> stopGps() async {
    if (!running) return;

    await _positionSub?.cancel();
    _positionSub = null;
    _stopTimers();
    await stopForeground();

    final durationMs =
        DateTime.now().difference(startTime ?? DateTime.now()).inMilliseconds;
    final hours = durationMs / 3600000.0;
    final avg = hours > 0 ? totalDistanceKm / hours : 0.0;
    final info = modeInfo[selectedMode]!;

    if (totalDistanceKm > 0 || durationMs >= 10000) {
      final list = List<TripRecord>.from(tripsNotifier.value)
        ..add(TripRecord(
          mode: selectedMode.name,
          modeName: info.name,
          modeIcon: info.icon,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          durationMs: durationMs,
          distanceKm: round2(totalDistanceKm),
          maxSpeed: round1(maxSpeed),
          avgSpeed: round1(avg),
        ));
      await _persistTrips(list);
    }

    await clearActiveTrip();

    running = false;
    status = 'تم حفظ الرحلة ✓';
    currentSpeed = 0;
    notifyListeners();
  }

  Future<void> resetCurrent() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _stopTimers();
    await stopForeground();

    running = false;
    status = 'اضغط تشغيل للبدء';
    startTime = null;
    lastPos = null;
    pointsCount = 0;
    currentSpeed = 0;
    totalDistanceKm = 0;
    maxSpeed = 0;
    bestAccuracy = 999999;
    notifyListeners();
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
      kmh = speedFromPositions(lastPos!, pos);
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
    currentSpeed = kmh;
    status = _buildStatusText(warmingUp, badAccuracy, pos.accuracy);
    notifyListeners();

    unawaited(saveActiveTrip());
  }

  String _buildStatusText(bool warmingUp, bool badAccuracy, double accuracy) {
    if (warmingUp) return 'تثبيت إشارة GPS...';
    if (badAccuracy) return 'دقة ضعيفة • ${accuracy.round()}م';
    if (accuracy <= 10) return 'دقة ممتازة • ${accuracy.round()}م';
    if (accuracy <= 40) return 'دقة جيدة • ${accuracy.round()}م';
    return 'GPS يعمل الآن';
  }

  bool changeMode(TripMode mode) {
    if (running) return false;
    selectedMode = mode;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------
  // App lifecycle hooks (wired from the screen's WidgetsBindingObserver)
  // ---------------------------------------------------------------------

  Future<void> handleAppResumed() async {
    if (!running) return;
    await refreshFromActiveTrip();
    notifyListeners();
  }

  void handleAppPaused() {
    if (!running) return;
    unawaited(saveActiveTrip(force: true));
  }

  // ---------------------------------------------------------------------
  // Derived display values
  // ---------------------------------------------------------------------

  String durationText() {
    if (startTime == null) return '00:00';
    final ms = DateTime.now().difference(startTime!).inMilliseconds;
    return formatMs(ms);
  }

  double avgSpeedKmh() {
    if (startTime == null) return 0;
    final hours =
        DateTime.now().difference(startTime!).inMilliseconds / 3600000.0;
    return hours > 0 ? totalDistanceKm / hours : 0;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stopTimers();
    tripsNotifier.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------
// Background isolate entry point
// ---------------------------------------------------------------------

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
        timeLimit: Duration(seconds: 12),
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
    kmh = speedFromPositions(oldPos, pos);
  }
  kmh = max(0, kmh);

  final warmingUp = elapsedMs < 8000 || points < 4;
  final badAccuracy = pos.accuracy > 40;
  final impossibleSpeed = kmh > info.maxValidSpeed;

  final valid = !warmingUp && !badAccuracy && !impossibleSpeed && oldPos != null;

  if (valid) {
    if (kmh > maxSpeed) maxSpeed = kmh;
    final d = distanceKm(oldPos, pos);
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
    // The notification text never changes while a trip is running, so we
    // avoid calling FlutterForegroundTask.updateService() on every tick —
    // one less native binder call every 10 seconds for the lifetime of
    // the trip.
    updateActiveTripFromBackground();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
