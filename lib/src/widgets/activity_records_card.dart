import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class ActivityRecordEntry {
  const ActivityRecordEntry({
    required this.activity,
    this.ownerUid,
    this.ownerName,
    this.ownerAvatarUrl,
  });

  final ActivitySummary activity;
  final String? ownerUid;
  final String? ownerName;
  final String? ownerAvatarUrl;
}

class ActivityRecordsCard extends StatelessWidget {
  const ActivityRecordsCard({
    required this.entries,
    this.title = 'BEST BOARD',
    this.showOwner = false,
    this.showWhenEmpty = false,
    this.emptyMessage = 'Chưa có dữ liệu kỷ lục.',
    super.key,
  });

  final List<ActivityRecordEntry> entries;
  final String title;
  final bool showOwner;
  final bool showWhenEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final records = _ActivityRecords.fromEntries(entries);
    if (!records.hasAnyRecord && !showWhenEmpty) {
      return const SizedBox.shrink();
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xfff9fbff), Color(0xffeaf2fb), Color(0xfff5f8fc)]
            : const [Color(0xf207172b), Color(0xe005243f), Color(0xb3121027)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              Text(
                '${entries.length} logs',
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (records.hasAnyRecord) ...[
            _StandardDistanceGrid(records: records, showOwner: showOwner),
            const SizedBox(height: 12),
            _HighlightGrid(records: records, showOwner: showOwner),
          ] else
            _EmptyRecordsState(message: emptyMessage),
        ],
      ),
    );
  }
}

class _EmptyRecordsState extends StatelessWidget {
  const _EmptyRecordsState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, color: AppColors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StandardDistanceGrid extends StatelessWidget {
  const _StandardDistanceGrid({required this.records, required this.showOwner});

  final _ActivityRecords records;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _RecordCardData.distance(
        label: '5K',
        targetMeters: 5000,
        record: records.k5,
      ),
      _RecordCardData.distance(
        label: '10K',
        targetMeters: 10000,
        record: records.k10,
      ),
      _RecordCardData.distance(
        label: '21K',
        targetMeters: 21097.5,
        record: records.half,
      ),
      _RecordCardData.distance(
        label: '42K',
        targetMeters: 42195,
        record: records.full,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 98,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) =>
          _RecordTile(data: cards[index], showOwner: showOwner),
    );
  }
}

class _HighlightGrid extends StatelessWidget {
  const _HighlightGrid({required this.records, required this.showOwner});

  final _ActivityRecords records;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _RecordCardData(
        label: 'LONG RUN',
        value: records.longest == null
            ? '--'
            : formatDistance(records.longest!.activity.distanceMeters),
        subtitle: records.longest == null
            ? 'Chưa có'
            : formatDuration(records.longest!.activity.movingTimeSeconds),
        record: records.longest,
        color: AppColors.blue,
        icon: Icons.straighten,
      ),
      _RecordCardData(
        label: 'PACE',
        value: formatPace(records.fastestPace?.activity.paceSecondsPerKm),
        subtitle: records.fastestPace == null
            ? 'Chưa có'
            : formatDistance(records.fastestPace!.activity.distanceMeters),
        record: records.fastestPace,
        color: const Color(0xff19f58a),
        icon: Icons.speed,
      ),
      _RecordCardData(
        label: 'LOW HR',
        value: records.lowestHeartRate?.activity.averageHeartRate == null
            ? '--'
            : '${records.lowestHeartRate!.activity.averageHeartRate!.round()} bpm',
        subtitle: records.lowestHeartRate == null
            ? 'Chưa có'
            : formatDistance(records.lowestHeartRate!.activity.distanceMeters),
        record: records.lowestHeartRate,
        color: AppColors.red,
        icon: Icons.favorite,
      ),
      _RecordCardData(
        label: 'TIME',
        value: records.longestTime == null
            ? '--'
            : formatDuration(records.longestTime!.activity.movingTimeSeconds),
        subtitle: records.longestTime == null
            ? 'Chưa có'
            : formatDistance(records.longestTime!.activity.distanceMeters),
        record: records.longestTime,
        color: AppColors.amber,
        icon: Icons.timer,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 104,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) =>
          _RecordTile(data: cards[index], showOwner: showOwner),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.data, required this.showOwner});

  final _RecordCardData data;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ownerName = data.record?.ownerName;
    final record = data.record;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: record == null ? null : () => _openRecord(context, record),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                data.color.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(data.icon, color: data.color, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        data.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: data.color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                if (showOwner && ownerName != null)
                  _OwnerLine(record: data.record!)
                else
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRecord(BuildContext context, ActivityRecordEntry record) {
    final ownerUid = record.ownerUid;
    final activityId = record.activity.id;
    context.push(
      ownerUid == null
          ? '/activity/$activityId'
          : '/club/$ownerUid/activity/$activityId',
    );
  }
}

class _OwnerLine extends StatelessWidget {
  const _OwnerLine({required this.record});

  final ActivityRecordEntry record;

  @override
  Widget build(BuildContext context) {
    final name = record.ownerName ?? 'RunNow member';
    final avatarUrl = record.ownerAvatarUrl;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        CircleAvatar(
          radius: 8,
          backgroundColor: AppColors.blueGlow.withValues(alpha: 0.18),
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          child: avatarUrl == null
              ? Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.blueGlow,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordCardData {
  const _RecordCardData({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.record,
    required this.color,
    required this.icon,
  });

  factory _RecordCardData.distance({
    required String label,
    required double targetMeters,
    required ActivityRecordEntry? record,
  }) {
    final seconds = _estimatedTargetSeconds(record?.activity, targetMeters);
    return _RecordCardData(
      label: label,
      value: seconds == null ? '--' : formatDuration(seconds),
      subtitle: record == null
          ? 'Chưa có'
          : formatPace(record.activity.paceSecondsPerKm),
      record: record,
      color: AppColors.blueGlow,
      icon: Icons.flag,
    );
  }

  final String label;
  final String value;
  final String subtitle;
  final ActivityRecordEntry? record;
  final Color color;
  final IconData icon;
}

class _ActivityRecords {
  const _ActivityRecords({
    required this.k5,
    required this.k10,
    required this.half,
    required this.full,
    required this.longest,
    required this.longestTime,
    required this.fastestPace,
    required this.lowestHeartRate,
  });

  factory _ActivityRecords.fromEntries(List<ActivityRecordEntry> entries) {
    final valid = entries
        .where((entry) => entry.activity.distanceMeters > 0)
        .toList();
    ActivityRecordEntry? byDistance(double targetMeters) {
      final candidates = valid
          .where((entry) => entry.activity.distanceMeters >= targetMeters)
          .toList();
      if (candidates.isEmpty) return null;
      candidates.sort((left, right) {
        final leftSeconds =
            _estimatedTargetSeconds(left.activity, targetMeters) ?? 1 << 30;
        final rightSeconds =
            _estimatedTargetSeconds(right.activity, targetMeters) ?? 1 << 30;
        return leftSeconds.compareTo(rightSeconds);
      });
      return candidates.first;
    }

    ActivityRecordEntry? maxBy(num Function(ActivitySummary activity) score) {
      if (valid.isEmpty) return null;
      final sorted = [...valid]
        ..sort(
          (left, right) =>
              score(right.activity).compareTo(score(left.activity)),
        );
      return sorted.first;
    }

    ActivityRecordEntry? minPace() {
      final candidates = valid
          .where(
            (entry) =>
                entry.activity.paceSecondsPerKm != null &&
                entry.activity.paceSecondsPerKm! > 0,
          )
          .toList();
      if (candidates.isEmpty) return null;
      candidates.sort(
        (left, right) => left.activity.paceSecondsPerKm!.compareTo(
          right.activity.paceSecondsPerKm!,
        ),
      );
      return candidates.first;
    }

    ActivityRecordEntry? minHeartRate() {
      final candidates = valid
          .where(
            (entry) =>
                entry.activity.averageHeartRate != null &&
                entry.activity.averageHeartRate! > 0,
          )
          .toList();
      if (candidates.isEmpty) return null;
      candidates.sort(
        (left, right) => left.activity.averageHeartRate!.compareTo(
          right.activity.averageHeartRate!,
        ),
      );
      return candidates.first;
    }

    return _ActivityRecords(
      k5: byDistance(5000),
      k10: byDistance(10000),
      half: byDistance(21097.5),
      full: byDistance(42195),
      longest: maxBy((activity) => activity.distanceMeters),
      longestTime: maxBy((activity) => activity.movingTimeSeconds),
      fastestPace: minPace(),
      lowestHeartRate: minHeartRate(),
    );
  }

  final ActivityRecordEntry? k5;
  final ActivityRecordEntry? k10;
  final ActivityRecordEntry? half;
  final ActivityRecordEntry? full;
  final ActivityRecordEntry? longest;
  final ActivityRecordEntry? longestTime;
  final ActivityRecordEntry? fastestPace;
  final ActivityRecordEntry? lowestHeartRate;

  bool get hasAnyRecord =>
      k5 != null ||
      k10 != null ||
      half != null ||
      full != null ||
      longest != null ||
      longestTime != null ||
      fastestPace != null ||
      lowestHeartRate != null;
}

int? _estimatedTargetSeconds(ActivitySummary? activity, double targetMeters) {
  if (activity == null || activity.distanceMeters < targetMeters) return null;
  if (activity.distanceMeters <= 0 || activity.movingTimeSeconds <= 0) {
    return null;
  }
  return (activity.movingTimeSeconds * targetMeters / activity.distanceMeters)
      .round();
}
