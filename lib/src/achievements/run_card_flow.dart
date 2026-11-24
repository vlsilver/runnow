import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/run_card_art_steps.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowAchievementTokens;

/// Mở màn lật thẻ của buổi [run]. Đẩy lên navigator gốc để màn phủ cả thanh
/// tab.
Future<void> showRunCardFlow(BuildContext context, ActivitySummary run) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => RunCardFlowScreen(run: run),
    ),
  );
}

/// Mở thẳng các bước vẽ nền cho [card] đã lật.
Future<void> showRunCardDraw(BuildContext context, RunCard card) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => RunCardDrawScreen(card: card),
    ),
  );
}

/// Lật một thẻ rồi đi tiếp từng bước trên chính thẻ đó. Thẻ chỉ chủ buổi đọc
/// được (rule Firestore), nên màn này chỉ mở trên buổi của chính mình.
class RunCardFlowScreen extends ConsumerWidget {
  const RunCardFlowScreen({super.key, required this.run});

  final ActivitySummary run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner =
        ref.watch(userProfileProvider).asData?.value?.displayName ??
        '3i member';
    return _CardStage(
      child: RunCardPanel(
        activity: run,
        owner: owner,
        onDone: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Các bước vẽ nền cho thẻ đã có, mở từ màn xem thẻ. Id thẻ là id buổi chạy.
/// Không đọc được buổi (đã xoá) thì vẫn vẽ được từ ảnh tải lên.
class RunCardDrawScreen extends ConsumerWidget {
  const RunCardDrawScreen({super.key, required this.card});

  final RunCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner =
        ref.watch(userProfileProvider).asData?.value?.displayName ??
        '3i member';
    final detail = ref.watch(activityDetailProvider(card.id));
    return _CardStage(
      child: detail.isLoading
          ? const Center(child: CircularProgressIndicator(color: _T.titleGold2))
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              child: RunCardArtSteps(
                card: card,
                photos: detail.asData?.value.summary.photos ?? const [],
                owner: owner,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
    );
  }
}

class _CardStage extends StatelessWidget {
  const _CardStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.shade,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_T.graphite2, _T.field, _T.shade],
          ),
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}
