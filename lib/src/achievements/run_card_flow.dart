import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        child: SafeArea(
          child: RunCardPanel(
            activity: run,
            owner: owner,
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
