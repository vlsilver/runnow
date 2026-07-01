import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class RunContractHomeScreen extends ConsumerStatefulWidget {
  const RunContractHomeScreen({super.key});

  @override
  ConsumerState<RunContractHomeScreen> createState() =>
      _RunContractHomeScreenState();
}

class _RunContractHomeScreenState extends ConsumerState<RunContractHomeScreen> {
  final _recalculatedKeys = <String>{};
  final _joining = <String>{};

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(stravaConnectionProvider);
    final syncRevision = ref.watch(syncControllerProvider).completedRevision;
    final profile = ref.watch(userProfileProvider).value;
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final currentUid = ref.watch(firebaseUserProvider).value?.uid;
    final myActive = ref.watch(myActiveContractsProvider);
    final clubContracts = ref.watch(clubRunContractsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kèo'),
        actions: [
          IconButton(
            tooltip: 'Hồ sơ & thành tích',
            onPressed: () => context.push('/settings/profile'),
            icon: CircleAvatar(
              radius: 17,
              backgroundImage: profile?.avatarUrl == null
                  ? null
                  : NetworkImage(profile!.avatarUrl!),
              child: profile?.avatarUrl == null
                  ? const Icon(Icons.person_outline, size: 19)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _createContract(myActive.value ?? const [], connected),
        icon: Icon(connected ? Icons.add_rounded : Icons.link_rounded),
        label: Text(connected ? 'Tạo kèo' : 'Kết nối'),
      ),
      body: myActive.when(
        data: (mine) {
          for (final contract in mine) {
            _scheduleRecalculation(
              connected: connected,
              contract: contract,
              syncRevision: syncRevision,
              asCreator: contract.creatorUid == currentUid,
            );
          }
          return _ContractFeed(
            contracts: clubContracts,
            myContracts: mine,
            currentUid: currentUid,
            currentProfile: profile,
            members: members,
            joining: _joining,
            onJoin: _joinContract,
          );
        },
        error: (error, stack) =>
            Center(child: Text('Không thể tải kèo của bạn: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _scheduleRecalculation({
    required bool connected,
    required RunContract? contract,
    required int syncRevision,
    required bool asCreator,
  }) {
    if (!connected || contract == null) return;
    final key =
        '${asCreator ? 'creator' : 'participant'}:${contract.id}:$syncRevision';
    if (!_recalculatedKeys.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final controller = ref.read(runContractControllerProvider);
        if (asCreator) {
          controller.recalculate(contract).ignore();
        } else {
          controller.recalculateParticipant(contract).ignore();
        }
      }
    });
  }

  Future<void> _createContract(
    List<RunContract> myActive,
    bool connected,
  ) async {
    if (!connected) {
      ref.read(stravaAuthProvider).connect();
      return;
    }
    if (myActive.length >= maxActiveRunContracts) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bạn đang tham gia ${myActive.length} kèo chưa hoàn thành. '
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

class _ContractFeed extends StatelessWidget {
  const _ContractFeed({
    required this.contracts,
    required this.myContracts,
    required this.currentUid,
    required this.currentProfile,
    required this.members,
    required this.joining,
    required this.onJoin,
  });

  final AsyncValue<List<RunContract>> contracts;
  final List<RunContract> myContracts;
  final String? currentUid;
  final UserProfile? currentProfile;
  final List<MemberProfile> members;
  final Set<String> joining;
  final ValueChanged<RunContract> onJoin;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return contracts.when(
      data: (clubContracts) {
        final visible = _mergeContracts(clubContracts, myContracts);
        final profiles = {for (final member in members) member.uid: member};
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 20 : 16, 18, wide ? 20 : 16, 130),
          children: [
            if (visible.isEmpty)
              const _EmptyContracts()
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
          : member?.displayName ?? 'RunNow member',
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
  const _EmptyContracts();

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
          'Chưa có kèo đang diễn ra',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text('Hãy là người cắm lá cờ đầu tiên.'),
      ],
    ),
  );
}
