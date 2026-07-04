import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/theme.dart';

class RunContractCard extends StatelessWidget {
  const RunContractCard({
    required this.contract,
    this.ownerName,
    this.ownerAvatarUrl,
    this.currentUid,
    this.participantAvatarUrls = const [],
    this.onTap,
    this.onJoin,
    this.compact = false,
    this.isMine = false,
    super.key,
  });

  final RunContract contract;
  final String? ownerName;
  final String? ownerAvatarUrl;
  final String? currentUid;
  final List<String?> participantAvatarUrls;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;
  final bool compact;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final participant = contract.participantFor(currentUid);
    final state = contractUiState(contract, DateTime.now());
    final stateColor = _stateColor(context, state);
    final completedCount = contract.participants.values
        .where((item) => item.progressValue >= contract.targetValue)
        .length;
    final progressValue =
        participant?.progressValue ??
        contract.overallProgressRatio * contract.targetValue;
    final ratio = contract.targetValue <= 0
        ? 0.0
        : progressValue / contract.targetValue;
    final percent = (ratio * 100).toStringAsFixed(0);
    final surface = palette.glassStart;
    const radius = 16.0;
    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                contract: contract,
                ownerName: ownerName,
                ownerAvatarUrl: ownerAvatarUrl,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contract.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          participant == null
                              ? '${contract.participantCount} người · TB ${contract.overallProgressPercent.toStringAsFixed(0)}%'
                              : _valueOverTarget(
                                  contract.metric,
                                  progressValue,
                                  contract.targetValue,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.52),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    percent,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 31,
                      height: 0.9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      '%',
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.38),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 7,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: onSurface.withValues(alpha: 0.09),
                color: stateColor,
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  _AvatarStack(urls: participantAvatarUrls),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '$completedCount/${contract.participantCount} hoàn thành · TB ${contract.overallProgressPercent.toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.58),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (participant == null &&
                      contract.isActive &&
                      onJoin != null)
                    FilledButton(
                      onPressed: onJoin,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Tham gia'),
                    )
                  else
                    Text(
                      DateFormat('dd/MM · HH:mm').format(
                        contract.endAtExclusive.subtract(
                          const Duration(seconds: 1),
                        ),
                      ),
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.42),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.contract,
    required this.ownerName,
    required this.ownerAvatarUrl,
  });

  final RunContract contract;
  final String? ownerName;
  final String? ownerAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final state = contractUiState(contract, DateTime.now());
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final name = ownerName ?? '3i member';
    return Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundImage: ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
              ? null
              : NetworkImage(ownerAvatarUrl!),
          child: ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
              ? Text(name.isEmpty ? '?' : name[0].toUpperCase())
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'Người tạo · ${_value(contract.metric, contract.targetValue)}',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.52),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _stateColor(context, state).withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _stateColor(context, state),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _stateLabel(state),
                  style: TextStyle(
                    color: _stateColor(context, state),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.urls});

  final List<String?> urls;

  @override
  Widget build(BuildContext context) {
    final shown = urls.take(3).toList();
    if (shown.isEmpty) {
      return Icon(
        Icons.group_outlined,
        size: 20,
        color: context.runNowPalette.accent,
      );
    }
    return SizedBox(
      // CircleAvatar đường kính 28; cộng đúng offset overlap cho từng avatar.
      // Trước đây dùng 24 khiến avatar cuối bị clip mất 4 px.
      width: 28.0 + (shown.length - 1) * 17,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * 17,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: context.runNowPalette.accent,
                backgroundImage: shown[index] == null || shown[index]!.isEmpty
                    ? null
                    : NetworkImage(shown[index]!),
                child: shown[index] == null || shown[index]!.isEmpty
                    ? const Icon(Icons.person, size: 14)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

String runContractMetricLabel(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => 'Quãng đường',
  RunContractMetric.activityCount => 'Số buổi',
  RunContractMetric.activeDays => 'Ngày active',
  RunContractMetric.longestRun => 'Chạy dài nhất',
};

String _value(RunContractMetric metric, double value) => switch (metric) {
  RunContractMetric.distance || RunContractMetric.longestRun =>
    '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} km',
  RunContractMetric.activityCount => '${value.toInt()} buổi',
  RunContractMetric.activeDays => '${value.toInt()} ngày',
};

String _valueOverTarget(RunContractMetric metric, double value, double target) {
  String n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  return switch (metric) {
    RunContractMetric.distance ||
    RunContractMetric.longestRun => '${n(value)} / ${n(target)} km',
    RunContractMetric.activityCount =>
      '${value.toInt()} / ${target.toInt()} buổi',
    RunContractMetric.activeDays => '${value.toInt()} / ${target.toInt()} ngày',
  };
}

String _stateLabel(RunContractUiState state) => switch (state) {
  RunContractUiState.scheduled => 'SẮP BẮT ĐẦU',
  RunContractUiState.newContract => 'MỚI CHỐT',
  RunContractUiState.onTrack => 'ĐANG CHẠY',
  RunContractUiState.rescuable => 'CÓ THỂ CỨU',
  RunContractUiState.atRisk => 'SẮP VỠ',
  RunContractUiState.saved => 'ĐÃ CỨU',
  RunContractUiState.syncGrace => 'CHỜ SYNC',
  RunContractUiState.awaitingFinalize => 'CHỜ CHỐT',
  RunContractUiState.broken => 'KÈO VỠ',
  RunContractUiState.cancelled => 'ĐÃ HỦY',
};

Color _stateColor(BuildContext context, RunContractUiState state) =>
    switch (state) {
      RunContractUiState.atRisk ||
      RunContractUiState.broken => Theme.of(context).colorScheme.error,
      RunContractUiState.rescuable ||
      RunContractUiState.syncGrace => context.runNowPalette.tertiary,
      _ => context.runNowPalette.accent,
    };
