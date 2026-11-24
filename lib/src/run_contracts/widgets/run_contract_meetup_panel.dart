import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Giờ hẹn của kèo hẹn chạy và lối vào phòng chạy live. Kèo không có giờ hẹn
/// thì không vẽ gì.
class RunContractMeetupPanel extends StatelessWidget {
  const RunContractMeetupPanel({required this.contract, super.key});

  final RunContract contract;

  @override
  Widget build(BuildContext context) {
    final meetAt = contract.meetAt;
    if (meetAt == null) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final roomId = contract.roomId;
    return GlassPanel(
      borderRadius: 18,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 20, color: palette.accentDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hẹn chạy ${DateFormat('HH:mm · dd/MM').format(meetAt)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chạy chung trong phòng hay chạy riêng đều được, miễn đủ '
            'km trong ngày. Ai đăng ký mà không chạy sẽ bị 3i réo tên.',
            style: TextStyle(color: palette.textMuted, height: 1.4),
          ),
          if (roomId != null && contract.isActive) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/rooms/$roomId'),
                icon: const Icon(Icons.directions_run_rounded),
                label: const Text('Vào phòng chạy'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
