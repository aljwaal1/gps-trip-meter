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
