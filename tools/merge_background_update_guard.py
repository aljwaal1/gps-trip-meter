from pathlib import Path

path = Path('lib/services/trip_session.dart')
text = path.read_text(encoding='utf-8')

if 'bool _backgroundUpdateInProgress = false;' in text:
    raise SystemExit(0)

old = """class GpsTaskHandler extends TaskHandler {
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
"""

new = """class GpsTaskHandler extends TaskHandler {
  bool _backgroundUpdateInProgress = false;

  Future<void> _runBackgroundUpdateOnce() async {
    if (_backgroundUpdateInProgress) return;
    _backgroundUpdateInProgress = true;
    try {
      await updateActiveTripFromBackground();
    } finally {
      _backgroundUpdateInProgress = false;
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _runBackgroundUpdateOnce();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // A location lookup can outlive the 10-second service interval on slow
    // devices. Keep at most one update active to avoid concurrent writes to
    // the persisted trip state.
    unawaited(_runBackgroundUpdateOnce());
  }
"""

if old not in text:
    raise SystemExit('Expected GpsTaskHandler block was not found; refusing unsafe merge.')

path.write_text(text.replace(old, new, 1), encoding='utf-8')
