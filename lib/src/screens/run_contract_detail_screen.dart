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
import 'package:myrun/src/widgets/glass.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết kèo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ref
              .watch(runContractProvider(widget.contractId))
              .when(
                data: (contract) => contract == null
                    ? const Center(child: Text('Không tìm thấy kèo chạy.'))
                    : _loggedContent(contract),
                error: (error, stack) => Center(child: Text('$error')),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
        ),
      ),
    );
  }

  Widget _loggedContent(RunContract contract) {
    final currentUid = ref.read(firebaseUserProvider).value?.uid;
    final participant = contract.participantFor(currentUid);
    if (!_recalculated &&
        contract.isActive &&
        participant != null &&
        !contract.completedBy(currentUid)) {
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

  Widget _content(RunContract contract) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final owner = uid == contract.creatorUid;
    var ownerName = '3i member';
    String? ownerAvatarUrl;
    if (owner) {
      final profile = ref.watch(userProfileProvider).value;
      ownerName = profile?.displayName ?? 'Bạn';
      ownerAvatarUrl = profile?.avatarUrl;
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
    final completed = contract.completedBy(uid);
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
        if (participant != null) ...[
          const SizedBox(height: 12),
          _MyProgressCard(contract: contract, participant: participant),
          if (contract.isActive && !completed) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                onPressed: () => _selectActivities(contract, participant),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text(
                  participant.countedActivityIds.isEmpty
                      ? 'Chọn buổi chạy áp dụng'
                      : 'Đổi buổi chạy áp dụng',
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _ParticipantProgressList(
          contract: contract,
          profiles: profiles,
          currentUid: uid,
          currentProfile: ref.watch(userProfileProvider).value,
        ),
        const SizedBox(height: 18),
        if (owner &&
            contract.isActive &&
            lifecycle == RunContractLifecycle.awaitingFinalize)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _primaryAction(contract, lifecycle),
          )
        else if (owner && contract.isActive && completed)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _CompletedParticipant(),
          )
        else if (owner && contract.isActive)
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
        if (!owner && contract.isActive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: participant == null
                ? FilledButton.icon(
                    onPressed: _working ? null : () => _join(contract),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Tham gia kèo'),
                  )
                : completed
                ? const _CompletedParticipant()
                : FilledButton.icon(
                    onPressed: () => context.go('/tracking'),
                    icon: const Icon(Icons.directions_run_rounded),
                    label: const Text('Chạy để cứu kèo'),
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
        _ => FilledButton.icon(
          onPressed: () => context.go('/tracking'),
          icon: const Icon(Icons.directions_run_rounded),
          label: const Text('Chạy để cứu kèo'),
        ),
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
    for (final item in [
      ...ref.read(clubRunContractsProvider).value ?? const <RunContract>[],
      ...ref.read(myActiveContractsProvider).value ?? const <RunContract>[],
    ]) {
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

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
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
    _selectedIds = {...widget.initialActivityIds};
    _options = widget.controller.activityOptions(widget.contract);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
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
                'Chỉ session bạn xác nhận mới được cộng vào kèo này.',
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
                      return const Center(child: CircularProgressIndicator());
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
                      : Text('Áp dụng ${_selectedIds.length} buổi chạy'),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final completed = contract.overallProgressPercent >= 100;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
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
                    : NetworkImage(ownerAvatarUrl!),
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
          const SizedBox(height: 20),
          Text(
            contract.title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            'Cùng hoàn thành ${_contractValue(contract.metric, contract.targetValue)} '
            'trong kỳ này. Tiến trình cập nhật từ Strava.',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.58),
              height: 1.35,
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
    final foreground =
        ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      gradient: LinearGradient(
        colors: [palette.accent, palette.accentDeep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const Spacer(),
              Text(
                rawRatio >= 1 ? 'Đã hoàn thành' : 'Chưa hoàn thành',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _contractValue(contract.metric, participant.progressValue),
                style: TextStyle(
                  color: foreground,
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '/ ${_contractValue(contract.metric, contract.targetValue)}',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${(rawRatio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: foreground,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: rawRatio.clamp(0.0, 1.0),
            minHeight: 9,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: foreground.withValues(alpha: 0.2),
            color: foreground,
          ),
          const SizedBox(height: 10),
          Text(
            rawRatio >= 1
                ? 'Bạn đã hoàn thành mục tiêu.'
                : 'Còn ${_contractValue(contract.metric, remaining)} để hoàn thành',
            style: TextStyle(
              color: foreground.withValues(alpha: 0.82),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Deadline ${DateFormat('dd/MM · HH:mm').format(contract.endAtExclusive.subtract(const Duration(seconds: 1)))}',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (contract.lastCalculatedAt != null)
                Text(
                  'Sync ${DateFormat('HH:mm').format(contract.lastCalculatedAt!)}',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
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
              : NetworkImage(avatarUrl!),
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
                    Icon(Icons.check_circle, color: palette.accent, size: 17),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: palette.border,
                color: palette.accent,
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
                color: completed ? palette.accent : null,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              completed ? 'Xong' : '${(ratio * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: completed
                    ? palette.accent
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

class _CompletedParticipant extends StatelessWidget {
  const _CompletedParticipant();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.verified_rounded, color: context.runNowPalette.accent),
      const SizedBox(width: 8),
      const Text(
        'Bạn đã hoàn thành kèo',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ],
  );
}

String _contractValue(RunContractMetric metric, double value) =>
    switch (metric) {
      RunContractMetric.distance || RunContractMetric.longestRun =>
        '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} km',
      RunContractMetric.activityCount => '${value.toInt()} buổi',
      RunContractMetric.activeDays => '${value.toInt()} ngày',
    };
