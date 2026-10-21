import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'training_plan_models.dart';
import 'training_plan_repository.dart';

/// Hỏi đáp riêng với AI Coach.
///
/// Khác chat nhóm ở chỗ mọi câu trả lời đều đặt trong ngữ cảnh CỦA NGƯỜI HỎI:
/// backend nạp giáo án đang chạy (hoặc bản nháp) cộng phong độ gần đây trước
/// khi hỏi model. Nhờ vậy "tuần này nặng quá phải làm sao" trả lời được bằng
/// đúng số buổi trong lịch người đó.
class CoachChatScreen extends ConsumerStatefulWidget {
  const CoachChatScreen({super.key, required this.planId});

  /// Giáo án đang hỏi — kênh chat riêng của user gắn với giáo án này.
  final String planId;

  @override
  ConsumerState<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends ConsumerState<CoachChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Timer? _replyTimeout;

  @override
  void dispose() {
    _replyTimeout?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      // Backend xử bất đồng bộ: câu hỏi + trả lời được bot ghi vào chat rồi về
      // qua stream. Giữ trạng thái "đang trả lời" tới khi reply xuất hiện (ở
      // listener trong build) hoặc hết timeout.
      await ref.read(coachControllerProvider).ask(widget.planId, text);
      _replyTimeout?.cancel();
      _replyTimeout = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() => _sending = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Coach chưa trả lời được: $e')),
        );
        _input.text = text; // trả lại câu hỏi để không phải gõ lại
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final messages = ref.watch(coachChatProvider(widget.planId));
    final plan = ref.watch(coachPlanByIdProvider(widget.planId)).value;

    ref.listen(coachChatProvider(widget.planId), (_, next) {
      _scrollToEnd();
      // Reply của coach về → tắt trạng thái "đang trả lời".
      final msgs = next.value;
      if (_sending && msgs != null && msgs.isNotEmpty && msgs.last.fromCoach) {
        _replyTimeout?.cancel();
        setState(() => _sending = false);
      }
    });

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Hỏi Coach'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Lỗi tải hội thoại: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (list) => list.isEmpty
                  ? _EmptyChat(plan: plan, onPick: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _Bubble(message: list[i]),
                    ),
            ),
          ),
          if (_sending)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Coach đang xem lịch của bạn…',
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
                ],
              ),
            ),
          _Composer(
            controller: _input,
            enabled: !_sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── bong bóng

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CoachChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final fromCoach = message.fromCoach;
    return Align(
      alignment: fromCoach ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: fromCoach ? palette.glassStart : palette.accent,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(fromCoach ? 4 : 14),
            bottomRight: Radius.circular(fromCoach ? 14 : 4),
          ),
          border: fromCoach ? Border.all(color: palette.border) : null,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: fromCoach ? palette.ink : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── màn trống

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.plan, required this.onPick});
  final TrainingPlan? plan;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;

    // Gợi ý bám vào giáo án thật — có lịch thì hỏi được chuyện cụ thể, chưa
    // có thì chỉ hỏi được chuyện chung.
    final suggestions = plan == null
        ? const [
            'Mình nên bắt đầu chạy từ đâu?',
            'Chạy bao nhiêu buổi một tuần là hợp lý?',
            'Làm sao biết mình chạy đúng pace nhẹ?',
          ]
        : const [
            'Hôm nay mình chạy bài gì?',
            'Tuần này nặng quá, giảm bớt được không?',
            'Vì sao lịch xếp buổi dài vào cuối tuần?',
            'Mình bị đau gối, có nên chạy tiếp không?',
          ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Text(
          'Hỏi gì cũng được',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          plan == null
              ? 'Coach chưa thấy giáo án nào của bạn, nên sẽ trả lời ở mức chung. '
                    'Tạo giáo án rồi hỏi lại sẽ cụ thể hơn nhiều.'
              : 'Coach đọc được giáo án và số liệu chạy của bạn, nên cứ hỏi thẳng '
                    'vào buổi tập hay tuần đang tập.',
          style: TextStyle(fontSize: 15, height: 1.5, color: palette.textMuted),
        ),
        const SizedBox(height: 26),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => onPick(s),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s,
                        style: TextStyle(fontSize: 14.5, color: palette.ink),
                      ),
                    ),
                    Icon(Icons.north_east_rounded,
                        size: 16, color: palette.textMuted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── ô nhập

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Hỏi coach…',
                  filled: true,
                  fillColor: palette.glassStart,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor:
                    Theme.of(context).brightness == Brightness.dark
                    ? RunNowDataColors.coachOnAccentDark
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
