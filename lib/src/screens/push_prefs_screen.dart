import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

/// Bật tắt thông báo theo nhóm. Nhóm và nhãn do backend trả về; app chỉ vẽ.
/// Trên cùng là quyền thông báo của máy, vì tắt ở máy thì bật nhóm cũng vô ích.
class PushPrefsScreen extends ConsumerStatefulWidget {
  const PushPrefsScreen({super.key});

  @override
  ConsumerState<PushPrefsScreen> createState() => _PushPrefsScreenState();
}

class _PushPrefsScreenState extends ConsumerState<PushPrefsScreen>
    with WidgetsBindingObserver {
  List<PushPrefGroup>? _groups;
  Object? _loadError;
  bool _saving = false;
  PushPermission? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _readPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Người dùng sang Cài đặt của máy bật lại thông báo rồi quay về.
    // Có quyền rồi thì đăng ký token luôn, vì lúc mở app chưa có quyền nên
    // chưa đăng ký.
    if (state == AppLifecycleState.resumed) _sync((push) => push.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final groups = await ref.read(runNowApiClientProvider).getPushPrefs();
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _readPermission() async {
    if (!mounted) return;
    final push = ref.read(pushControllerProvider);
    if (push == null) return;
    try {
      final permission = await push.permission();
      if (mounted) setState(() => _permission = permission);
    } catch (error, stack) {
      // Không đọc được thì giữ thẻ quyền như cũ; danh sách nhóm vẫn dùng được.
      debugPrint('push_prefs.permission_failed: $error\n$stack');
    }
  }

  Future<void> _ask() => _sync((push) => push.ask());

  /// Chạy một thao tác trả quyền rồi vẽ lại thẻ quyền. Thao tác có thể hỏng sau
  /// khi máy đã cho quyền (lúc đăng ký token), nên hỏng thì đọc lại quyền.
  Future<void> _sync(
    Future<PushPermission> Function(PushController push) action,
  ) async {
    final push = ref.read(pushControllerProvider);
    if (push == null) return;
    try {
      final permission = await action(push);
      if (mounted) setState(() => _permission = permission);
    } catch (error, stack) {
      debugPrint('push_prefs.permission_sync_failed: $error\n$stack');
      await _readPermission();
    }
  }

  Future<void> _toggle(PushPrefGroup group, bool on) async {
    final before = _groups!;
    final next = [
      for (final g in before)
        g.id == group.id ? PushPrefGroup(id: g.id, label: g.label, on: on) : g,
    ];
    setState(() {
      _groups = next;
      _saving = true;
    });
    try {
      final saved = await ref.read(runNowApiClientProvider).setPushPrefs([
        for (final g in next)
          if (!g.on) g.id,
      ]);
      if (mounted) setState(() => _groups = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _groups = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lưu bị lỗi, đã tải lại cài đặt.')),
      );
      // Lỗi có thể tới sau khi server đã lưu, nên đọc lại cho công tắc khớp.
      // Đọc xong mới mở lại công tắc, để kết quả cũ không đè lần bấm sau.
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (_permission == PushPermission.notAsked)
            _PermissionCard(
              text: 'Máy chưa cho 3i gửi thông báo.',
              action: FilledButton(
                onPressed: _ask,
                child: const Text('Bật thông báo'),
              ),
            ),
          if (_permission == PushPermission.denied)
            const _PermissionCard(
              text:
                  'Thông báo của 3i đang tắt trong Cài đặt của máy. '
                  'Bật lại ở đó thì mới nhận được.',
            ),
          if (groups != null)
            GlassPanel(
              borderRadius: 20,
              child: Column(
                children: [
                  for (final g in groups)
                    ListTile(
                      title: Text(g.label),
                      trailing: RunNowSwitch(
                        value: g.on,
                        onChanged: _saving ? null : (on) => _toggle(g, on),
                      ),
                    ),
                ],
              ),
            )
          else if (_loadError != null)
            Column(
              children: [
                const Text('Chưa tải được cài đặt thông báo.'),
                TextButton(onPressed: _load, child: const Text('Thử lại')),
              ],
            )
          else
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassPanel(
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(child: Text(text)),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}
