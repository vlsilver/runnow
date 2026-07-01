import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
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
      body: ref
          .watch(runContractProvider(widget.contractId))
          .when(
            data: (contract) => contract == null
                ? const Center(child: Text('Không tìm thấy kèo chạy.'))
                : _loggedContent(contract),
            error: (error, stack) => Center(child: Text('$error')),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
    );
  }

  Widget _loggedContent(RunContract contract) {
    final currentUid = ref.read(firebaseUserProvider).value?.uid;
    final participant = contract.participantFor(currentUid);
    if (!_recalculated && contract.isActive && participant != null) {
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
    var ownerName = 'RunNow member';
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

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
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
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColoredBox(
            color: palette.accent,
            child: const SizedBox(height: 5, width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rawRatio = contract.targetValue <= 0
        ? 0.0
        : participant.progressValue / contract.targetValue;
    final remaining = (contract.targetValue - participant.progressValue).clamp(
      0.0,
      contract.targetValue,
    );
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      gradient: LinearGradient(
        colors: [palette.tint, palette.glassEnd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CỦA BẠN',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                rawRatio >= 1 ? 'Đã hoàn thành' : 'Chưa hoàn thành',
                style: TextStyle(
                  color: rawRatio >= 1
                      ? palette.accent
                      : onSurface.withValues(alpha: 0.58),
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
                  color: palette.accent,
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
                    color: onSurface.withValues(alpha: 0.48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${(rawRatio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: palette.accent,
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
            color: palette.accent,
          ),
          const SizedBox(height: 10),
          Text(
            rawRatio >= 1
                ? 'Bạn đã hoàn thành mục tiêu.'
                : 'Còn ${_contractValue(contract.metric, remaining)} để hoàn thành',
            style: TextStyle(
              color: palette.accent,
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
                        'RunNow member',
              avatarUrl: participants[index].uid == currentUid
                  ? currentProfile?.avatarUrl
                  : profiles[participants[index].uid]?.avatarUrl,
              isCurrentUser: participants[index].uid == currentUid,
            ),
            if (index != participants.length - 1) const Divider(height: 24),
          ],
          const SizedBox(height: 18),
          Divider(color: onSurface.withValues(alpha: 0.1)),
          const SizedBox(height: 10),
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
