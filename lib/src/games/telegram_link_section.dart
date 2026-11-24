import 'package:flutter/material.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Nút liên kết Telegram cho người chưa liên kết. Đã liên kết hay đang đọc
/// trạng thái thì không vẽ gì, huỷ liên kết nằm ở Cài đặt. Lỗi của nút đưa cho
/// [onError] để màn hình báo.
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
    if (status?.linked == true ||
        (status == null && controller.error == null)) {
      return const SizedBox.shrink();
    }
    final Widget body;
    if (status == null) {
      body = Row(
        children: [
          const Expanded(child: Text('Chưa đọc được trạng thái Telegram.')),
          TextButton(onPressed: controller.load, child: const Text('Thử lại')),
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
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassPanel(padding: const EdgeInsets.all(16), child: body),
    );
  }
}
