import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_recap_card.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/strava_activity_link.dart';
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
                // Chỉ hiện bản đồ khi buổi CÓ route. Buổi Apple Health chỉ có
                // km + thời gian (không GPS) → bỏ map thay vì vẽ bản đồ trống.
                if ((item.summary.polyline?.isNotEmpty ?? false) ||
                    item.summary.routePoints.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ActivityRouteHeaderDelegate(
                      detail: item,
                      selectedDistanceMeters: _selectedDistanceMeters,
                      onPhotoTap: _openPhoto,
                      showSyncBadge: widget.ownerUid == null,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brand guideline của Strava: nơi hiện dữ liệu Strava
                      // phải có đường dẫn ngược về hoạt động gốc. Đặt ngay
                      // dưới bản đồ, canh trái.
                      if (item.summary.source == ActivitySource.strava)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: StravaActivityLink(
                              activityId:
                                  item.summary.sourceActivityId ??
                                  item.summary.id,
                            ),
                          ),
                        ),
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
            loading: () => const RunNowLoading(label: 'Đang tải hoạt động'),
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

  Future<void> _openPhoto(ActivityPhoto photo) =>
      showActivityPhotoViewer(context, photo);
}

class _ActivityRouteHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ActivityRouteHeaderDelegate({
    required this.detail,
    required this.selectedDistanceMeters,
    required this.onPhotoTap,
    required this.showSyncBadge,
  });

  final ActivityDetail detail;
  final ValueListenable<double?> selectedDistanceMeters;
  final ValueChanged<ActivityPhoto> onPhotoTap;
  final bool showSyncBadge;

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
        builder: (context, selectedDistance, _) => _ActivityMapArea(
          map: RouteMap(
            encodedPolyline: detail.summary.polyline,
            routePoints: detail.summary.routePoints,
            photos: detail.photos,
            onPhotoTap: onPhotoTap,
            highlightedDistanceMeters: selectedDistance,
            totalDistanceMeters: detail.summary.distanceMeters,
            height: height,
          ),
          activity: showSyncBadge ? detail.summary : null,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ActivityRouteHeaderDelegate oldDelegate) {
    return oldDelegate.detail != detail ||
        oldDelegate.selectedDistanceMeters != selectedDistanceMeters ||
        oldDelegate.showSyncBadge != showSyncBadge;
  }
}

/// Bọc [map] và (nếu có [activity]) icon đồng bộ kèo ở góc trên-phải bản đồ,
/// theo `features/design_handoff_sync_icon/` — thay cho card ở cuối trang
/// trước đây. Quản lý trạng thái mở/đóng popup + lớp phủ mờ để bấm ra ngoài
/// bản đồ (không phải ra ngoài toàn màn hình) là đóng popup.
/// Bọc [map] và (nếu có [activity]) icon đồng bộ kèo ở góc dưới-phải bản đồ.
/// Popup của icon tự lo phần overlay/dismiss qua [OverlayPortal] (xem
/// `_MapSyncBadge`) — widget này chỉ còn việc xếp layout, không giữ state
/// mở/đóng popup nữa (từng đặt ở đây nhưng gây lỗi bấm không ăn: popup dùng
/// `Positioned`+`Clip.none` bên trong `SliverPersistentHeader` bị viewport
/// của `CustomScrollView` cắt vùng nhận cảm ứng khi header co lại lúc cuộn).
class _ActivityMapArea extends StatelessWidget {
  const _ActivityMapArea({required this.map, required this.activity});

  final Widget map;
  final ActivitySummary? activity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: map),
        if (activity != null)
          Positioned(
            bottom: 14,
            right: 14,
            child: _MapSyncBadge(activity: activity!),
          ),
      ],
    );
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
                      StoragePhoto(
                        path: photo.storagePath,
                        cacheWidth: 296,
                        cacheHeight: 224,
                      ),
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

/// Card "Áp dụng vào kèo" — cho phép gán buổi chạy này vào 1 kèo đang active
/// ngay từ màn chi tiết, thay vì chỉ có chiều ngược lại (từ màn kèo chọn
/// hoạt động). Chỉ hiện cho hoạt động của chính mình.
typedef _ApplyCardData = ({
  List<ContractApplyOption> options,
  String? assignedContractId,
});

/// Icon đồng bộ kèo cố định ở góc bản đồ — thay cho card cuối trang trước
/// đây. `open`/`onToggle`/`onRequestClose` do [_ActivityMapArea] điều khiển
/// để lớp phủ mờ (dim) trên toàn bản đồ và icon dùng chung 1 trạng thái.
class _MapSyncBadge extends ConsumerStatefulWidget {
  const _MapSyncBadge({required this.activity});

  final ActivitySummary activity;

  @override
  ConsumerState<_MapSyncBadge> createState() => _MapSyncBadgeState();
}

class _MapSyncBadgeState extends ConsumerState<_MapSyncBadge> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  Future<_ApplyCardData>? _future;
  List<RunContract>? _loadedFor;
  bool _saving = false;
  String? _error;

  void _togglePopup() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
    }
  }

  void _closePopup() {
    if (_overlayController.isShowing) _overlayController.hide();
  }

  bool _sameContracts(List<RunContract> a, List<RunContract> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _ensureLoaded(List<RunContract> contracts) {
    if (_loadedFor != null && _sameContracts(_loadedFor!, contracts)) return;
    _loadedFor = contracts;
    _future = _load(contracts);
  }

  Future<_ApplyCardData> _load(List<RunContract> contracts) async {
    final controller = ref.read(runContractControllerProvider);
    final optionsFuture = controller.applyOptionsFor(
      widget.activity,
      contracts,
    );
    final assignedFuture = controller.currentContractIdFor(widget.activity.id);
    return (
      options: await optionsFuture,
      assignedContractId: await assignedFuture,
    );
  }

  void _reload() {
    if (_loadedFor != null) _future = _load(_loadedFor!);
  }

  Future<void> _apply(RunContract contract) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(runContractControllerProvider)
          .applyActivityToContract(contract, widget.activity);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(RunContract contract) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(runContractControllerProvider)
          .removeActivityFromContract(contract, widget.activity);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPicker(
    List<ContractApplyOption> options,
    RunContract? current,
  ) {
    _closePopup();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ApplyToContractPickerSheet(
        activity: widget.activity,
        options: options,
        currentContract: current,
        onApply: _apply,
        onRemove: current == null ? null : _remove,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final basicEligible =
        activity.kind == ActivityKind.run &&
        activity.manual != true &&
        (activity.source == ActivitySource.strava ||
            isCountedNonStravaRun(activity));
    if (!basicEligible) return const SizedBox.shrink();

    final contractsState = ref.watch(myActiveContractsProvider);
    final contracts = contractsState.value;
    if (contracts == null || contracts.isEmpty) return const SizedBox.shrink();
    _ensureLoaded(contracts);

    return FutureBuilder<_ApplyCardData>(
      future: _future,
      builder: (context, snapshot) {
        RunContract? appliedContract;
        ContractApplyOption? appliedOption;
        final options = snapshot.data?.options ?? const <ContractApplyOption>[];
        if (snapshot.hasData) {
          for (final contract in contracts) {
            if (contract.id == snapshot.data!.assignedContractId) {
              appliedContract = contract;
              break;
            }
          }
          if (appliedContract != null) {
            for (final option in options) {
              if (option.contract.id == appliedContract.id) {
                appliedOption = option;
                break;
              }
            }
          }
        }
        final loading = !snapshot.hasData || _saving;
        final synced = appliedContract != null;
        final resolvedAppliedContract = appliedContract;

        return CompositedTransformTarget(
          link: _layerLink,
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: (context) => Stack(
              children: [
                // Bấm ra ngoài (bất kỳ đâu trên toàn màn hình, không chỉ
                // trong vùng bản đồ) để đóng popup.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closePopup,
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  targetAnchor: Alignment.topRight,
                  followerAnchor: Alignment.bottomRight,
                  offset: const Offset(0, -6),
                  child: Material(
                    color: Colors.transparent,
                    child: _SyncPopup(
                      loading: loading,
                      synced: synced,
                      error: _error,
                      activityDistanceKm: activity.distanceMeters / 1000,
                      activityDate: activity.startedAt,
                      contractTitle: resolvedAppliedContract?.title,
                      currentValue: appliedOption?.currentValue,
                      targetValue: resolvedAppliedContract?.targetValue,
                      metric: resolvedAppliedContract?.metric,
                      onApplyPressed: () =>
                          _openPicker(options, resolvedAppliedContract),
                      onViewContract: resolvedAppliedContract == null
                          ? null
                          : () {
                              _closePopup();
                              context.push(
                                '/contracts/${resolvedAppliedContract.id}',
                              );
                            },
                    ),
                  ),
                ),
              ],
            ),
            child: _SyncIconButton(synced: synced, onTap: _togglePopup),
          ),
        );
      },
    );
  }
}

class _SyncIconButton extends StatelessWidget {
  const _SyncIconButton({required this.synced, required this.onTap});

  final bool synced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              // Đã đồng bộ: nền vàng đặc để khác biệt rõ ngay từ xa, không
              // chỉ trông chờ vào chấm xanh nhỏ ở góc (từng khó nhận ra).
              color: synced
                  ? palette.tertiary
                  : Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: synced
                  ? null
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1.5,
                    ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.link_rounded,
              size: 19,
              color: synced
                  ? Colors.black
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
          if (synced)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RunNowSemanticColors.success,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Popup nổi cạnh icon (không phải bottom sheet chặn màn hình) — luôn dùng
/// tông tối cố định vì nổi đè lên bản đồ (giống quy ước `_RoutePill` ở
/// `route_map.dart`), bất kể theme sáng/tối của app.
class _SyncPopup extends StatelessWidget {
  const _SyncPopup({
    required this.loading,
    required this.synced,
    required this.error,
    required this.activityDistanceKm,
    required this.activityDate,
    required this.contractTitle,
    required this.currentValue,
    required this.targetValue,
    required this.metric,
    required this.onApplyPressed,
    required this.onViewContract,
  });

  final bool loading;
  final bool synced;
  final String? error;
  final double activityDistanceKm;
  final DateTime activityDate;
  final String? contractTitle;
  final double? currentValue;
  final double? targetValue;
  final RunContractMetric? metric;
  final VoidCallback onApplyPressed;
  final VoidCallback? onViewContract;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        // Nền tối cố định (không theo theme) vì popup nổi đè lên bản đồ,
        // giống quy ước Colors.black.withValues(...) đã dùng ở _RoutePill
        // trong route_map.dart — không dùng Color(0x...) hex thô mới.
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: loading
          ? const _SyncPopupLoading()
          : synced
          ? _buildSynced(context)
          : _buildNotSynced(context),
    );
  }

  Widget _buildNotSynced(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: palette.tertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 15,
                color: palette.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chưa đồng bộ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Buổi chạy này chưa tính vào kèo nào',
                    style: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          'Áp dụng buổi chạy ${activityDistanceKm.toStringAsFixed(1)}km này vào '
          'một kèo đang chạy để tính tiến độ.',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          _ApplyErrorBanner(message: error!),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.tertiary,
              foregroundColor: Colors.black,
            ),
            onPressed: onApplyPressed,
            child: Text(error != null ? 'Thử lại' : 'Chọn kèo để đồng bộ'),
          ),
        ),
      ],
    );
  }

  Widget _buildSynced(BuildContext context) {
    final palette = context.runNowPalette;
    final progressLabel =
        currentValue != null && targetValue != null && metric != null
        ? 'Đã ${_contractValueLabel(metric!, currentValue!)} / '
              '${_contractValueLabel(metric!, targetValue!)}'
        : null;
    final percent = currentValue != null && targetValue != null
        ? _ratioPercent(currentValue!, targetValue!)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: RunNowSemanticColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: RunNowSemanticColors.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Đã đồng bộ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Buổi chạy ${activityDistanceKm.toStringAsFixed(1)}km · '
                    '${_formatShortDate(activityDate)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          _ApplyErrorBanner(message: error!),
        ],
        const SizedBox(height: 11),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: palette.tertiary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.flag_rounded,
                size: 14,
                color: palette.tertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contractTitle ?? 'Kèo chạy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (progressLabel != null)
                    Text(
                      progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ),
            if (percent != null)
              Text(
                '$percent%',
                style: TextStyle(
                  color: palette.tertiary,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
        if (onViewContract != null) ...[
          const SizedBox(height: 11),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 11),
          GestureDetector(
            onTap: onViewContract,
            child: Center(
              child: Text(
                'Xem chi tiết kèo ›',
                style: TextStyle(
                  color: palette.tertiary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SyncPopupLoading extends StatelessWidget {
  const _SyncPopupLoading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
        SizedBox(width: 10),
        Text(
          'Đang tải kèo...',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _ApplyErrorBanner extends StatelessWidget {
  const _ApplyErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyToContractPickerSheet extends StatefulWidget {
  const _ApplyToContractPickerSheet({
    required this.activity,
    required this.options,
    required this.currentContract,
    required this.onApply,
    required this.onRemove,
  });

  final ActivitySummary activity;
  final List<ContractApplyOption> options;
  final RunContract? currentContract;
  final Future<void> Function(RunContract contract) onApply;
  final Future<void> Function(RunContract contract)? onRemove;

  @override
  State<_ApplyToContractPickerSheet> createState() =>
      _ApplyToContractPickerSheetState();
}

class _ApplyToContractPickerSheetState
    extends State<_ApplyToContractPickerSheet> {
  late String? _selectedContractId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final preferred = widget.options.where((option) => option.eligible);
    _selectedContractId =
        widget.currentContract?.id ??
        (preferred.isNotEmpty
            ? preferred.first.contract.id
            : widget.options.isNotEmpty
            ? widget.options.first.contract.id
            : null);
  }

  ContractApplyOption? get _selectedOption {
    final id = _selectedContractId;
    if (id == null) return null;
    for (final option in widget.options) {
      if (option.contract.id == id) return option;
    }
    return null;
  }

  Future<void> _submit() async {
    final selected = _selectedOption?.contract;
    if (selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onApply(selected);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeCurrent() async {
    final current = widget.currentContract;
    if (current == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onRemove!(current);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final selectedTitle = _selectedOption?.contract.title ?? 'kèo';
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'Áp dụng vào kèo nào?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${formatDistance(widget.activity.distanceMeters)} · '
              '${_formatShortDate(widget.activity.startedAt)}',
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.options.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = widget.options[index];
                  return _ContractApplyOptionTile(
                    option: option,
                    selected: option.contract.id == _selectedContractId,
                    onSelected: option.eligible
                        ? () => setState(
                            () => _selectedContractId = option.contract.id,
                          )
                        : null,
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ApplyErrorBanner(message: _error!),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.onRemove != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _removeCurrent,
                      child: const Text('Gỡ khỏi kèo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving || _selectedOption == null
                        ? null
                        : _submit,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Áp dụng vào $selectedTitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractApplyOptionTile extends StatelessWidget {
  const _ContractApplyOptionTile({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final ContractApplyOption option;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final eligible = option.eligible;
    final muted = onSurface.withValues(alpha: 0.5);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: eligible && selected
              ? palette.accent.withValues(alpha: 0.12)
              : eligible
              ? Colors.transparent
              : Color.alphaBlend(
                  palette.accent.withValues(alpha: 0.05),
                  palette.glassStart,
                ),
          border: Border.all(
            color: eligible && selected ? palette.accent : palette.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: eligible && selected
                      ? palette.accent
                      : eligible
                      ? palette.border
                      : muted,
                  width: 2,
                ),
              ),
              child: eligible && selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.contract.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: eligible ? onSurface : muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    eligible
                        ? 'Đã ${_contractValueLabel(option.contract.metric, option.currentValue)}'
                              ' / ${_contractValueLabel(option.contract.metric, option.contract.targetValue)}'
                        : option.ineligibleReason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eligible ? palette.textMuted : muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (eligible)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_ratioPercent(option.currentValue, option.contract.targetValue)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: onSurface,
                    ),
                  ),
                  if (option.previewValue != null)
                    Text(
                      '+${_contractValueLabel(option.contract.metric, option.previewValue! - option.currentValue)}'
                      '→${_ratioPercent(option.previewValue!, option.contract.targetValue)}%',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              )
            else
              Text(
                '–',
                style: TextStyle(color: muted, fontWeight: FontWeight.w800),
              ),
          ],
        ),
      ),
    );
  }
}

String _contractValueLabel(RunContractMetric metric, double value) =>
    switch (metric) {
      RunContractMetric.distance || RunContractMetric.longestRun =>
        '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} km',
      RunContractMetric.activityCount => '${value.toInt()} buổi',
      RunContractMetric.activeDays => '${value.toInt()} ngày',
      RunContractMetric.routeCompletion => '${value.toInt()} lần',
    };

int _ratioPercent(double value, double target) =>
    target <= 0 ? 0 : ((value / target) * 100).clamp(0, 999).round();

String _formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

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
