import 'package:flutter/material.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

/// Nút "MyBot chơi thay" trong ván. Chỉ người chơi tự bật; bật rồi thì gần hết
/// giờ mà chưa chọn, MyBot chọn giúp. Lựa chọn của chủ luôn thắng.
class GameStandInTile extends StatelessWidget {
  const GameStandInTile({
    super.key,
    required this.on,
    required this.busy,
    required this.onChanged,
  });

  final bool on;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RunNowSwitchListTile(
          key: const ValueKey('game-stand-in'),
          secondary: const Icon(Icons.smart_toy_outlined),
          title: const Text('MyBot chơi thay'),
          subtitle: const Text('Chọn giúp khi sắp hết giờ'),
          value: on,
          onChanged: busy ? null : onChanged,
        ),
      ),
    );
  }
}
