import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/live_cheers.dart';

/// Rules cho một người bấm lại sau 3 giây tính theo giờ server. App chờ dư
/// một giây vì giờ server của hai lần ghi lệch theo độ trễ mạng mỗi lần.
const liveCheerCooldown = Duration(seconds: 4);

/// Tổng cổ vũ của một buổi live, ví dụ "🔥 4  👏 1". Chưa ai cổ vũ, đang tải
/// hay đọc lỗi thì không chiếm chỗ. [max] giới hạn số emoji cho chỗ hẹp.
class LiveCheerTotals extends ConsumerWidget {
  const LiveCheerTotals({
    required this.sessionId,
    this.max,
    this.style,
    super.key,
  });

  final String sessionId;
  final int? max;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cheers = ref.watch(liveCheersProvider(sessionId));
    if (cheers.error case final error?) {
      debugPrint('live cheers $sessionId: $error');
    }
    final totals = liveCheerTotals(cheers.value ?? const []);
    if (totals.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      children: [
        for (final (emoji, count) in totals.take(max ?? totals.length))
          Text('$emoji $count', style: style),
      ],
    );
  }
}

/// Hàng emoji cổ vũ ở màn xem live, cho người không ở trong phòng. Bấm xong
/// thì cả hàng mờ đi tới hết [liveCheerCooldown].
class LiveCheerBar extends ConsumerStatefulWidget {
  const LiveCheerBar({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<LiveCheerBar> createState() => _LiveCheerBarState();
}

class _LiveCheerBarState extends ConsumerState<LiveCheerBar> {
  Timer? _cooling;

  @override
  void dispose() {
    _cooling?.cancel();
    super.dispose();
  }

  Future<void> _send(String emoji) async {
    setState(() {
      _cooling = Timer(liveCheerCooldown, () {
        if (mounted) setState(() => _cooling = null);
      });
    });
    try {
      await ref.read(liveCheerRepositoryProvider).send(widget.sessionId, emoji);
    } catch (error) {
      debugPrint('live cheer ${widget.sessionId}: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không gửi được cổ vũ, thử lại nhé.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final emoji in liveCheerEmojis)
        IconButton.filledTonal(
          onPressed: _cooling == null ? () => _send(emoji) : null,
          icon: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
    ],
  );
}
