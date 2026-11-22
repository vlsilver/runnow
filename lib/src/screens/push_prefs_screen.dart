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

class _PushPrefsScreenState extends ConsumerState<PushPrefsScreen> {
  List<PushPrefGroup>? _groups;
  Object? _loadError;
  bool _saving = false;
  PushPermission? _permission;

  @override
  void initState() {
    super.initState();
    _load();
    _readPermission();
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
    final push = ref.read(pushControllerProvider);
    if (push == null) return;
    final permission = await push.permission();
    if (mounted) setState(() => _permission = permission);
  }

  Future<void> _ask() async {
    final push = ref.read(pushControllerProvider);
    if (push == null) return;
    final permission = await push.ask();
    if (mounted) setState(() => _permission = permission);
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
        const SnackBar(content: Text('Chưa lưu được, thử lại sau.')),
      );
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
