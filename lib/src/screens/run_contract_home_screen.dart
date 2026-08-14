import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_plan/coach_card.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';
import 'package:myrun/src/training_plan/training_plan_repository.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

class RunContractHomeScreen extends ConsumerStatefulWidget {
  const RunContractHomeScreen({super.key});

  @override
  ConsumerState<RunContractHomeScreen> createState() =>
      _RunContractHomeScreenState();
}

class _RunContractHomeScreenState extends ConsumerState<RunContractHomeScreen> {
  static const _pageSize = 20;

  final _joining = <String>{};
  final _pageItems = <RunContract>[];
  _ContractFilter _filter = _ContractFilter.active;
  Object? _pageCursor;
  Object? _pageError;
  StackTrace? _pageStackTrace;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadFirstPage);
  }

  AsyncValue<List<RunContract>> get _pageSource {
    if (_loadingInitial) return const AsyncLoading();
    if (_pageError != null) {
      return AsyncError(_pageError!, _pageStackTrace ?? StackTrace.empty);
    }
    return AsyncData(List.unmodifiable(_pageItems));
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    setState(() {
      _pageItems.clear();
      _pageCursor = null;
      _pageError = null;
      _pageStackTrace = null;
      _hasMore = true;
      _loadingInitial = true;
      _loadingMore = false;
    });
    await _loadPage(reset: true);
  }

  Future<void> _loadNextPage() => _loadPage(reset: false);

  Future<void> _loadPage({required bool reset}) async {
    if (!reset && (!_hasMore || _loadingInitial || _loadingMore)) return;
    if (!reset) setState(() => _loadingMore = true);
    final requestedFilter = _filter;
    try {
      final repository = ref.read(runContractRepositoryProvider);
      final page = switch (requestedFilter) {
        _ContractFilter.active => repository.fetchClubContractsPage(
          limit: _pageSize,
          cursor: reset ? null : _pageCursor,
        ),
        _ContractFilter.completed => repository.fetchMyContractHistoryPage(
          status: RunContractStatus.completed,
          limit: _pageSize,
          cursor: reset ? null : _pageCursor,
        ),
        _ContractFilter.failed => repository.fetchMyContractHistoryPage(
          status: RunContractStatus.failed,
          limit: _pageSize,
          cursor: reset ? null : _pageCursor,
        ),
      };
      final result = await page;
      if (!mounted || requestedFilter != _filter) return;
      setState(() {
        if (reset) _pageItems.clear();
        final existingIds = _pageItems.map((item) => item.id).toSet();
        _pageItems.addAll(
          result.contracts.where((item) => existingIds.add(item.id)),
        );
        _pageCursor = result.nextCursor;
        _hasMore = result.hasMore;
        _pageError = null;
        _pageStackTrace = null;
      });
    } catch (error, stackTrace) {
      if (!mounted || requestedFilter != _filter) return;
      setState(() {
        _pageError = error;
        _pageStackTrace = stackTrace;
      });
    } finally {
      if (mounted && requestedFilter == _filter) {
        setState(() {
          _loadingInitial = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(stravaConnectionProvider);
    final connectionLoading = ref.watch(stravaConnectionLoadingProvider);
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(userProfileProvider).value;
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final currentUid = ref.watch(firebaseUserProvider).value?.uid;
    final myActive = ref.watch(myActiveContractsProvider);

    // Giáo án AI Coach giờ nằm chung feed Kèo: giáo án mình sở hữu (kể cả riêng
    // tư) + các giáo án công khai của người khác. Dedup theo id, của mình trước.
    final ownedCoach = ref.watch(coachPlanProvider).value;
    final publicCoaches =
        ref.watch(publicCoachPlansProvider).value ?? const <TrainingPlan>[];
    final coachPlans = <TrainingPlan>[
      ?ownedCoach,
      ...(publicCoaches.where((p) => p.id != ownedCoach?.id).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ))),
    ];

    final keoBody = myActive.when(
      data: (mine) {
        return _ContractFeed(
          source: _pageSource,
          myContracts: mine,
          coachPlans: coachPlans,
          currentUid: currentUid,
          currentProfile: profile,
          members: members,
          joining: _joining,
          filter: _filter,
          hasMore: _hasMore,
          loadingMore: _loadingMore,
          onFilterChanged: (filter) {
            if (_filter == filter) return;
            _filter = filter;
            _loadFirstPage();
          },
          onLoadMore: _loadNextPage,
          onJoin: _joinContract,
          onOpenCoach: (plan) => context.push('/coach/${plan.id}'),
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải kèo của bạn: $error')),
      loading: () => const RunNowLoading(label: 'Đang tải kèo'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kèo'),
        actions: [
          if (connected)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _ContractSyncAction(
                syncing: sync.syncing,
                synced: sync.lastSyncSucceeded,
                onPressed: () => ref
                    .read(syncControllerProvider)
                    .startBackgroundSync(force: true),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: connectionLoading
            ? 'Đang kiểm tra Strava'
            : connected
            ? 'Tạo kèo'
            : 'Kết nối Strava',
        onPressed: connectionLoading
            ? null
            : () => _createContract(
                myActive.value ?? const [],
                connected,
                currentUid,
              ),
        child: Icon(
          connectionLoading
              ? Icons.more_horiz_rounded
              : connected
              ? Icons.add_rounded
              : Icons.link_rounded,
        ),
      ),
      body: keoBody,
    );
  }

  Future<void> _createContract(
    List<RunContract> myActive,
    bool connected,
    String? currentUid,
  ) async {
    if (!connected) {
      ref.read(stravaAuthProvider).connect();
      return;
    }
    final unfinished = myActive
        .where((contract) => !contract.completedBy(currentUid))
        .toList();
    if (unfinished.length >= maxActiveRunContracts) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bạn đang tham gia ${unfinished.length} kèo chưa hoàn thành. '
            'Hãy chốt một kèo để tạo kèo mới.',
          ),
        ),
      );
      return;
    }
    await context.push('/contracts/new');
    if (mounted) await _loadFirstPage();
  }

  Future<void> _joinContract(RunContract contract) async {
    if (!_joining.add(contract.id)) return;
    setState(() {});
    try {
      await ref.read(runContractControllerProvider).join(contract);
      if (mounted) await _loadFirstPage();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      _joining.remove(contract.id);
      if (mounted) setState(() {});
    }
  }
}

enum _ContractFilter { active, completed, failed }

class _ContractSyncAction extends StatefulWidget {
  const _ContractSyncAction({
    required this.syncing,
    required this.synced,
    required this.onPressed,
  });

  final bool syncing;
  final bool synced;
  final VoidCallback onPressed;

  @override
  State<_ContractSyncAction> createState() => _ContractSyncActionState();
}

class _ContractSyncActionState extends State<_ContractSyncAction>
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
  void didUpdateWidget(covariant _ContractSyncAction oldWidget) {
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
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 999,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: widget.syncing ? null : widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _controller,
                child: Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Đồng bộ',
                style: TextStyle(fontWeight: FontWeight.w700, color: onSurface),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.synced
                      ? RunNowSemanticColors.success
                      : onSurface.withValues(alpha: 0.24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContractFeed extends StatelessWidget {
  const _ContractFeed({
    required this.source,
    required this.myContracts,
    required this.coachPlans,
    required this.currentUid,
    required this.currentProfile,
    required this.members,
    required this.joining,
    required this.filter,
    required this.hasMore,
    required this.loadingMore,
    required this.onFilterChanged,
    required this.onLoadMore,
    required this.onJoin,
    required this.onOpenCoach,
  });

  final AsyncValue<List<RunContract>> source;
  final List<RunContract> myContracts;
  final List<TrainingPlan> coachPlans;
  final String? currentUid;
  final UserProfile? currentProfile;
  final List<MemberProfile> members;
  final Set<String> joining;
  final _ContractFilter filter;
  final bool hasMore;
  final bool loadingMore;
  final ValueChanged<_ContractFilter> onFilterChanged;
  final VoidCallback onLoadMore;
  final ValueChanged<RunContract> onJoin;
  final ValueChanged<TrainingPlan> onOpenCoach;

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb
        ? RunNowWebLayout.isDesktop(context)
        : MediaQuery.sizeOf(context).width >= 900;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 20 : 16, 14, wide ? 20 : 16, 10),
          child: _ContractFilterBar(value: filter, onChanged: onFilterChanged),
        ),
        Expanded(
          child: source.when(
            data: (list) {
              final visible = switch (filter) {
                _ContractFilter.active => _mergeContracts(list, myContracts),
                _ContractFilter.completed => _mergeCompleted(
                  list,
                  myContracts,
                  currentUid,
                ),
                _ContractFilter.failed => list,
              };
              final canLoadMore = hasMore;
              final profiles = {
                for (final member in members) member.uid: member,
              };
              // Coach card chỉ xuất hiện ở filter "đang chạy", nằm đầu feed.
              final coachCards = filter == _ContractFilter.active
                  ? coachPlans
                  : const <TrainingPlan>[];
              if (visible.isEmpty && coachCards.isEmpty) {
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 20 : 16,
                    0,
                    wide ? 20 : 16,
                    130,
                  ),
                  children: [_EmptyContracts(filter: filter)],
                );
              }
              if (wide) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 130),
                  children: [
                    Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        for (final plan in coachCards)
                          SizedBox(
                            width: 440,
                            child: _coachCard(context, plan, profiles),
                          ),
                        for (final contract in visible)
                          SizedBox(
                            width: 440,
                            child: _contractCard(context, contract, profiles),
                          ),
                      ],
                    ),
                    if (canLoadMore) ...[
                      const SizedBox(height: 20),
                      _LoadMoreContracts(
                        onPressed: loadingMore ? null : onLoadMore,
                        loading: loadingMore,
                      ),
                    ],
                  ],
                );
              }
              final lead = coachCards.length;
              final itemCount =
                  lead + visible.length + (canLoadMore ? 1 : 0);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                itemCount: itemCount,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  if (index < lead) {
                    return _coachCard(context, coachCards[index], profiles);
                  }
                  final i = index - lead;
                  if (i == visible.length) {
                    return _LoadMoreContracts(
                      onPressed: loadingMore ? null : onLoadMore,
                      loading: loadingMore,
                    );
                  }
                  return _contractCard(context, visible[i], profiles);
                },
              );
            },
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Không thể tải danh sách kèo: $error'),
              ),
            ),
            loading: () => const RunNowLoading(label: 'Đang tải kèo'),
          ),
        ),
      ],
    );
  }

  Widget _coachCard(
    BuildContext context,
    TrainingPlan plan,
    Map<String, MemberProfile> profiles,
  ) {
    final isMine = plan.isOwner(currentUid);
    return CoachCard(
      plan: plan,
      currentUid: currentUid,
      ownerName: isMine
          ? (currentProfile?.displayName ?? 'Bạn')
          : (profiles[plan.ownerUid]?.displayName ?? 'HLV 3i'),
      ownerAvatarUrl: isMine
          ? currentProfile?.avatarUrl
          : profiles[plan.ownerUid]?.avatarUrl,
      onTap: () => onOpenCoach(plan),
    );
  }

  Widget _contractCard(
    BuildContext context,
    RunContract contract,
    Map<String, MemberProfile> profiles,
  ) {
    final isMine = contract.creatorUid == currentUid;
    final member = profiles[contract.creatorUid];
    return RunContractCard(
      contract: contract,
      ownerName: isMine
          ? currentProfile?.displayName ?? 'Bạn'
          : member?.displayName ?? '3i member',
      ownerAvatarUrl: isMine ? currentProfile?.avatarUrl : member?.avatarUrl,
      currentUid: currentUid,
      participantAvatarUrls: [
        for (final participant in contract.participants.values)
          participant.uid == currentUid
              ? currentProfile?.avatarUrl
              : profiles[participant.uid]?.avatarUrl,
      ],
      isMine: isMine,
      compact: true,
      onJoin:
          currentUid != null &&
              contract.participantFor(currentUid) == null &&
              !joining.contains(contract.id)
          ? () => onJoin(contract)
          : null,
      onTap: () => context.push('/contracts/${contract.id}'),
    );
  }
}

class _LoadMoreContracts extends StatelessWidget {
  const _LoadMoreContracts({required this.onPressed, required this.loading});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.expand_more_rounded),
      label: Text(loading ? 'Đang tải' : 'Tải thêm'),
    ),
  );
}

List<RunContract> _mergeContracts(
  List<RunContract> clubContracts,
  List<RunContract> mine,
) {
  final byId = {for (final contract in clubContracts) contract.id: contract};
  for (final contract in mine) {
    if (contract.isActive) byId[contract.id] = contract;
  }
  final result = byId.values.toList();
  result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
}

/// Kèo tôi đã hoàn thành: gồm kèo đã chốt kết quả (`status: completed`) và
/// kèo tôi đã đạt mục tiêu nhưng chưa tới hạn chốt (`status: active` vẫn
/// chạy tới deadline/finalize) — cùng một trải nghiệm "đã cứu" trên card.
List<RunContract> _mergeCompleted(
  List<RunContract> history,
  List<RunContract> myActive,
  String? currentUid,
) {
  final byId = {
    for (final contract in history)
      if (contract.status == RunContractStatus.completed) contract.id: contract,
  };
  for (final contract in myActive) {
    if (contract.isActive && contract.completedBy(currentUid)) {
      byId[contract.id] = contract;
    }
  }
  final result = byId.values.toList();
  result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
}

class _EmptyContracts extends StatelessWidget {
  const _EmptyContracts({required this.filter});

  final _ContractFilter filter;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (filter) {
      _ContractFilter.active => (
        'Chưa có kèo đang diễn ra',
        'Hãy là người cắm lá cờ đầu tiên.',
      ),
      _ContractFilter.completed => (
        'Chưa có kèo nào hoàn thành',
        'Hoàn thành một kèo để thấy nó ở đây.',
      ),
      _ContractFilter.failed => (
        'Chưa có kèo nào thất bại',
        'Cứ giữ phong độ này nhé.',
      ),
    };
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.flag_outlined,
            size: 44,
            color: context.runNowPalette.accent,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle),
        ],
      ),
    );
  }
}

class _ContractFilterBar extends StatelessWidget {
  const _ContractFilterBar({required this.value, required this.onChanged});

  final _ContractFilter value;
  final ValueChanged<_ContractFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _ContractFilter.active: 'Đang chạy',
      _ContractFilter.completed: 'Hoàn thành',
      _ContractFilter.failed: 'Thất bại',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _ContractFilter.values) ...[
            ChoiceChip(
              label: Text(labels[filter]!),
              selected: value == filter,
              showCheckmark: false,
              onSelected: (_) => onChanged(filter),
              labelStyle: TextStyle(
                color: value == filter
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: value == filter
                    ? Colors.transparent
                    : context.runNowPalette.border,
              ),
            ),
            if (filter != _ContractFilter.values.last)
              const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}
