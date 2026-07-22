import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/live_route_view.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

class RunContractDetailScreen extends ConsumerStatefulWidget {
  const RunContractDetailScreen({required this.contractId, super.key});
  final String contractId;

  @override
  ConsumerState<RunContractDetailScreen> createState() =>
      _RunContractDetailScreenState();
}

class _RunContractDetailScreenState
    extends ConsumerState<RunContractDetailScreen> {
  bool _working = false;
  bool _viewLogged = false;
  bool _recalculated = false;
  bool _showRouteMap = false;
  bool _showActivityFeed = false;
  bool _showPhotoAlbum = false;

  @override
  Widget build(BuildContext context) {
    final contractState = ref.watch(runContractProvider(widget.contractId));
    final contract = contractState.value;
    final lifecycle = contract == null
        ? null
        : contractLifecycle(contract, DateTime.now());
    final syncing = ref.watch(syncControllerProvider).syncing;
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final participant = contract?.participantFor(uid);
    final canDelete =
        contract != null &&
        uid != null &&
        uid == contract.creatorUid &&
        contract.participantCount == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết kèo'),
        actions: [
          if (canDelete)
            IconButton(
              onPressed: _working ? null : () => _confirmDelete(contract),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Xóa kèo',
            ),
        ],
      ),
      floatingActionButton: _floatingAction(
        contract: contract,
        lifecycle: lifecycle,
        participant: participant,
        uid: uid,
        syncing: syncing,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: contractState.when(
            data: (contract) => contract == null
                ? const Center(child: Text('Không tìm thấy kèo chạy.'))
                : _loggedContent(contract),
            error: (error, stack) => Center(child: Text('$error')),
            loading: () => const RunNowLoading(label: 'Đang tải kèo'),
          ),
        ),
      ),
    );
  }

  /// Hành động nổi bật kiểu "pin" ở đáy màn hình — ưu tiên nhắc sync khi kèo
  /// đang chờ đồng bộ cuối; ngoài ra, nếu kèo đang active và user chưa hoàn
  /// thành, ưu tiên tiếp theo là chọn/đổi buổi chạy áp dụng (trước đây chỉ là
  /// 1 nút viền mảnh nằm giữa nội dung cuộn, dễ bị bỏ qua).
  Widget? _floatingAction({
    required RunContract? contract,
    required RunContractLifecycle? lifecycle,
    required RunContractParticipant? participant,
    required String? uid,
    required bool syncing,
  }) {
    if (lifecycle == RunContractLifecycle.syncGrace) {
      return _PinnedSyncButton(
        syncing: syncing,
        onPressed: () =>
            ref.read(syncControllerProvider).startBackgroundSync(force: true),
      );
    }
    if (contract == null || participant == null) return null;
    if (!contract.isActive || contract.completedBy(uid)) return null;
    // Kèo theo tuyến: thay hẳn nút "chọn buổi chạy áp dụng" (chọn 1 hoạt
    // động đã có sẵn) bằng nút LIVE — chạy trực tiếp cho kèo là luồng chính
    // của loại kèo này, không cần cả 2 nút cùng lúc gây rối. Ẩn hẳn nếu
    // ngoài kỳ chạy (`running`) hoặc đã hoàn thành mục tiêu (check ở trên).
    if (contract.route != null) {
      // Web không có tab "Chạy"/tracking (không GPS liên tục) nên cũng ẩn
      // luôn nút bắt đầu live ở đây — web chỉ xem live (qua "Xem live" trên
      // bản đồ), không tự chạy live được.
      if (kIsWeb) return null;
      final available = lifecycle == RunContractLifecycle.running;
      final label = switch (lifecycle) {
        null => 'CHƯA SẴN SÀNG',
        RunContractLifecycle.scheduled =>
          'CHẠY TỪ ${DateFormat('dd/MM · HH:mm').format(contract.startAt)}',
        RunContractLifecycle.running => 'LIVE NOW',
        RunContractLifecycle.syncGrace ||
        RunContractLifecycle.awaitingFinalize ||
        RunContractLifecycle.completed ||
        RunContractLifecycle.failed => 'ĐÃ HẾT GIỜ CHẠY',
        RunContractLifecycle.cancelled => 'KÈO ĐÃ HỦY',
      };
      return _GoLiveButton(
        enabled: available,
        label: label,
        onPressed: () => context.push('/tracking/live', extra: contract.id),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => _selectActivities(contract, participant),
      icon: const Icon(Icons.playlist_add_check_rounded),
      label: Text(
        participant.countedActivityIds.isEmpty
            ? 'Chọn buổi chạy áp dụng'
            : 'Đổi buổi chạy áp dụng',
      ),
    );
  }

  Widget _loggedContent(RunContract contract) {
    final currentUid = ref.read(firebaseUserProvider).value?.uid;
    final participant = contract.participantFor(currentUid);
    if (!_recalculated &&
        _shouldAutoRecalculate(contract, participant, currentUid)) {
      _recalculated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final controller = ref.read(runContractControllerProvider);
          if (currentUid == contract.creatorUid) {
            controller.recalculate(contract).ignore();
          } else {
            controller.recalculateParticipant(contract).ignore();
          }
        }
      });
    }
    if (!_viewLogged) {
      _viewLogged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(runContractAnalyticsProvider)
              .log('contract_detail_viewed', contract: contract)
              .ignore();
          if (!contract.isActive) {
            ref
                .read(runContractAnalyticsProvider)
                .log('contract_recap_viewed', contract: contract)
                .ignore();
          }
        }
      });
    }
    return _content(contract);
  }

  bool _shouldAutoRecalculate(
    RunContract contract,
    RunContractParticipant? participant,
    String? currentUid,
  ) {
    if (!contract.isActive ||
        participant == null ||
        contract.completedBy(currentUid)) {
      return false;
    }
    final lastCalculatedAt = contract.lastCalculatedAt;
    if (lastCalculatedAt == null) return true;
    return DateTime.now().difference(lastCalculatedAt) >
        const Duration(minutes: 2);
  }

  Widget _content(RunContract contract) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final owner = uid == contract.creatorUid;
    var ownerName = '3i member';
    String? ownerAvatarUrl;
    final currentProfile = ref.watch(userProfileProvider).value;
    if (owner) {
      ownerName = currentProfile?.displayName ?? 'Bạn';
      ownerAvatarUrl = currentProfile?.avatarUrl;
    } else {
      for (final member in ref.watch(membersProvider).value ?? const []) {
        if (member.uid == contract.creatorUid) {
          ownerName = member.displayName;
          ownerAvatarUrl = member.avatarUrl;
          break;
        }
      }
    }
    final lifecycle = contractLifecycle(contract, DateTime.now());
    final participant = contract.participantFor(uid);
    final profiles = {
      for (final member
          in ref.watch(membersProvider).value ?? const <MemberProfile>[])
        member.uid: member,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
      children: [
        _ContractDetailHeader(
          contract: contract,
          ownerName: ownerName,
          ownerAvatarUrl: ownerAvatarUrl,
        ),
        if (contract.route != null) ...[
          const SizedBox(height: 16),
          _LazyRouteMapSection(
            contract: contract,
            expanded: _showRouteMap,
            onToggle: () => setState(() => _showRouteMap = !_showRouteMap),
          ),
        ],
        if (participant != null) ...[
          const SizedBox(height: 12),
          _MyProgressCard(contract: contract, participant: participant),
        ],
        const SizedBox(height: 12),
        _ParticipantProgressList(
          contract: contract,
          profiles: profiles,
          currentUid: uid,
          currentProfile: currentProfile,
        ),
        const SizedBox(height: 12),
        _LazyContractSection(
          title: 'Ảnh trong kèo',
          subtitle: 'Album chỉ tải khi bạn mở mục này.',
          icon: Icons.photo_library_outlined,
          expanded: _showPhotoAlbum,
          onToggle: () => setState(() => _showPhotoAlbum = !_showPhotoAlbum),
          child: _ContractPhotoAlbumLoader(contractId: contract.id),
        ),
        const SizedBox(height: 12),
        _LazyContractSection(
          title: 'Buổi chạy đã ghi nhận',
          subtitle: 'Mở khi cần xem các buổi đã áp dụng vào kèo.',
          icon: Icons.format_list_bulleted_rounded,
          expanded: _showActivityFeed,
          onToggle: () =>
              setState(() => _showActivityFeed = !_showActivityFeed),
          child: _ContractActivityFeedSection(contractId: contract.id),
        ),
        const SizedBox(height: 18),
        if (owner &&
            contract.isActive &&
            lifecycle == RunContractLifecycle.awaitingFinalize)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _primaryAction(contract, lifecycle),
          )
        else if (owner &&
            contract.isActive &&
            (lifecycle == RunContractLifecycle.syncGrace ||
                lifecycle == RunContractLifecycle.scheduled))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _primaryAction(contract, lifecycle),
          ),
        if (owner && !contract.isActive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: () => context.push(
                '/contracts/new',
                extra: ref
                    .read(runContractControllerProvider)
                    .recontractDraft(contract),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: Text(
                contract.status == RunContractStatus.completed
                    ? 'Tái kèo'
                    : 'Phục thù',
              ),
            ),
          ),
        if (!owner && contract.isActive && participant == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: _working ? null : () => _join(contract),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Tham gia kèo'),
            ),
          ),
      ],
    );
  }

  Widget _primaryAction(RunContract contract, RunContractLifecycle lifecycle) =>
      switch (lifecycle) {
        RunContractLifecycle.awaitingFinalize => FilledButton.icon(
          onPressed: _working ? null : () => _finalize(contract),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Chốt kết quả'),
        ),
        RunContractLifecycle.syncGrace => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Đang chờ đồng bộ cuối. Bạn có thể chốt kết quả từ 06:00.',
            ),
          ),
        ),
        RunContractLifecycle.scheduled => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Kèo đã chốt và sẽ tự bắt đầu đúng giờ.'),
          ),
        ),
        _ => const SizedBox.shrink(),
      };

  Future<void> _finalize(RunContract contract) async {
    setState(() => _working = true);
    try {
      final analytics = ref.read(runContractAnalyticsProvider);
      analytics.log('contract_finalize_triggered', contract: contract).ignore();
      final status = await ref
          .read(runContractControllerProvider)
          .finalize(contract);
      analytics
          .log(
            status == RunContractStatus.completed
                ? 'contract_completed'
                : 'contract_failed',
            contract: contract,
          )
          .ignore();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _join(RunContract contract) async {
    setState(() => _working = true);
    try {
      await ref.read(runContractControllerProvider).join(contract);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _selectActivities(
    RunContract contract,
    RunContractParticipant participant,
  ) async {
    final palette = context.runNowPalette;
    final contractTitles = <String, String>{};
    for (final item
        in ref.read(myActiveContractsProvider).value ?? const <RunContract>[]) {
      contractTitles[item.id] = item.title;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: palette.glassStart,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ActivityAssignmentSheet(
        contract: contract,
        initialActivityIds: participant.countedActivityIds.toSet(),
        contractTitles: contractTitles,
        controller: ref.read(runContractControllerProvider),
      ),
    );
  }

  Future<void> _confirmDelete(RunContract contract) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa kèo này?'),
        content: Text(
          'Kèo "${contract.title}" sẽ bị xóa vĩnh viễn và không thể khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa kèo'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteContract(contract);
  }

  Future<void> _deleteContract(RunContract contract) async {
    setState(() => _working = true);
    try {
      await ref.read(runContractControllerProvider).deleteContract(contract);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// Nút sync nổi bật kiểu "neo" (FAB) — hiện khi kèo đang chờ đồng bộ cuối
/// (`RunContractLifecycle.syncGrace`), lúc người dùng cần chủ động sync nhất
/// nhưng trước đây chỉ có dòng chữ tĩnh, không có cách nào bấm ngay tại đây.
class _PinnedSyncButton extends StatefulWidget {
  const _PinnedSyncButton({required this.syncing, required this.onPressed});

  final bool syncing;
  final VoidCallback onPressed;

  @override
  State<_PinnedSyncButton> createState() => _PinnedSyncButtonState();
}

class _PinnedSyncButtonState extends State<_PinnedSyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _PinnedSyncButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncing != widget.syncing) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.syncing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.syncing
        ? RotationTransition(turns: _controller, child: const Icon(Icons.sync))
        : const Icon(Icons.sync_rounded);
    return FloatingActionButton.extended(
      onPressed: widget.syncing ? null : widget.onPressed,
      icon: icon,
      label: Text(widget.syncing ? 'Đang đồng bộ...' : 'Đồng bộ ngay'),
    );
  }
}

class _ActivityAssignmentSheet extends StatefulWidget {
  const _ActivityAssignmentSheet({
    required this.contract,
    required this.initialActivityIds,
    required this.contractTitles,
    required this.controller,
  });

  final RunContract contract;
  final Set<String> initialActivityIds;
  final Map<String, String> contractTitles;
  final RunContractController controller;

  @override
  State<_ActivityAssignmentSheet> createState() =>
      _ActivityAssignmentSheetState();
}

class _ActivityAssignmentSheetState extends State<_ActivityAssignmentSheet> {
  late final Future<List<RunContractActivityOption>> _options;
  late final Set<String> _selectedIds;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialIds = widget.initialActivityIds.toList()..sort();
    _selectedIds = widget.contract.metric == RunContractMetric.longestRun
        ? initialIds.take(1).toSet()
        : initialIds.toSet();
    _options = widget.controller.activityOptions(widget.contract, limit: 80);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final singleSessionMode =
        widget.contract.metric == RunContractMetric.longestRun;
    return Material(
      color: palette.glassStart,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Chọn buổi chạy',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                singleSessionMode
                    ? 'Kèo chạy dài chỉ nhận 1 session liên tục. Không cộng dồn nhiều buổi.'
                    : 'Chỉ session bạn xác nhận mới được cộng vào kèo này.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<RunContractActivityOption>>(
                  future: _options,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const RunNowLoading(label: 'Đang tìm buổi chạy');
                    }
                    final options = snapshot.data!;
                    if (options.isEmpty) {
                      final threshold = switch (widget.contract.metric) {
                        RunContractMetric.activityCount ||
                        RunContractMetric.activeDays =>
                          'Kèo theo buổi/ngày chỉ nhận session chạy trên 1 km.',
                        _ =>
                          'Session 3I cần đạt ít nhất 500 m và nằm trong kỳ kèo.',
                      };
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(threshold, textAlign: TextAlign.center),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final activity = option.activity;
                        final assignedElsewhere =
                            option.assignedContractId != null &&
                            option.assignedContractId != widget.contract.id;
                        if (assignedElsewhere) {
                          final assignedTitle =
                              widget.contractTitles[option
                                  .assignedContractId] ??
                              'kèo khác';
                          return _AssignedActivityTile(
                            activity: activity,
                            assignedTitle: assignedTitle,
                          );
                        }
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selectedIds.contains(activity.id),
                          onChanged: (selected) {
                            setState(() {
                              if (selected ?? false) {
                                if (singleSessionMode) _selectedIds.clear();
                                _selectedIds.add(activity.id);
                              } else {
                                _selectedIds.remove(activity.id);
                              }
                            });
                          },
                          title: Text(
                            activity.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy, HH:mm').format(activity.startedAt)}'
                            ' · ${(activity.distanceMeters / 1000).toStringAsFixed(2)} km',
                          ),
                          secondary: const Icon(Icons.directions_run_rounded),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          singleSessionMode
                              ? (_selectedIds.isEmpty
                                    ? 'Chọn 1 buổi chạy'
                                    : 'Áp dụng buổi chạy này')
                              : 'Áp dụng ${_selectedIds.length} buổi chạy',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.replaceActivityAssignments(
        widget.contract,
        _selectedIds,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AssignedActivityTile extends StatelessWidget {
  const _AssignedActivityTile({
    required this.activity,
    required this.assignedTitle,
  });

  final ActivitySummary activity;
  final String assignedTitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.accent.withValues(alpha: 0.07),
          palette.glassStart,
        ),
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('dd/MM/yyyy, HH:mm').format(activity.startedAt)}'
                  ' · ${(activity.distanceMeters / 1000).toStringAsFixed(2)} km',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 3),
                Text(
                  'Đã áp dụng cho: $assignedTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'ĐÃ GÁN',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractDetailHeader extends StatelessWidget {
  const _ContractDetailHeader({
    required this.contract,
    required this.ownerName,
    required this.ownerAvatarUrl,
  });

  final RunContract contract;
  final String ownerName;
  final String? ownerAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final completed = contract.overallProgressPercent >= 100;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      gradient: LinearGradient(
        colors: [palette.tint, palette.glassStart],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage:
                    ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
                    ? null
                    : cachedAvatarImage(context, ownerAvatarUrl!, 44),
                child: ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
                    ? Text(ownerName.isEmpty ? '?' : ownerName[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'KÈO NHÓM',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    completed ? 'ĐÃ CỨU' : 'ĐANG CHẠY',
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            contract.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Deadline ${DateFormat('dd/MM · HH:mm').format(contract.endAtExclusive.subtract(const Duration(seconds: 1)))}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyProgressCard extends StatelessWidget {
  const _MyProgressCard({required this.contract, required this.participant});

  final RunContract contract;
  final RunContractParticipant participant;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final rawRatio = contract.targetValue <= 0
        ? 0.0
        : participant.progressValue / contract.targetValue;
    final remaining = (contract.targetValue - participant.progressValue).clamp(
      0.0,
      contract.targetValue,
    );
    final completed = rawRatio >= 1;
    final foreground =
        ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      gradient: LinearGradient(
        colors: [palette.accent, palette.accentDeep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'CỦA BẠN',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _contractValue(contract.metric, participant.progressValue),
                style: TextStyle(
                  color: foreground,
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '/${_contractValue(contract.metric, contract.targetValue)}',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (completed)
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: foreground,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Hoàn thành',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Còn ${_contractValue(contract.metric, remaining)}',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: rawRatio.clamp(0.0, 1.0),
            minHeight: 9,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: foreground.withValues(alpha: 0.2),
            color: foreground,
          ),
        ],
      ),
    );
  }
}

class _LazyContractSection extends StatelessWidget {
  const _LazyContractSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Ink(
                decoration: BoxDecoration(
                  color: palette.glassStart,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: palette.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: palette.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[const SizedBox(height: 10), child],
        ],
      ),
    );
  }
}

class _LazyRouteMapSection extends ConsumerWidget {
  const _LazyRouteMapSection({
    required this.contract,
    required this.expanded,
    required this.onToggle,
  });

  final RunContract contract;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = contract.route;
    if (route == null) return const SizedBox.shrink();
    final distanceKm = (route.distanceMeters / 1000).toStringAsFixed(1);
    if (!expanded) {
      return _LazyContractSection(
        title: 'Tuyến tham khảo',
        subtitle: '$distanceKm km · bấm để mở bản đồ/live',
        icon: Icons.route_rounded,
        expanded: false,
        onToggle: onToggle,
        child: const SizedBox.shrink(),
      );
    }

    final feedItems =
        ref.watch(runContractActivityFeedProvider(contract.id)).value ??
        const <ContractActivityFeedItem>[];
    final feedPhotos = feedItems
        .expand((item) => item.activity.photos)
        .toList();
    final currentUid = ref.watch(firebaseUserProvider).value?.uid;
    final currentProfile = ref.watch(userProfileProvider).value;
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final profiles = {for (final member in members) member.uid: member};

    (String, String?) resolveMember(String memberUid) {
      if (memberUid == currentUid) {
        return (
          currentProfile?.displayName ?? 'Bạn',
          currentProfile?.avatarUrl,
        );
      }
      final member = profiles[memberUid];
      return (member?.displayName ?? '3i member', member?.avatarUrl);
    }

    final claimedPhotos = [
      for (final item in feedItems)
        for (final photo in item.activity.photos)
          LiveRoutePhoto(
            photo: photo,
            ownerUid: item.uid,
            ownerName: resolveMember(item.uid).$1,
            ownerAvatarUrl: resolveMember(item.uid).$2,
          ),
    ];

    return _LazyContractSection(
      title: 'Tuyến tham khảo',
      subtitle: '$distanceKm km · đang hiển thị bản đồ',
      icon: Icons.route_rounded,
      expanded: true,
      onToggle: onToggle,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: RouteMap.fromRoutePoints(
            points: [
              for (final point in route.points)
                RoutePoint(
                  latitude: point.latitude,
                  longitude: point.longitude,
                  timestamp: contract.createdAt,
                ),
            ],
            photos: feedPhotos,
            onPhotoTap: (photo) => showActivityPhotoViewer(context, photo),
            liveRunnersStream: ref
                .read(liveTrackingRepositoryProvider)
                .watchContractLiveSessions(contract.id),
            liveRoutePhotos: claimedPhotos,
            height: 220,
          ),
        ),
      ),
    );
  }
}

/// Danh sách buổi chạy đã được ghi nhận (đếm vào tiến độ) của TẤT CẢ người
/// tham gia kèo — không chỉ của user hiện tại — mỗi buổi hiện rõ của ai,
/// giống style nhật ký Club nhưng chỉ gồm đúng các buổi thuộc kèo này.
class _ContractActivityFeedSection extends ConsumerWidget {
  const _ContractActivityFeedSection({required this.contractId});

  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(runContractActivityFeedProvider(contractId));
    return feed.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final currentUid = ref.watch(firebaseUserProvider).value?.uid;
        final currentProfile = ref.watch(userProfileProvider).value;
        final members =
            ref.watch(membersProvider).value ?? const <MemberProfile>[];
        final profiles = {for (final member in members) member.uid: member};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < items.length; index++)
              ActivityTile(
                activity: items[index].activity,
                sequence: index + 1,
                ownerUid: items[index].uid == currentUid
                    ? null
                    : items[index].uid,
                memberName: items[index].uid == currentUid
                    ? (currentProfile?.displayName ?? 'Bạn')
                    : (profiles[items[index].uid]?.displayName ?? '3i member'),
                memberAvatarUrl: items[index].uid == currentUid
                    ? currentProfile?.avatarUrl
                    : profiles[items[index].uid]?.avatarUrl,
              ),
          ],
        );
      },
      error: (error, stack) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }
}

class _ContractPhotoAlbumLoader extends ConsumerWidget {
  const _ContractPhotoAlbumLoader({required this.contractId});

  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(runContractActivityFeedProvider(contractId));
    return feed.when(
      data: (items) {
        final photos = {
          for (final item in items)
            for (final photo in item.activity.photos) photo.id: photo,
        }.values.toList();
        if (photos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Chưa có ảnh nào trong kèo này.',
              style: TextStyle(color: context.runNowPalette.textMuted),
            ),
          );
        }
        return _ContractPhotoAlbum(photos: photos);
      },
      error: (error, stack) => Text('$error'),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: RunNowLoading(
          label: 'Đang tải ảnh',
          compact: true,
          revealDelay: Duration(milliseconds: 140),
        ),
      ),
    );
  }
}

/// Nút "phát live" nổi bật, dùng làm `floatingActionButton` cho kèo theo
/// tuyến (thay hẳn nút "chọn buổi chạy áp dụng" — xem [_floatingAction]) —
/// nền gradient đỏ ([RunNowSemanticColors.danger], màu LIVE phổ quát của
/// recording/broadcast) + quầng sáng và chấm nhấp nháy. Cố tình KHÁC màu
/// với marker vị trí live trên [RouteMap] (dùng info/teal) vì marker đó
/// nằm chung bản đồ với marker kết thúc (cũng màu danger) — trùng màu ở
/// đó sẽ gây nhầm lẫn hai điểm.
class _GoLiveButton extends StatefulWidget {
  const _GoLiveButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_GoLiveButton> createState() => _GoLiveButtonState();
}

class _GoLiveButtonState extends State<_GoLiveButton>
    with SingleTickerProviderStateMixin {
  late final _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const danger = RunNowSemanticColors.danger;
    final palette = context.runNowPalette;
    final activeColor = widget.enabled ? danger : palette.textMuted;
    // Bọc RepaintBoundary — pulse chạy vô thời hạn (`repeat(reverse: true)`)
    // suốt lúc nút này còn hiện, cô lập vùng repaint để không kéo theo phần
    // còn lại của màn hình vẽ lại mỗi frame.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final glowAlpha = widget.enabled
              ? 0.28 + _pulseController.value * 0.32
              : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withValues(alpha: glowAlpha),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? widget.onPressed : null,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.enabled
                      ? [danger, Color.lerp(danger, Colors.black, 0.35)!]
                      : [palette.tint, palette.glassStart],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: Tween<double>(
                        begin: 0.35,
                        end: 1,
                      ).animate(_pulseController),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.enabled ? Colors.white : activeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.enabled ? Colors.white : activeColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Album ảnh chụp trong các buổi chạy đã ghi nhận của kèo — gộp từ mọi
/// người tham gia (đã lọc quyền xem qua [runContractActivityFeedProvider]).
class _ContractPhotoAlbum extends StatelessWidget {
  const _ContractPhotoAlbum({required this.photos});

  final List<ActivityPhoto> photos;

  @override
  Widget build(BuildContext context) {
    final sorted = [...photos]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sorted.length} ảnh từ buổi chạy',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sorted.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final photo = sorted[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => showActivityPhotoViewer(context, photo),
                child: StoragePhoto(
                  path: photo.storagePath,
                  cacheWidth: 240,
                  cacheHeight: 240,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ParticipantProgressList extends StatelessWidget {
  const _ParticipantProgressList({
    required this.contract,
    required this.profiles,
    required this.currentUid,
    required this.currentProfile,
  });

  final RunContract contract;
  final Map<String, MemberProfile> profiles;
  final String? currentUid;
  final UserProfile? currentProfile;

  @override
  Widget build(BuildContext context) {
    final participants = contract.participants.values.toList()
      ..sort((a, b) => b.progressValue.compareTo(a.progressValue));
    final completedCount = participants
        .where(
          (participant) => participant.progressValue >= contract.targetValue,
        )
        .length;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 19,
                color: context.runNowPalette.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${participants.length} NGƯỜI THAM GIA',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                '$completedCount/${participants.length} đã hoàn thành',
                style: TextStyle(
                  color: context.runNowPalette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < participants.length; index++) ...[
            _ParticipantRow(
              contract: contract,
              participant: participants[index],
              name: participants[index].uid == currentUid
                  ? currentProfile?.displayName ?? 'Bạn'
                  : profiles[participants[index].uid]?.displayName ??
                        '3i member',
              avatarUrl: participants[index].uid == currentUid
                  ? currentProfile?.avatarUrl
                  : profiles[participants[index].uid]?.avatarUrl,
              isCurrentUser: participants[index].uid == currentUid,
            ),
            if (index != participants.length - 1) const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.contract,
    required this.participant,
    required this.name,
    required this.avatarUrl,
    required this.isCurrentUser,
  });

  final RunContract contract;
  final RunContractParticipant participant;
  final String name;
  final String? avatarUrl;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final completed = participant.progressValue >= contract.targetValue;
    final ratio = contract.targetValue <= 0
        ? 0.0
        : (participant.progressValue / contract.targetValue).clamp(0.0, 1.0);
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: avatarUrl == null || avatarUrl!.isEmpty
              ? null
              : cachedAvatarImage(context, avatarUrl!, 40),
          child: avatarUrl == null || avatarUrl!.isEmpty
              ? Text(name.isEmpty ? '?' : name[0].toUpperCase())
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      isCurrentUser ? '$name · Bạn' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.check_circle,
                      color: RunNowSemanticColors.success,
                      size: 17,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: palette.border,
                color: completed
                    ? RunNowSemanticColors.success
                    : palette.accent,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _contractValue(contract.metric, participant.progressValue),
              style: TextStyle(
                color: completed ? RunNowSemanticColors.success : null,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              completed ? 'Xong' : '${(ratio * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: completed
                    ? RunNowSemanticColors.success
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _contractValue(RunContractMetric metric, double value) =>
    switch (metric) {
      RunContractMetric.distance || RunContractMetric.longestRun =>
        '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} km',
      RunContractMetric.activityCount => '${value.toInt()} buổi',
      RunContractMetric.activeDays => '${value.toInt()} ngày',
      RunContractMetric.routeCompletion => '${value.toInt()} lần',
    };
