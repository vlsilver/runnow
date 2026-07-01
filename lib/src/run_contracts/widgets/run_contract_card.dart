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
    final completedCount = contract.participants.values
        .where((item) => item.progressValue >= contract.targetValue)
        .length;
    // Nền đặc + viền + bóng nhẹ để card nổi rõ trên nền giấy, không còn trong
    // suốt và không bị "đè" khi cuộn/nhấn (ripple gói gọn trong bo góc).
    final surface = isMine ? palette.tint : palette.glassStart;
    const radius = 18.0;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isMine ? palette.accent.withValues(alpha: 0.45) : palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 4, child: ColoredBox(color: palette.accent)),
                Expanded(
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
                        const SizedBox(height: 11),
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
                        const SizedBox(height: 12),
                        if (participant != null) ...[
                          _ProgressLine(
                            label: 'CỦA BẠN',
                            progressValue: participant.progressValue,
                            contract: contract,
                            emphasize: true,
                          ),
                          const SizedBox(height: 10),
                        ],
                        _ProgressLine(
                          label: 'CẢ NHÓM',
                          progressValue:
                              contract.overallProgressRatio *
                              contract.targetValue,
                          contract: contract,
                          trailingPrefix:
                              '${contract.participantCount} người · TB',
                          showValue: false,
                          dim: true,
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: onSurface.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            _AvatarStack(urls: participantAvatarUrls),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '$completedCount/${contract.participantCount} đã hoàn thành',
                                style: TextStyle(
                                  color: onSurface.withValues(alpha: 0.62),
                                  fontSize: 11.5,
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
                                    horizontal: 18,
                                    vertical: 9,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                                  color: onSurface.withValues(alpha: 0.46),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    final name = ownerName ?? 'RunNow member';
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

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.progressValue,
    required this.contract,
    this.trailingPrefix,
    this.emphasize = false,
    this.showValue = true,
    this.dim = false,
  });

  final String label;
  final double progressValue;
  final RunContract contract;
  final String? trailingPrefix;
  final bool emphasize;
  final bool showValue;

  /// Hàng phụ (cả nhóm) — thanh mảnh, màu nhạt để nhường mắt cho "của bạn".
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rawRatio = contract.targetValue <= 0
        ? 0.0
        : progressValue / contract.targetValue;
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: emphasize
                    ? palette.accentDeep
                    : onSurface.withValues(alpha: 0.5),
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            if (trailingPrefix != null) ...[
              Text(
                trailingPrefix!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: onSurface.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (showValue) ...[
              Text(
                _valueOverTarget(
                  contract.metric,
                  progressValue,
                  contract.targetValue,
                ),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '${(rawRatio * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: emphasize ? palette.accentDeep : null,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: rawRatio.clamp(0.0, 1.0),
          minHeight: dim ? 5 : 7,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: onSurface.withValues(alpha: 0.09),
          color: dim ? palette.accent.withValues(alpha: 0.5) : palette.accent,
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
      width: 24.0 + (shown.length - 1) * 17,
      height: 28,
      child: Stack(
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
    RunContractMetric.distance || RunContractMetric.longestRun =>
      '${n(value)} / ${n(target)} km',
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
