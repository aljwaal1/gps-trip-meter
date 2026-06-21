import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../models/trip_mode.dart';
import '../models/trip_record.dart';
import '../services/geo_utils.dart';
import '../services/trip_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TripSession session;
  bool _unclosedDialogShown = false;

  @override
  void initState() {
    super.initState();
    session = TripSession();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await session.init();
    final hasUnclosed = await session.tryLoadUnclosedTrip();
    if (hasUnclosed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRestoreDialog());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync once on resume instead of polling shared_preferences every
    // second while the app is alive — see TripSession for details.
    if (state == AppLifecycleState.resumed) {
      session.handleAppResumed();
    } else if (state == AppLifecycleState.paused) {
      session.handleAppPaused();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, textAlign: TextAlign.center), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showRestoreDialog() async {
    if (!mounted || _unclosedDialogShown) return;
    _unclosedDialogShown = true;
    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة رحلة سابقة'),
          content: const Text(
            'وجدنا رحلة لم تُغلق بشكل طبيعي. يمكنك استكمالها من آخر بيانات محفوظة، أو حفظها في السجل، أو حذفها والبدء من جديد.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await session.discardUnclosed();
                _showSnack('تم حذف الرحلة بدون حفظ');
              },
              child: const Text('حذفها'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await session.saveUnclosedAsTrip();
                _showSnack('تم حفظ الرحلة');
              },
              child: const Text('حفظ الرحلة'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final ok = await session.resumeUnclosed(onMessage: _showSnack);
                if (ok) _showSnack('تم استكمال GPS...');
              },
              child: const Text('استكمال الرحلة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBackgroundTestInfo() async {
    await showDialog(
      context: context,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('شرح تشغيل الخلفية'),
          content: Text(
            'على بعض الأجهزة قد يوقف النظام التطبيق بعد دقائق. لا مشكلة: التطبيق يحفظ الرحلة باستمرار، وعند فتحه يعرض استكمال الرحلة أو حفظها. لا تضغط Clear All أثناء الرحلة.',
          ),
        ),
      ),
    );
  }

  Future<void> _requestBatteryExemption() async {
    await session.requestIgnoreBatteryOptimizations();
    _showSnack('تحقق من نافذة الإذن أو إعدادات البطارية');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _header(),
                const SizedBox(height: 14),
                // Live-tracking section: rebuilds up to once/second, but
                // only this subtree — not the whole screen.
                AnimatedBuilder(
                  animation: session,
                  builder: (context, _) => _mainCard(),
                ),
                const SizedBox(height: 14),
                _backgroundHelpPanel(),
                const SizedBox(height: 14),
                // History section: rebuilds only when a trip is
                // started/stopped/restored, not on every tick.
                ValueListenableBuilder<List<TripRecord>>(
                  valueListenable: session.tripsNotifier,
                  builder: (context, trips, _) {
                    return RepaintBoundary(
                      child: Column(
                        children: [
                          _summaryPanel(trips),
                          const SizedBox(height: 14),
                          _typePanel(trips),
                          const SizedBox(height: 14),
                          _chartPanel(trips),
                          const SizedBox(height: 14),
                          _tripsPanel(trips),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                gradient: AppColors.brandMark,
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🛰️', style: TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 10),
            const Text(
              'عداد رحلات GPS',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'للمشي والدراجة والسيارة مع حفظ الرحلات والإحصاءات',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _mainCard() {
    final info = modeInfo[session.selectedMode]!;
    final speedColor = session.currentSpeed < info.slow
        ? AppColors.success
        : session.currentSpeed < info.mid
            ? AppColors.warning
            : AppColors.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(32),
      child: Column(
        children: [
          _statusBar(),
          const SizedBox(height: 12),
          _modeButtons(),
          const SizedBox(height: 14),
          RepaintBoundary(child: _speedBox(speedColor)),
          const SizedBox(height: 14),
          _actionButtons(),
          const SizedBox(height: 14),
          _statsGrid(),
          const SizedBox(height: 12),
          _accuracyBox(),
          const SizedBox(height: 10),
          const Text(
            'عند التشغيل سيأخذ GPS ثواني قليلة لتثبيت الإشارة، وبعدها يبدأ الحساب.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    final dotColor = session.running ? AppColors.successStrong : AppColors.idle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.lightBoxDecoration(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              session.status,
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: dotColor.withValues(alpha: 0.25), blurRadius: 10, spreadRadius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر نوع الرحلة',
          style: TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _modeButton(TripMode.walk),
            const SizedBox(width: 8),
            _modeButton(TripMode.bike),
            const SizedBox(width: 8),
            _modeButton(TripMode.car),
          ],
        ),
      ],
    );
  }

  Widget _modeButton(TripMode mode) {
    final info = modeInfo[mode]!;
    final active = session.selectedMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (!session.changeMode(mode)) {
            _showSnack('لا يمكن تغيير النوع أثناء تشغيل GPS');
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: active ? AppColors.activeMode : null,
            color: active ? null : AppColors.surface,
            border: Border.all(color: active ? AppColors.primaryLight : AppColors.borderStrong),
          ),
          child: Text(
            '${info.icon} ${info.name}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _speedBox(Color speedColor) {
    final info = modeInfo[session.selectedMode]!;
    final hint = session.currentSpeed < info.slow
        ? info.slowText
        : session.currentSpeed < info.mid
            ? info.midText
            : info.fastText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
      decoration: AppTheme.lightBoxDecoration(30),
      child: Column(
        children: [
          const Text(
            'السرعة الحالية',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            session.currentSpeed.round().toString(),
            style: TextStyle(fontSize: 118, height: 0.92, fontWeight: FontWeight.w900, color: speedColor),
          ),
          const Text(
            'كم/ساعة',
            style: TextStyle(color: AppColors.accentTeal, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(color: AppColors.textSubtle, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: session.running ? null : () => session.startGps(onMessage: _showSnack),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text('▶ تشغيل GPS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: session.running
                ? () async {
                    await session.stopGps();
                    _showSnack('تم إيقاف GPS وحفظ الرحلة');
                  }
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: AppColors.dangerStrong,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text('⏹ إيقاف وحفظ الرحلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await session.resetCurrent();
              _showSnack('تم التصفير بدون حفظ');
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text('↺ تصفير بدون حفظ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _requestBatteryExemption,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: AppColors.info,
              side: const BorderSide(color: Color(0xFFBFE8FF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            child: const Text(
              '🔋 السماح بالتشغيل في الخلفية',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statsGrid() {
    return TwoColumnGrid(
      aspectRatio: 1.65,
      children: [
        StatCard(label: 'المسافة', value: session.totalDistanceKm.toStringAsFixed(2), unit: 'كم'),
        StatCard(label: 'أعلى سرعة', value: session.maxSpeed.toStringAsFixed(1), unit: 'كم/س'),
        StatCard(label: 'المدة', value: session.durationText()),
        StatCard(label: 'متوسط السرعة', value: session.avgSpeedKmh().toStringAsFixed(1), unit: 'كم/س'),
      ],
    );
  }

  Widget _accuracyBox() {
    final acc = session.bestAccuracy == 999999 ? 0 : session.bestAccuracy;
    final pct = acc <= 0 ? 0.0 : max(0.0, min(1.0, (100 - acc) / 100));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.lightBoxDecoration(22),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '📡 أفضل دقة GPS',
                style: TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                acc == 0 ? '--' : '${acc.round()} متر',
                style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(value: pct, color: AppColors.successStrong, height: 8),
        ],
      ),
    );
  }

  Widget _backgroundHelpPanel() {
    return Panel(
      title: '🔋 تشغيل الخلفية',
      pill: 'مهم',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: AppTheme.lightBoxDecoration(20),
            child: const Text(
              'هذه نسخة عملية هادئة: التطبيق يحفظ الرحلة باستمرار، وإذا أوقفه النظام يمكنك استعادتها. '
              'لنتيجة أفضل اجعل التطبيق غير محسّن للبطارية ولا تضغط Clear All أثناء الرحلة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w800, height: 1.7),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _requestBatteryExemption,
            icon: const Icon(Icons.battery_saver_rounded),
            label: const Text('فتح إعدادات البطارية'),
          ),
          OutlinedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings_applications_rounded),
            label: const Text('فتح إعدادات التطبيق'),
          ),
          OutlinedButton.icon(
            onPressed: _showBackgroundTestInfo,
            icon: const Icon(Icons.timer_rounded),
            label: const Text('شرح تشغيل الخلفية'),
          ),
        ],
      ),
    );
  }

  Widget _summaryPanel(List<TripRecord> trips) {
    final totalDistance = trips.fold<double>(0, (a, t) => a + t.distanceKm);
    final totalTime = trips.fold<int>(0, (a, t) => a + t.durationMs);
    final longest = trips.fold<double>(0, (m, t) => max(m, t.distanceKm));
    final fastest = trips.fold<double>(0, (m, t) => max(m, t.maxSpeed));
    final bestAvg = trips.fold<double>(0, (m, t) => max(m, t.avgSpeed));
    final avgDist = trips.isEmpty ? 0.0 : totalDistance / trips.length;

    return Panel(
      title: '📊 ملخص كل الرحلات',
      pill: '${trips.length} رحلة',
      child: TwoColumnGrid(
        aspectRatio: 1.55,
        children: [
          SummaryCard(label: 'إجمالي المسافة', value: totalDistance.toStringAsFixed(2), unit: 'كم'),
          SummaryCard(label: 'إجمالي الوقت', value: formatMs(totalTime)),
          SummaryCard(label: 'أطول رحلة', value: longest.toStringAsFixed(2), unit: 'كم'),
          SummaryCard(label: 'أعلى سرعة', value: fastest.toStringAsFixed(1), unit: 'كم/س'),
          SummaryCard(label: 'متوسط المسافة', value: avgDist.toStringAsFixed(2), unit: 'كم'),
          SummaryCard(label: 'أفضل متوسط', value: bestAvg.toStringAsFixed(1), unit: 'كم/س'),
        ],
      ),
    );
  }

  Widget _typePanel(List<TripRecord> trips) {
    final total = trips.fold<double>(0, (a, t) => a + t.distanceKm);

    return Panel(
      title: '🚶🚴🚗 حسب نوع الرحلة',
      child: Column(
        children: TripMode.values.map((mode) {
          final info = modeInfo[mode]!;
          final list = trips.where((t) => t.mode == mode.name).toList();
          final dist = list.fold<double>(0, (a, t) => a + t.distanceKm);
          final pct = total > 0 ? dist / total : 0.0;

          return TypeBreakdownTile(
            key: ValueKey(mode.name),
            icon: info.icon,
            name: info.name,
            count: list.length,
            distanceKm: dist,
            percent: pct,
          );
        }).toList(),
      ),
    );
  }

  Widget _chartPanel(List<TripRecord> trips) {
    final reversed = trips.reversed.toList();
    final maxDist = reversed.fold<double>(0, (m, t) => max(m, t.distanceKm));

    return Panel(
      title: '📈 رسم المسافات',
      pill: 'آخر 20',
      child: reversed.isEmpty
          ? const EmptyState('لا يوجد بيانات للرسم بعد.')
          : Column(
              children: reversed.map((t) {
                final pct = maxDist > 0 ? max(0.03, t.distanceKm / maxDist) : 0.03;
                return DistanceBarTile(key: ValueKey(t.timestamp), trip: t, percent: pct);
              }).toList(),
            ),
    );
  }

  Widget _tripsPanel(List<TripRecord> trips) {
    final reversed = trips.reversed.toList();

    return Panel(
      title: '📋 آخر الرحلات',
      pill: '${trips.length} / ${TripSession.maxTrips}',
      child: reversed.isEmpty
          ? const EmptyState('🗺️\nلا توجد رحلات محفوظة بعد.\nابدأ رحلة وسيتم حفظها هنا.')
          : Column(
              children: reversed.map((t) => TripTile(key: ValueKey(t.timestamp), trip: t)).toList(),
            ),
    );
  }
}
