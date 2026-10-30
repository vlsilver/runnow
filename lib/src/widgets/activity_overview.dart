import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// "Hôm nay 04:10", "Hôm qua 18:20", hoặc "25/10 06:00" theo giờ máy.
String sessionWhenLabel(DateTime startedAt, DateTime now) {
  final local = startedAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat('HH:mm').format(local);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Hôm nay $time';
  if (daysAgo == 1) return 'Hôm qua $time';
  return '${DateFormat('dd/MM').format(local)} $time';
}

String activityKindLabel(ActivityKind kind) => switch (kind) {
  ActivityKind.run => 'Chạy bộ',
  ActivityKind.trailRun => 'Chạy trail',
  ActivityKind.virtualRun => 'Chạy máy',
  ActivityKind.walk => 'Đi bộ',
  ActivityKind.hike => 'Leo núi',
  ActivityKind.ride => 'Đạp xe',
  ActivityKind.swim => 'Bơi',
  ActivityKind.gym => 'Tập gym',
  ActivityKind.motorbike => 'Xe máy',
};

/// Phần đầu màn chi tiết: ai chạy, khi nào, tên buổi, ba số chính và lưới
/// các số phụ (chỉ hiện ô có dữ liệu).
class ActivityOverview extends StatelessWidget {
  const ActivityOverview({required this.detail, this.owner, super.key});

  final ActivityDetail detail;

  /// Người chạy khi xem buổi của thành viên khác; null khi là buổi của mình.
  final MemberProfile? owner;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final when =
        '${sessionWhenLabel(summary.startedAt, DateTime.now())} · '
        '${activityKindLabel(summary.kind)}';
    final cells = _cells(detail);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (owner case final owner?) ...[
                _Avatar(member: owner),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (owner case final owner?)
                      Text(
                        owner.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    Text(
                      when,
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.name.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary.name,
              style: const TextStyle(
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Big(
                  value: (summary.distanceMeters / 1000).toStringAsFixed(2),
                  label: 'km',
                ),
              ),
              Expanded(
                child: _Big(
                  value: formatDuration(summary.movingTimeSeconds),
                  label: 'thời gian',
                ),
              ),
              Expanded(
                child: _Big(
                  value: formatPace(
                    summary.paceSecondsPerKm,
                  ).replaceAll(' /km', ''),
                  label: '/km',
                ),
              ),
            ],
          ),
          if (cells.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Grid(cells: cells),
          ],
          if (detail.gearName case final gear? when gear.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.hiking_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    gear,
                    style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static List<_Cell> _cells(ActivityDetail detail) {
    final summary = detail.summary;
    final heartRates = detail.streams['heartrate'];
    final maxHeartRate = heartRates == null || heartRates.isEmpty
        ? null
        : heartRates.reduce(math.max);
    // Tổng chỉ đáng hiện khi dừng nghỉ đáng kể so với thời gian chạy.
    final paused = summary.elapsedTimeSeconds - summary.movingTimeSeconds;
    return [
      if (summary.elevationGainMeters case final gain?)
        _Cell(Icons.terrain_rounded, 'Leo', '${gain.round()}', 'm'),
      if (summary.averageHeartRate case final hr?)
        _Cell(Icons.favorite_rounded, 'Nhịp tim', '${hr.round()}', 'tb'),
      if (maxHeartRate != null && maxHeartRate > 0)
        _Cell(
          Icons.monitor_heart_rounded,
          'Max',
          '${maxHeartRate.round()}',
          'bpm',
        ),
      if (summary.averageCadence case final cadence?)
        _Cell(
          Icons.directions_run_rounded,
          'Cadence',
          '${cadence.round()}',
          '',
        ),
      if (detail.calories case final kcal? when kcal > 0)
        _Cell(
          Icons.local_fire_department_rounded,
          'Calo',
          '${kcal.round()}',
          '',
        ),
      if (paused >= 60)
        _Cell(
          Icons.schedule_rounded,
          'Tổng',
          formatDuration(summary.elapsedTimeSeconds),
          '',
        ),
    ];
  }
}

class _Cell {
  const _Cell(this.icon, this.label, this.value, this.unit);

  final IconData icon;
  final String label;
  final String value;
  final String unit;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cells});

  final List<_Cell> cells;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cell in cells)
              Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: palette.glassStart,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _CellBody(cell: cell),
              ),
          ],
        );
      },
    );
  }
}

class _CellBody extends StatelessWidget {
  const _CellBody({required this.cell});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(cell.icon, size: 13, color: muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                cell.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: cell.value),
              if (cell.unit.isNotEmpty)
                TextSpan(
                  text: ' ${cell.unit}',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
            ],
          ),
          style: const TextStyle(
            fontFamily: 'Barlow Condensed',
            fontSize: 22,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Barlow Condensed',
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member});

  final MemberProfile member;

  @override
  Widget build(BuildContext context) {
    final url = member.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = member.displayName;
    return CircleAvatar(
      radius: 20,
      backgroundColor: context.runNowPalette.accent,
      backgroundImage: hasUrl ? cachedAvatarImage(context, url, 40) : null,
      child: hasUrl
          ? null
          : Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}
