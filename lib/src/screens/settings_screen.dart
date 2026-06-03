import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/glass.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final profile = ref.watch(userProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SettingsPanel(
            child: ListTile(
              leading: Icon(Icons.link),
              title: Text('Strava'),
              subtitle: Text('Đã kết nối Firebase Auth và Firestore.'),
            ),
          ),
          const SizedBox(height: 10),
          profile.when(
            data: (user) => _SettingsPanel(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(user?.displayName ?? 'Chưa có athlete'),
                subtitle: Text(
                  user?.lastSyncedAt == null
                      ? 'Chưa đồng bộ'
                      : 'Đồng bộ gần nhất: ${formatDate(user!.lastSyncedAt!)}',
                ),
              ),
            ),
            loading: () => const _SettingsPanel(
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Đang tải athlete...'),
              ),
            ),
            error: (error, stack) => _SettingsPanel(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Không thể tải athlete'),
                subtitle: Text('$error'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsPanel(
            child: ListTile(
              leading: sync.syncing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              title: const Text('Đồng bộ thủ công'),
              subtitle: sync.message == null ? null : Text(sync.message!),
              onTap: sync.syncing
                  ? null
                  : ref.read(syncControllerProvider).startBackgroundSync,
            ),
          ),
          const SizedBox(height: 10),
          _SettingsPanel(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Ngắt kết nối Strava'),
              onTap: ref.read(stravaAuthProvider).disconnect,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(borderRadius: 14, child: child);
  }
}
