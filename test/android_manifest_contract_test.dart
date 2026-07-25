import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android build manifest keeps required location service contract', () {
    final workflow = File('.github/workflows/build-apk.yml');
    expect(workflow.existsSync(), isTrue,
        reason: 'ملف بناء APK يجب أن يبقى موجودًا');

    final source = workflow.readAsStringSync();

    const requiredEntries = <String>[
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_BACKGROUND_LOCATION',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_LOCATION',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.WAKE_LOCK',
      'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      'android:foregroundServiceType="location"',
      'android:exported="false"',
      'android:allowBackup="false"',
      'android:usesCleartextTraffic="false"',
    ];

    for (final entry in requiredEntries) {
      expect(source, contains(entry),
          reason: 'عقد Manifest مفقود أو تغيّر: $entry');
    }
  });
}
