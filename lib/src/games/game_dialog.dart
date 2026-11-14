import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/theme.dart';

/// Popup hỏi lại của màn Ma Sói, trả true khi người chơi đồng ý. Không truyền
/// [confirmLabel] thì popup chỉ để báo, có mỗi nút [cancelLabel].
///
/// Popup luôn dựng theme trăng thay vì đọc từ [context]: route của dialog nằm
/// ngoài Theme của màn, và context của State màn ván cũng ở phía trên Theme đó.
Future<bool> showGameConfirm(
  BuildContext context, {
  required String title,
  required Widget body,
  required String cancelLabel,
  String? confirmLabel,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    barrierColor: context.moonlit.page.withValues(alpha: 0.8),
    builder: (_) => GameThemed(
      moonlit: true,
      child: _GameConfirm(
        title: title,
        body: body,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
      ),
    ),
  );
  return answer ?? false;
}

class _GameConfirm extends StatelessWidget {
  const _GameConfirm({
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final Widget body;
  final String cancelLabel;
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    final confirm = confirmLabel;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: context.runNowPalette.radius(24),
            border: Border.all(color: context.moonlit.borderStrong),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [context.moonlit.heroTop, context.moonlit.panelBottom],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: gameTitleFont,
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: context.moonlit.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: body)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(cancelLabel),
                      ),
                    ),
                    if (confirm != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(confirm),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
