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
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/glass.dart';

class RunContractHomeScreen extends ConsumerStatefulWidget {
  const RunContractHomeScreen({super.key});

  @override
  ConsumerState<RunContractHomeScreen> createState() =>
      _RunContractHomeScreenState();
}

class _RunContractHomeScreenState extends ConsumerState<RunContractHomeScreen> {
  final _recalculatedBatchKeys = <String>{};
  final _joining = <String>{};
  _ContractFilter _filter = _ContractFilter.active;

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(stravaConnectionProvider);
    final sync = ref.watch(syncControllerProvider);
    final syncRevision = sync.completedRevision;
    final profile = ref.watch(userProfileProvider).value;
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final currentUid = ref.watch(firebaseUserProvider).value?.uid;
    final myActive = ref.watch(myActiveContractsProvider);
    final clubContracts = ref.watch(clubRunContractsProvider);

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
        tooltip: connected ? 'Tạo kèo' : 'Kết nối Strava',
        onPressed: () =>
            _createContract(myActive.value ?? const [], connected, currentUid),
        child: Icon(connected ? Icons.add_rounded : Icons.link_rounded),
      ),
      body: myActive.when(
        data: (mine) {
          _scheduleRecalculations(
            connected: connected,
            contracts: mine,
            syncRevision: syncRevision,
            currentUid: currentUid,
          );
          return _ContractFeed(
            contracts: clubContracts,
            myContracts: mine,
            currentUid: currentUid,
            currentProfile: profile,
            members: members,
            joining: _joining,
            filter: _filter,
            onFilterChanged: (filter) => setState(() => _filter = filter),
            onJoin: _joinContract,
          );
        },
        error: (error, stack) =>
            Center(child: Text('Không thể tải kèo của bạn: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _scheduleRecalculations({
    required bool connected,
    required List<RunContract> contracts,
    required int syncRevision,
    required String? currentUid,
  }) {
    if (!connected || currentUid == null) return;
    final pending =
        contracts
            .where((contract) => !contract.completedBy(currentUid))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (pending.isEmpty) return;
    final key = '$syncRevision:${pending.map((item) => item.id).join(',')}';
    if (!_recalculatedBatchKeys.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(runContractControllerProvider);
      // Một activity chỉ thuộc một kèo. Chạy tuần tự để kèo trước lưu claim
      // trước khi kèo sau đọc danh sách activity đã được sử dụng.
      for (final contract in pending) {
        if (!mounted) return;
        if (contract.creatorUid == currentUid) {
          await controller.recalculate(contract);
        } else {
          await controller.recalculateParticipant(contract);
        }
      }
    });
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
    context.push('/contracts/new');
  }

  Future<void> _joinContract(RunContract contract) async {
    if (!_joining.add(contract.id)) return;
    setState(() {});
    try {
      await ref.read(runContractControllerProvider).join(contract);
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

enum _ContractFilter { mine, active, public }

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
    final icon = widget.syncing
        ? RotationTransition(turns: _controller, child: const Icon(Icons.sync))
        : Icon(widget.synced ? Icons.check_rounded : Icons.sync_rounded);
    return GlassIconButton(
      tooltip: 'Đồng bộ Strava',
      onPressed: widget.syncing ? null : widget.onPressed,
      icon: icon,
    );
  }
}

class _ContractFeed extends StatelessWidget {
  const _ContractFeed({
    required this.contracts,
    required this.myContracts,
    required this.currentUid,
    required this.currentProfile,
    required this.members,
    required this.joining,
    required this.filter,
    required this.onFilterChanged,
    required this.onJoin,
  });

  final AsyncValue<List<RunContract>> contracts;
  final List<RunContract> myContracts;
  final String? currentUid;
  final UserProfile? currentProfile;
  final List<MemberProfile> members;
  final Set<String> joining;
  final _ContractFilter filter;
  final ValueChanged<_ContractFilter> onFilterChanged;
  final ValueChanged<RunContract> onJoin;

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb
        ? RunNowWebLayout.isDesktop(context)
        : MediaQuery.sizeOf(context).width >= 900;
    return contracts.when(
      data: (clubContracts) {
        final allContracts = _mergeContracts(clubContracts, myContracts);
        final visible = allContracts.where((contract) {
          return switch (filter) {
            _ContractFilter.mine => contract.participantFor(currentUid) != null,
            _ContractFilter.active => contract.isActive,
            _ContractFilter.public =>
              contract.visibility == RunContractVisibility.club,
          };
        }).toList();
        final profiles = {for (final member in members) member.uid: member};
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 20 : 16, 18, wide ? 20 : 16, 130),
          children: [
            _ContractFilterBar(value: filter, onChanged: onFilterChanged),
            const SizedBox(height: 18),
            if (visible.isEmpty)
              _EmptyContracts(filtered: allContracts.isNotEmpty)
            else if (wide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    for (final contract in visible)
                      SizedBox(
                        width: 440,
                        child: _contractCard(context, contract, profiles),
                      ),
                  ],
                ),
              )
            else
              for (var index = 0; index < visible.length; index++) ...[
                _contractCard(context, visible[index], profiles),
                if (index != visible.length - 1) const SizedBox(height: 14),
              ],
          ],
        );
      },
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Không thể tải danh sách kèo: $error'),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
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

class _EmptyContracts extends StatelessWidget {
  const _EmptyContracts({this.filtered = false});

  final bool filtered;

  @override
  Widget build(BuildContext context) => GlassPanel(
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
        Text(
          filtered ? 'Không có kèo phù hợp' : 'Chưa có kèo đang diễn ra',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          filtered
              ? 'Hãy thử một bộ lọc khác.'
              : 'Hãy là người cắm lá cờ đầu tiên.',
        ),
      ],
    ),
  );
}

class _ContractFilterBar extends StatelessWidget {
  const _ContractFilterBar({required this.value, required this.onChanged});

  final _ContractFilter value;
  final ValueChanged<_ContractFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _ContractFilter.mine: 'Của tôi',
      _ContractFilter.active: 'Đang chạy',
      _ContractFilter.public: 'Công khai',
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
