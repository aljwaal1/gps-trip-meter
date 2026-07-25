from pathlib import Path

path = Path('lib/services/trip_session.dart')
text = path.read_text(encoding='utf-8')
old = '''  void _onPositionError(Object error) {
    running = false;
    status = 'خطأ في GPS';
    _stopTimers();
    notifyListeners();
  }
'''
new = '''  void _onPositionError(Object error) {
    unawaited(_handlePositionError(error));
  }

  Future<void> _handlePositionError(Object error) async {
    if (!running) return;

    // Persist the latest recoverable state before changing [running], because
    // saveActiveTrip intentionally ignores inactive sessions.
    await saveActiveTrip(force: true);
    await _positionSub?.cancel();
    _positionSub = null;
    _stopTimers();
    await stopForeground();

    running = false;
    currentSpeed = 0;
    status = 'توقف GPS مؤقتًا — يمكن استكمال الرحلة';
    notifyListeners();
  }
'''
if new in text:
    print('GPS error cleanup already merged')
elif old in text:
    path.write_text(text.replace(old, new), encoding='utf-8')
    print('Merged GPS error cleanup')
else:
    raise SystemExit('Expected _onPositionError block was not found')
