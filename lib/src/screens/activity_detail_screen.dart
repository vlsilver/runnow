import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  final ValueNotifier<double?> _selectedDistanceMeters = ValueNotifier(null);

  @override
  void dispose() {
    _selectedDistanceMeters.dispose();
    super.dispose();
  }

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: detail.when(
            data: (item) => CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ActivityRouteHeaderDelegate(
                    detail: item,
                    selectedDistanceMeters: _selectedDistanceMeters,
                    onPhotoTap: _openPhoto,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (item.streams.isEmpty) ...[
                        const SizedBox(height: 16),
                        _CachedSummaryFallback(
                          detail: item,
                          isMemberView: widget.ownerUid != null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (item.photos.isNotEmpty) ...[
                        _ActivityPhotoGallery(
                          photos: item.photos,
                          onPhotoTap: _openPhoto,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (item.streams.isNotEmpty) ...[
                        StreamChart(
                          streams: item.streams,
                          onDistanceSelected: (distance) =>
                              _selectedDistanceMeters.value = distance,
                        ),
                        if (item.streams['heartrate']?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          HeartRateZoneChart(streams: item.streams),
                        ],
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
            error: (error, stack) =>
                Center(child: Text('Không thể tải chi tiết: $error')),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
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

  Future<void> _openPhoto(ActivityPhoto photo) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _StoragePhoto(
                  path: photo.storagePath,
                  fit: BoxFit.contain,
                  interactive: true,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Text(
                  '${formatDistance(photo.distanceMeters)} · '
                  '${photo.capturedAt.day.toString().padLeft(2, '0')}/'
                  '${photo.capturedAt.month.toString().padLeft(2, '0')} '
                  '${photo.capturedAt.hour.toString().padLeft(2, '0')}:'
                  '${photo.capturedAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityRouteHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ActivityRouteHeaderDelegate({
    required this.detail,
    required this.selectedDistanceMeters,
    required this.onPhotoTap,
  });

  final ActivityDetail detail;
  final ValueListenable<double?> selectedDistanceMeters;
  final ValueChanged<ActivityPhoto> onPhotoTap;

  @override
  double get minExtent => 176;

  @override
  double get maxExtent => 330;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final height = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ValueListenableBuilder<double?>(
        valueListenable: selectedDistanceMeters,
        builder: (context, selectedDistance, _) => RouteMap(
          encodedPolyline: detail.summary.polyline,
          routePoints: detail.summary.routePoints,
          photos: detail.photos,
          onPhotoTap: onPhotoTap,
          highlightedDistanceMeters: selectedDistance,
          totalDistanceMeters: detail.summary.distanceMeters,
          height: height,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ActivityRouteHeaderDelegate oldDelegate) {
    return oldDelegate.detail != detail ||
        oldDelegate.selectedDistanceMeters != selectedDistanceMeters;
  }
}

class _ActivityPhotoGallery extends StatelessWidget {
  const _ActivityPhotoGallery({required this.photos, required this.onPhotoTap});

  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Semantics(
            button: true,
            label: 'Mở ảnh tại ${formatDistance(photo.distanceMeters)}',
            child: GestureDetector(
              onTap: () => onPhotoTap(photo),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 148,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _StoragePhoto(path: photo.storagePath),
                      Positioned(
                        left: 8,
                        bottom: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              formatDistance(photo.distanceMeters),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoragePhoto extends StatefulWidget {
  const _StoragePhoto({
    required this.path,
    this.fit = BoxFit.cover,
    this.interactive = false,
  });

  final String path;
  final BoxFit fit;
  final bool interactive;

  @override
  State<_StoragePhoto> createState() => _StoragePhotoState();
}

class _StoragePhotoState extends State<_StoragePhoto> {
  static const _maxPhotoBytes = 8 * 1024 * 1024;
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _StoragePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _bytes = _loadBytes();
  }

  Future<Uint8List?> _loadBytes() =>
      FirebaseStorage.instance.ref(widget.path).getData(_maxPhotoBytes);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final image = Image.memory(
          bytes,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
        );
        if (!widget.interactive) return image;
        return InteractiveViewer(minScale: 1, maxScale: 4, child: image);
      },
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
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: palette.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TỔNG QUAN HOẠT ĐỘNG',
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
                ? 'Hoạt động này chưa có biểu đồ chi tiết (pace, nhịp tim, độ cao theo thời gian).'
                : 'Biểu đồ chi tiết sẽ hiện sau khi đồng bộ xong dữ liệu hoạt động.',
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
    final palette = context.runNowPalette;
    return SizedBox(
      width: 96,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: palette.secondary.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
        ),
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
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
    final palette = context.runNowPalette;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.64,
      maxChildSize: 0.96,
      builder: (context, scrollController) => GlassPanel(
        borderRadius: 18,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.backgroundDeep,
            palette.glassStart,
            palette.backgroundMid,
          ],
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SHARE // ACTIVITY',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: palette.secondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tạo poster thành tích để chia sẻ.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
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
