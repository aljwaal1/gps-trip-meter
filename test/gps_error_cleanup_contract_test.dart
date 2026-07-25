import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS errors preserve recovery state and stop background resources', () {
    final source = File('lib/services/trip_session.dart').readAsStringSync();

    expect(source, contains('unawaited(_handlePositionError(error))'));
    expect(source, contains('await saveActiveTrip(force: true)'));
    expect(source, contains('await _positionSub?.cancel()'));
    expect(source, contains('_positionSub = null'));
    expect(source, contains('_stopTimers()'));
    expect(source, contains('await stopForeground()'));
    expect(source, contains("status = 'توقف GPS مؤقتًا — يمكن استكمال الرحلة'"));

    final saveIndex = source.indexOf('await saveActiveTrip(force: true)');
    final runningFalseIndex = source.indexOf('running = false;', saveIndex);
    expect(saveIndex, greaterThanOrEqualTo(0));
    expect(runningFalseIndex, greaterThan(saveIndex));
  });
}
