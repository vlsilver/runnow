import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:myrun/src/widgets/route_map.dart';
import 'package:myrun/src/widgets/storage_image.dart';
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
                      if (widget.ownerUid == null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _ApplyToContractCard(activity: item.summary),
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

class _StoragePhoto extends StatelessWidget {
  const _StoragePhoto({
    required this.path,
    this.fit = BoxFit.cover,
    this.interactive = false,
  });

  final String path;
  final BoxFit fit;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final image = StorageImage(path: path, fit: fit);
    if (!interactive) return image;
    return InteractiveViewer(minScale: 1, maxScale: 4, child: image);
  }
}

/// Card "Áp dụng vào kèo" — cho phép gán buổi chạy này vào 1 kèo đang active
/// ngay từ màn chi tiết, thay vì chỉ có chiều ngược lại (từ màn kèo chọn
/// hoạt động). Chỉ hiện cho hoạt động của chính mình.
class _ApplyToContractCard extends ConsumerStatefulWidget {
  const _ApplyToContractCard({required this.activity});

  final ActivitySummary activity;

  @override
  ConsumerState<_ApplyToContractCard> createState() =>
      _ApplyToContractCardState();
}

typedef _ApplyCardData = ({
  List<ContractApplyOption> options,
  String? assignedContractId,
});

class _ApplyToContractCardState extends ConsumerState<_ApplyToContractCard> {
  Future<_ApplyCardData>? _future;
  List<RunContract>? _loadedFor;
  bool _saving = false;
  String? _error;

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
    final assignedFuture = controller.currentContractIdFor(
      widget.activity.id,
    );
    return (options: await optionsFuture, assignedContractId: await assignedFuture);
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPicker(
    List<ContractApplyOption> options,
    RunContract? current,
  ) {
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
            isRunNowActivityDistanceEligible(activity));
    if (!basicEligible) return const SizedBox.shrink();

    final contractsState = ref.watch(myActiveContractsProvider);
    return contractsState.when(
      data: (contracts) {
        if (contracts.isEmpty) return const _ApplyToContractEmptyCard();
        _ensureLoaded(contracts);
        return FutureBuilder<_ApplyCardData>(
          future: _future,
          builder: (context, snapshot) {
            if (_saving || !snapshot.hasData) {
              return _ApplyToContractStatusCard(
                message: _saving ? 'Đang áp dụng...' : 'Đang tải kèo...',
              );
            }
            final data = snapshot.data!;
            RunContract? appliedContract;
            for (final contract in contracts) {
              if (contract.id == data.assignedContractId) {
                appliedContract = contract;
                break;
              }
            }
            if (appliedContract != null) {
              return _ApplyToContractAppliedChip(
                contractTitle: appliedContract.title,
                error: _error,
                onTap: () => _openPicker(data.options, appliedContract),
              );
            }
            final eligibleOptions = data.options
                .where((option) => option.eligible)
                .toList();
            final singleDirectContract =
                contracts.length == 1 && eligibleOptions.length == 1
                ? eligibleOptions.single.contract
                : null;
            return _ApplyToContractPromptCard(
              contractTitle: singleDirectContract?.title,
              error: _error,
              onPressed: singleDirectContract != null
                  ? () => _apply(singleDirectContract)
                  : () => _openPicker(data.options, null),
            );
          },
        );
      },
      error: (error, stack) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }
}

class _ApplyToContractEmptyCard extends StatelessWidget {
  const _ApplyToContractEmptyCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Chưa có kèo đang chạy. Tạo hoặc tham gia kèo để áp dụng '
              'buổi chạy này.',
              style: TextStyle(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyToContractStatusCard extends StatelessWidget {
  const _ApplyToContractStatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(color: context.runNowPalette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ApplyToContractPromptCard extends StatelessWidget {
  const _ApplyToContractPromptCard({
    required this.contractTitle,
    required this.error,
    required this.onPressed,
  });

  final String? contractTitle;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.flag_rounded,
                  size: 19,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Áp dụng vào kèo',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contractTitle ?? 'Chọn kèo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onPressed,
                child: Text(error != null ? 'Thử lại' : 'Áp dụng'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            _ApplyErrorBanner(message: error!),
          ],
        ],
      ),
    );
  }
}

class _ApplyToContractAppliedChip extends StatelessWidget {
  const _ApplyToContractAppliedChip({
    required this.contractTitle,
    required this.error,
    required this.onTap,
  });

  final String contractTitle;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          borderRadius: 999,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: RunNowSemanticColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Đang áp dụng cho '),
                          TextSpan(
                            text: contractTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          _ApplyErrorBanner(message: error!),
        ],
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
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
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
