import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/auth.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Nút đăng nhập dùng chung cho cả Google lẫn Apple — cùng chiều cao, cùng
/// bo góc, chỉ khác màu. Giữ hai nút đồng cỡ là yêu cầu của Apple: nút Sign
/// in with Apple không được kém nổi bật hơn lựa chọn đăng nhập khác.
class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.iconSize = 22,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          disabledForegroundColor: foreground.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize),
            const SizedBox(width: 8),
            // Flexible + ellipsis: chữ dài ra khi người dùng bật cỡ chữ lớn
            // trong trợ năng sẽ co lại thay vì tràn ngang khỏi nút.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final String _quote;

  static const _quotes = [
    'Một bước nhỏ hôm nay, một bản lĩnh lớn ngày mai.',
    'Không cần nhanh nhất. Chỉ cần không biến mất.',
    'Kỷ luật là thứ chạy cùng bạn khi động lực nghỉ ngơi.',
    'Mỗi km là một phiếu bầu cho phiên bản tốt hơn của bạn.',
    'Chạy không phải để trốn đi. Chạy để quay lại mạnh hơn.',
    'Consistency beats intensity.',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _quote = _quotes[math.Random().nextInt(_quotes.length)];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Center(
            // Nút đăng nhập rộng bằng cả màn hình trên desktop trông rất tệ
            // và khó bấm — khoá bề ngang lại quanh cỡ một cột điện thoại.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chính là file icon đang ship (assets/brand/3i-mark.png là
                    // bản sao của AppIcon 1024), bo góc theo tỉ lệ squircle của
                    // iOS để trông đúng như icon người dùng thấy ngoài màn hình
                    // chính — thay vì cắt tròn thành hình khác.
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: palette.secondary.withValues(
                                  alpha: 0.16 + _controller.value * 0.16,
                                ),
                                blurRadius: 30,
                                spreadRadius: -6,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/brand/3i-mark.png',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    // Logo đã là chữ "3i" rồi nên không lặp lại bằng text nữa;
                    // dòng dưới đóng vai trò wordmark, giải nghĩa ba chữ I.
                    const SizedBox(height: 16),
                    Text(
                      'INTENT · IMPROVE · INVOLVE',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _quote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.tertiary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Hai nút cùng kiểu, cùng cỡ — Apple yêu cầu nút Sign in
                    // with Apple không được kém nổi bật hơn nút đăng nhập khác.
                    _SignInButton(
                      label: 'Tiếp tục với Google',
                      icon: Icons.g_mobiledata_rounded,
                      iconSize: 30,
                      background: palette.ink,
                      foreground: palette.background,
                      onPressed: controller.loading ? null : controller.signIn,
                    ),
                    if (AuthController.appleSignInAvailable) ...[
                      const SizedBox(height: 10),
                      _SignInButton(
                        label: 'Tiếp tục với Apple',
                        icon: Icons.apple,
                        iconSize: 22,
                        // Theo spec của Apple: nền đen trên giao diện sáng,
                        // nền trắng trên giao diện tối.
                        background: isDark ? Colors.white : Colors.black,
                        foreground: isDark ? Colors.black : Colors.white,
                        onPressed: controller.loading
                            ? null
                            : controller.signInWithApple,
                      ),
                    ],
                    if (controller.loading) ...[
                      const SizedBox(height: 16),
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        controller.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
