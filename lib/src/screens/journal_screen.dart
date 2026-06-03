import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/activity_tile.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(syncControllerProvider).startBackgroundSync();
        },
        child: activities.when(
          data: (items) => ListView(
            padding: const EdgeInsets.all(16),
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
