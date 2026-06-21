import 'package:geolocator/geolocator.dart';

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
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        m['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
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

double distanceKm(Position a, Position b) {
  return Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) /
      1000.0;
}

double speedFromPositions(Position oldPos, Position newPos) {
  final d = distanceKm(oldPos, newPos);
  final hours = newPos.timestamp.difference(oldPos.timestamp).inMilliseconds / 3600000.0;
  return hours > 0 ? d / hours : 0;
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
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}'
      '  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
