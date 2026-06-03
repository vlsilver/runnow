import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(stravaAuthProvider);
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
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.red,
                    child: Icon(
                      Icons.directions_run,
                      size: 46,
                      color: Colors.white,
                    ),
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
                  const Text(
                    'Kết nối Strava để xem nhật ký chạy và đi bộ trong 12 tháng gần nhất.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: controller.loading ? null : controller.connect,
                      icon: const Icon(Icons.link),
                      label: Text(
                        controller.loading
                            ? 'Đang kết nối...'
                            : 'Kết nối Strava',
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
