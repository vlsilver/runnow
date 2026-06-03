import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_recap_card.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:myrun/src/widgets/stream_chart.dart';

class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({required this.activityId, super.key});
  final String activityId;

  @override
  ConsumerState<ActivityDetailScreen> createState() =>
      _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(activityDetailProvider(widget.activityId));
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
            const SizedBox(height: 16),
            StreamChart(streams: item.streams),
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

class _ShareComposer extends ConsumerStatefulWidget {
  const _ShareComposer({required this.detail});

  final ActivityDetail detail;

  @override
  ConsumerState<_ShareComposer> createState() => _ShareComposerState();
}

class _ShareComposerState extends ConsumerState<_ShareComposer> {
  final _recapKey = GlobalKey();
  bool _sharing = false;
  bool _publishing = false;

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
              'Tạo poster thành tích hoặc đăng hoạt động lên feed.',
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.people),
              label: Text(_publishing ? 'Đang cập nhật...' : 'Đăng lên feed'),
            ),
            TextButton.icon(
              onPressed: _publishing ? null : _removeFromFeed,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Gỡ khỏi feed'),
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

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      await ref.read(feedRepositoryProvider).publish(widget.detail.summary);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đăng hoạt động lên feed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể đăng lên feed: $error')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _removeFromFeed() async {
    setState(() => _publishing = true);
    try {
      await ref.read(feedRepositoryProvider).remove(widget.detail.summary);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gỡ hoạt động khỏi feed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể gỡ khỏi feed: $error')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }
}
