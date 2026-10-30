import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/heart_button.dart';

/// Bật tắt khoe một thẻ của mình với club. Đang khoe thì hiện ai đã thả tim
/// cho thẻ.
class ClubShareSwitch extends ConsumerStatefulWidget {
  const ClubShareSwitch({
    super.key,
    required this.clubKey,
    required this.share,
    required this.unshare,
    required this.offHint,
  });

  /// Phần sau `{uid}_` của id thẻ khoe và của tim thẻ: activityId với thẻ
  /// buổi chạy.
  final String clubKey;
  final Future<void> Function(RunNowApiClient api) share;
  final Future<void> Function(RunNowApiClient api) unshare;

  /// Dòng phụ khi chưa khoe: khoe thì club thấy gì.
  final String offHint;

  @override
  ConsumerState<ClubShareSwitch> createState() => _ClubShareSwitchState();
}

class _ClubShareSwitchState extends ConsumerState<ClubShareSwitch> {
  bool _busy = false;

  Future<void> _set(bool share) async {
    setState(() => _busy = true);
    final api = ref.read(runNowApiClientProvider);
    try {
      if (share) {
        await widget.share(api);
      } else {
        await widget.unshare(api);
      }
    } catch (error) {
      debugPrint('Không đổi được khoe thẻ: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            share
                ? 'Không khoe được thẻ: $error'
                : 'Không thôi khoe được: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(cardSharedProvider(widget.clubKey));
    if (shared.error case final error?) {
      debugPrint('Không tải được trạng thái khoe thẻ: $error');
      return TextButton(
        onPressed: () => ref.invalidate(cardSharedProvider(widget.clubKey)),
        child: const Text('Không tải được trạng thái khoe. Chạm để thử lại.'),
      );
    }
    final on = shared.value ?? false;
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.groups_rounded),
          title: const Text(
            'Khoe với club',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            on ? 'Cả club đang thấy thẻ này ở trang Kèo.' : widget.offHint,
            style: TextStyle(color: muted, fontSize: 12.5),
          ),
          value: on,
          onChanged: _busy || shared.isLoading ? null : _set,
        ),
        if (on && uid != null)
          Align(
            alignment: Alignment.centerLeft,
            child: HeartCheerers(
              target: cardHeartTarget(uid, widget.clubKey),
              label: 'thả tim',
            ),
          ),
      ],
    );
  }
}
