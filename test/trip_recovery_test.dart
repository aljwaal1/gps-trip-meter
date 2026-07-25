import 'package:flutter_test/flutter_test.dart';
import 'package:gps_trip_meter/services/trip_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('corrupted active-trip data is rejected without throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      activeTripKey: '{not-valid-json',
    });

    final session = TripSession();
    addTearDown(session.dispose);

    expect(await session.tryLoadUnclosedTrip(), isFalse);
    expect(session.running, isFalse);
  });

  test('inactive saved state is not offered as a recoverable trip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      activeTripKey: '{"running":false}',
    });

    final session = TripSession();
    addTearDown(session.dispose);

    expect(await session.tryLoadUnclosedTrip(), isFalse);
    expect(session.running, isFalse);
  });
}
