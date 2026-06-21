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

  /// GPS distanceFilter (meters) tuned per mode: walking needs fine
  /// granularity, driving can safely sample less often which reduces
  /// callback/computation/disk-write frequency without hurting accuracy.
  final int distanceFilterMeters;

  const ModeInfo({
    required this.name,
    required this.icon,
    required this.maxValidSpeed,
    required this.slow,
    required this.mid,
    required this.slowText,
    required this.midText,
    required this.fastText,
    required this.distanceFilterMeters,
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
    distanceFilterMeters: 2,
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
    distanceFilterMeters: 3,
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
    distanceFilterMeters: 5,
  ),
};

ModeInfo infoFromName(String name) {
  final mode = TripMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => TripMode.walk,
  );
  return modeInfo[mode]!;
}
