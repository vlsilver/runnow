import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
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
    final controller = ref.watch(googleAuthProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: GlassPanel(
              padding: const EdgeInsets.all(28),
              gradient: const LinearGradient(
                colors: [Color(0xf207172b), Color(0xd4062442)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final pulse = 0.92 + (_controller.value * 0.12);
                      return Transform.scale(
                        scale: pulse,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 106,
                              height: 106,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.blueGlow.withValues(
                                    alpha: 0.18 + _controller.value * 0.28,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.blueGlow.withValues(
                                      alpha: 0.20 + _controller.value * 0.22,
                                    ),
                                    blurRadius: 34,
                                    spreadRadius: -8,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 82,
                              height: 82,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [AppColors.red, AppColors.redDeep],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.directions_run,
                                size: 46,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'RunNow',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'YOUR TRAINING SPACE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _quote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Đăng nhập để tham gia cộng đồng chạy. Kết nối Strava trong Cài đặt để đồng bộ hoạt động.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.74),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: controller.loading ? null : controller.signIn,
                      icon: const Icon(Icons.login),
                      label: Text(
                        controller.loading
                            ? 'Đang đăng nhập...'
                            : 'Đăng nhập Google',
                      ),
                    ),
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(controller.errorMessage!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
