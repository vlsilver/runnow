import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_recap_card.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:myrun/src/widgets/stream_chart.dart';

class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({
    required this.activityId,
    this.ownerUid,
    super.key,
  });
  final String activityId;
  final String? ownerUid;

  @override
  ConsumerState<ActivityDetailScreen> createState() =>
      _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detail = widget.ownerUid == null
        ? ref.watch(activityDetailProvider(widget.activityId))
        : ref.watch(
            memberActivityDetailProvider((
              uid: widget.ownerUid!,
              activityId: widget.activityId,
            )),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết hoạt động'),
        actions: [
          if (detail.asData?.value case final item?)
            IconButton(
              onPressed: () => _openShareComposer(item),
              tooltip: 'Chia sẻ hoạt động',
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: detail.when(
        data: (item) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RouteMap(encodedPolyline: item.summary.polyline),
            if (item.streams.isEmpty) ...[
              const SizedBox(height: 16),
              _CachedSummaryFallback(
                detail: item,
                isMemberView: widget.ownerUid != null,
              ),
            ],
            const SizedBox(height: 16),
            if (item.streams.isNotEmpty) ...[
              StreamChart(streams: item.streams),
              if (item.streams['heartrate']?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                HeartRateZoneChart(streams: item.streams),
              ],
            ],
          ],
        ),
        error: (error, stack) =>
            Center(child: Text('Không thể tải chi tiết: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _openShareComposer(ActivityDetail detail) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShareComposer(detail: detail),
    );
  }
}

class _CachedSummaryFallback extends StatelessWidget {
  const _CachedSummaryFallback({
    required this.detail,
    required this.isMemberView,
  });

  final ActivityDetail detail;
  final bool isMemberView;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMemberView ? 'DETAIL CHƯA CACHE' : 'DETAIL CHƯA HYDRATE',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.66),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FallbackMetric(
                label: 'KM',
                value: formatDistance(summary.distanceMeters),
              ),
              _FallbackMetric(
                label: 'TIME',
                value: formatDuration(summary.movingTimeSeconds),
              ),
              _FallbackMetric(
                label: 'PACE',
                value: formatPace(summary.paceSecondsPerKm),
              ),
              if (summary.averageHeartRate != null)
                _FallbackMetric(
                  label: 'HR',
                  value: '${summary.averageHeartRate!.round()} bpm',
                ),
              if (summary.averageCadence != null)
                _FallbackMetric(
                  label: 'CADENCE',
                  value: '${summary.averageCadence!.round()} rpm',
                ),
              if (summary.elevationGainMeters != null)
                _FallbackMetric(
                  label: 'ELEV',
                  value: '${summary.elevationGainMeters!.round()} m',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isMemberView
                ? 'Hoạt động public này mới có summary. Charts/streams chỉ hiện khi chủ hoạt động đã hydrate detail lên Firestore.'
                : 'Charts/streams sẽ hiện sau khi tải detail từ Strava thành công.',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackMetric extends StatelessWidget {
  const _FallbackMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.48),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareComposer extends ConsumerStatefulWidget {
  const _ShareComposer({required this.detail});

  final ActivityDetail detail;

  @override
  ConsumerState<_ShareComposer> createState() => _ShareComposerState();
}

class _ShareComposerState extends ConsumerState<_ShareComposer> {
  final _recapKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.64,
      maxChildSize: 0.96,
      builder: (context, scrollController) => GlassPanel(
        borderRadius: 18,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF041221), Color(0xFF06263E), Color(0xFF220A20)],
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SHARE // ACTIVITY',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.blueGlow,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tạo poster thành tích để chia sẻ.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            ActivityRecapCard(
              repaintBoundaryKey: _recapKey,
              activity: widget.detail.summary,
              streams: widget.detail.streams,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: _sharing ? null : () => _share(buttonContext),
                icon: _sharing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_sharing ? 'Đang tạo poster...' : 'Chia sẻ poster'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext buttonContext) async {
    setState(() => _sharing = true);
    try {
      await shareActivityRecap(
        recapKey: _recapKey,
        shareButtonContext: buttonContext,
        activity: widget.detail.summary,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể chia sẻ poster: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
