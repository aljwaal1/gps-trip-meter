import 'package:flutter/material.dart';

import '../models/trip_record.dart';
import '../services/geo_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A titled card with an optional pill badge in the header.
class Panel extends StatelessWidget {
  final String title;
  final String? pill;
  final Widget child;

  const Panel({super.key, required this.title, this.pill, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(28),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTheme.panelTitle)),
              if (pill != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                  decoration: AppTheme.pillDecoration(),
                  child: Text(pill!, style: AppTheme.pillText),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFC6DCEC)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w800,
          height: 1.8,
        ),
      ),
    );
  }
}

/// Lightweight 2-column grid for a small, fixed number of cells.
///
/// Replaces `GridView.count(shrinkWrap: true, physics: NeverScrollable...)`
/// nested inside a `SingleChildScrollView`, which is a well-known
/// performance anti-pattern (it forces Sliver layout machinery and an
/// extra layout pass just to lay out 4-6 cards). A plain Row/Column does
/// the exact same visual job for a fixed item count at a fraction of the
/// layout cost.
class TwoColumnGrid extends StatelessWidget {
  final List<Widget> children;
  final double aspectRatio;
  final double spacing;

  const TwoColumnGrid({
    super.key,
    required this.children,
    required this.aspectRatio,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final hasSecond = i + 1 < children.length;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: AspectRatio(aspectRatio: aspectRatio, child: children[i])),
            SizedBox(width: spacing),
            Expanded(
              child: hasSecond
                  ? AspectRatio(aspectRatio: aspectRatio, child: children[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < children.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 9,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: height,
        value: value,
        backgroundColor: AppColors.border,
        color: color,
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.lightBoxDecoration(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.label),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: AppColors.textHeading,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: AppColors.textSubtle,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.lightBoxDecoration(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.label),
          const Spacer(),
          Text(
            unit.isEmpty ? value : '$value $unit',
            style: const TextStyle(
              color: AppColors.textHeading,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class TripTile extends StatelessWidget {
  final TripRecord trip;
  const TripTile({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.lightBoxDecoration(22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.chipBorder),
            ),
            child: Center(child: Text(trip.modeIcon, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateText(trip.timestamp),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '⏱ ${formatMs(trip.durationMs)} • متوسط ${trip.avgSpeed.toStringAsFixed(1)} كم/س',
                  style: const TextStyle(
                    color: AppColors.textHeading,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: AppTheme.pillDecoration(),
                  child: Text(
                    trip.modeName,
                    style: const TextStyle(
                      color: AppColors.info,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${trip.distanceKm.toStringAsFixed(2)} كم',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '⚡ ${trip.maxSpeed.toStringAsFixed(1)} كم/س',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DistanceBarTile extends StatelessWidget {
  final TripRecord trip;
  final double percent;

  const DistanceBarTile({super.key, required this.trip, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.lightBoxDecoration(18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.modeIcon} ${dateText(trip.timestamp)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${trip.distanceKm.toStringAsFixed(2)} كم',
                  style: const TextStyle(
                    color: AppColors.info,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: percent, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class TypeBreakdownTile extends StatelessWidget {
  final String icon;
  final String name;
  final int count;
  final double distanceKm;
  final double percent;

  const TypeBreakdownTile({
    super.key,
    required this.icon,
    required this.name,
    required this.count,
    required this.distanceKm,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.lightBoxDecoration(18),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '$icon $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count رحلة • ${distanceKm.toStringAsFixed(2)} كم',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: percent, color: AppColors.primaryLight, height: 8),
          ],
        ),
      ),
    );
  }
}
