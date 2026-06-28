import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(userProfileProvider);
    final profileLoading = profileState.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );
    final stravaConnected = ref.watch(stravaConnectionProvider);
    if (!profileLoading && !stravaConnected) {
      final strava = ref.watch(stravaAuthProvider);
      return Scaffold(
        appBar: AppBar(title: const Text('Nhật ký')),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _JournalConnectStravaCard(
              loading: strava.loading,
              errorMessage: strava.errorMessage,
              onConnect: ref.read(stravaAuthProvider).connect,
            ),
          ],
        ),
      );
    }
    final activities = ref.watch(activitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(syncControllerProvider).startBackgroundSync(force: true);
        },
        child: activities.when(
          data: (items) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: items.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Chưa có hoạt động.')),
                    ),
                  ]
                : [
                    for (var index = 0; index < items.length; index++)
                      ActivityTile(activity: items[index], sequence: index + 1),
                  ],
          ),
          error: (error, stack) => ListView(
            children: [
              Center(
                child: Text(
                  'Đang dùng dữ liệu offline hoặc không thể tải: $error',
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _JournalConnectStravaCard extends StatelessWidget {
  const _JournalConnectStravaCard({
    required this.loading,
    required this.errorMessage,
    required this.onConnect,
  });

  final bool loading;
  final String? errorMessage;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: [palette.glassStart, palette.glassEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_run, color: palette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'NHẬT KÝ STRAVA',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Kết nối Strava để tải nhật ký chạy và đi bộ vào RunNow.',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onConnect,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(loading ? 'Đang kết nối...' : 'Kết nối Strava'),
            ),
          ),
        ],
      ),
    );
  }
}
