import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background GPS updates are serialized', () {
    final source = File('lib/services/trip_session.dart').readAsStringSync();

    expect(source, contains('bool _backgroundUpdateInProgress = false;'));
    expect(source, contains('Future<void> _runBackgroundUpdateOnce() async'));
    expect(source, contains('if (_backgroundUpdateInProgress) return;'));
    expect(source, contains('_backgroundUpdateInProgress = true;'));
    expect(source, contains('await updateActiveTripFromBackground();'));
    expect(source, contains('finally {'));
    expect(source, contains('_backgroundUpdateInProgress = false;'));
    expect(source, contains('unawaited(_runBackgroundUpdateOnce());'));
  });
}
