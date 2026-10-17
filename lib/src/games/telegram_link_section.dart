import 'package:flutter/material.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Trạng thái liên kết Telegram kèm nút liên kết hoặc huỷ. Lỗi của nút đưa
/// cho [onError] để màn hình báo.
class TelegramLinkSection extends StatelessWidget {
  const TelegramLinkSection({
    super.key,
    required this.controller,
    required this.onError,
  });

  final TelegramLinkController controller;
  final ValueChanged<Object> onError;

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final status = controller.status;
    final busy = controller.busy;
    final Widget body;
    if (status == null) {
      body = controller.error == null
          ? Text(
              'Đang kiểm tra Telegram…',
              style: TextStyle(color: palette.textMuted),
            )
          : Row(
              children: [
                const Expanded(
                  child: Text('Chưa đọc được trạng thái Telegram.'),
                ),
                TextButton(
                  onPressed: controller.load,
                  child: const Text('Thử lại'),
                ),
              ],
            );
    } else if (status.linked) {
      final name = status.tgUsername != null
          ? '@${status.tgUsername}'
          : status.displayName ?? 'Telegram';
      body = Row(
        children: [
          Icon(Icons.check_circle_rounded, color: palette.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Đã liên kết $name.',
              style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _guard(controller.unlink),
            child: const Text('Không phải bạn? Huỷ'),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => _guard(controller.link),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Liên kết Telegram'),
          ),
          if (controller.waiting) ...[
            const SizedBox(height: 8),
            Text(
              'Bấm Start trong Telegram rồi quay lại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted),
            ),
          ],
        ],
      );
    }
    return GlassPanel(padding: const EdgeInsets.all(16), child: body);
  }
}
