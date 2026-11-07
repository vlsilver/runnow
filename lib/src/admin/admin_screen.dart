import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/admin/agent_config_screen.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Cấu hình trang admin. null nghĩa là người đang đăng nhập không phải admin,
/// app chỉ cần ẩn tab. Lỗi khác (mạng, 5xx) vẫn ném ra để màn báo lỗi.
final adminSettingsProvider = FutureProvider<AdminSettings?>(
  retry: (_, _) => null,
  (ref) async {
    final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
    if (uid == null) return null;
    try {
      return await ref.watch(runNowApiClientProvider).getAdminSettings();
    } on RunNowApiException catch (error) {
      if (error.code == 'not_admin') return null;
      rethrow;
    }
  },
);

const _roles = [
  (
    id: 'admin',
    title: 'Admin',
    hint:
        'Chạy ván Ma Sói, cho bot quên ký ức nhóm, sửa trang này. Admin dùng '
        'được cả bot cá nhân.',
  ),
  (id: 'tester', title: 'Tester Ma Sói', hint: 'Vào được ván Ma Sói thử.'),
  (
    id: 'bot',
    title: 'Bot cá nhân trong app',
    hint:
        'Có tab MyBot với bot riêng và vào phòng bot trong app, không '
        'liên quan bot Telegram. Admin luôn có quyền này.',
  ),
];

/// Tab Admin trên web: cấp, bỏ quyền và xem Telegram đang nối vào chat nào.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(RunNowApiClient api) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(runNowApiClientProvider));
      ref.invalidate(adminSettingsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RunNowApiException
                  ? error.message
                  : 'Không lưu được, thử lại sau.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _grant(String role, List<MemberProfile> candidates) async {
    final uid = await showDialog<String>(
      context: context,
      builder: (context) => _MemberPicker(members: candidates),
    );
    if (uid != null) await _run((api) => api.grantRole(role, uid));
  }

  Future<void> _revoke(
    String role,
    String title,
    String name,
    String uid,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bỏ quyền $title của $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ quyền'),
          ),
        ],
      ),
    );
    if (yes == true) await _run((api) => api.revokeRole(role, uid));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final settings = ref.watch(adminSettingsProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final me = ref.watch(firebaseUserProvider).value?.uid;
    final names = {for (final m in members) m.uid: m.displayName};
    final data = settings.value;
    final Widget body;
    if (data == null) {
      body = Center(
        child: settings.isLoading
            ? const CircularProgressIndicator()
            : settings.hasError
            ? TextButton(
                onPressed: () => ref.invalidate(adminSettingsProvider),
                child: const Text('Không tải được. Chạm để thử lại.'),
              )
            : const Text('Chỉ admin xem được trang này.'),
      );
    } else {
      final heading = TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: palette.ink,
      );
      final muted = TextStyle(color: palette.textMuted);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final role in _roles) ...[
            Row(
              children: [
                Expanded(child: Text(role.title, style: heading)),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _grant(role.id, [
                          for (final m in members)
                            if (!data.uidsOf(role.id).contains(m.uid)) m,
                        ]),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm'),
                ),
              ],
            ),
            Text(role.hint, style: muted),
            if (data.uidsOf(role.id).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Chưa có ai.', style: muted),
              ),
            for (final uid in data.uidsOf(role.id))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(names[uid] ?? uid),
                subtitle: names[uid] == null ? null : Text(uid),
                // Không tự bỏ quyền admin, backend cũng chặn.
                trailing: role.id == 'admin' && uid == me
                    ? null
                    : IconButton(
                        tooltip: 'Bỏ quyền',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _busy
                            ? null
                            : () => _revoke(
                                role.id,
                                role.title,
                                names[uid] ?? uid,
                                uid,
                              ),
                      ),
              ),
            const SizedBox(height: 24),
          ],
          Text('Bot cá nhân', style: heading),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Trần và giá'),
            subtitle: const Text('Chi phí hôm nay, trần, số câu, giá model'),
            trailing: const Icon(Icons.chevron_right),
            // Push trong nhánh /admin, khỏi thêm route chỉ admin web dùng.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AgentConfigScreen(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Telegram', style: heading),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Group bot đọc'),
            subtitle: SelectableText(
              data.chatId.isEmpty ? 'Chưa cấu hình' : data.chatId,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bot'),
            subtitle: SelectableText(
              data.botUsername.isEmpty
                  ? 'Chưa cấu hình'
                  : '@${data.botUsername}',
            ),
          ),
          Text(
            'Token bot nằm ở Secret Manager, chỉ service bot đọc được, nên '
            'trang này không xem hay sửa token. Chat ID là chỗ lưu lịch sử và '
            'ký ức của group, đổi nó phải chuyển dữ liệu theo, nên vẫn đổi '
            'bằng deploy.',
            style: muted,
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Admin'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _MemberPicker extends StatefulWidget {
  const _MemberPicker({required this.members});

  final List<MemberProfile> members;

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final m in widget.members)
        if (query.isEmpty || m.displayName.toLowerCase().contains(query)) m,
    ];
    return AlertDialog(
      title: const Text('Chọn thành viên'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Tìm theo tên'),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final m in shown)
                    ListTile(
                      title: Text(m.displayName),
                      onTap: () => Navigator.of(context).pop(m.uid),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
      ],
    );
  }
}
