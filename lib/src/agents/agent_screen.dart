import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// "Bot của tôi": tạo bot, sửa tên và tính cách, xem và sửa bộ nhớ, rồi vào
/// chat riêng hay phòng bot.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _name = TextEditingController();
  final _persona = TextEditingController();

  /// Hồ sơ đã đổ vào ô nhập; đọc lại sau khi lưu thì không ghi đè chữ đang gõ.
  AgentProfile? _filled;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _persona.dispose();
    super.dispose();
  }

  void _fill(AgentProfile profile) {
    if (_filled != null) return;
    _filled = profile;
    _name.text = profile.name;
    _persona.text = profile.persona;
  }

  /// Chạy một thao tác ghi, báo lỗi nếu có, rồi đọc lại hồ sơ.
  Future<bool> _run(Future<void> Function(RunNowApiClient api) action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action(ref.read(runNowApiClientProvider));
      ref.invalidate(agentMeProvider);
      return true;
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
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    final persona = _persona.text.trim();
    final ok = await _run(
      (api) => api.saveAgentProfile(name: name, persona: persona),
    );
    if (ok) _filled = AgentProfile(name: name, persona: persona, created: true);
    if (ok && mounted) setState(() {});
  }

  /// Mở chat; quay về thì đọc lại hồ sơ, vì bot có thể vừa nhớ hay quên gì.
  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) ref.invalidate(agentMeProvider);
  }

  Future<void> _editMemory(AgentMemory? memory) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _MemoryDialog(initial: memory?.text ?? ''),
    );
    if (text == null || text.trim().isEmpty) return;
    await _run(
      (api) => memory == null
          ? api.addAgentMemory(text.trim())
          : api.updateAgentMemory(memory.id, text.trim()),
    );
  }

  Future<void> _deleteMemory(AgentMemory memory) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá mục nhớ?'),
        content: Text(memory.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (yes == true) await _run((api) => api.deleteAgentMemory(memory.id));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final me = ref.watch(agentMeProvider);
    final data = me.value;
    final Widget body;
    if (data == null) {
      body = me.hasError
          ? Center(
              child: TextButton(
                onPressed: () => ref.invalidate(agentMeProvider),
                child: const Text('Không tải được bot. Chạm để thử lại.'),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (!data.enabled || data.agent == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Bot cá nhân đang thử nghiệm với vài thành viên.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      final agent = data.agent!;
      _fill(agent);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (agent.created) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open('/agent/dm'),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Chat riêng'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _open('/agent/room'),
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Phòng bot'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ] else ...[
            const Text(
              'Đặt tên và tính cách cho bot. Sau đó kể cho bot nghe về bạn, '
              'bot sẽ thay bạn nói chuyện trong phòng bot với bot của các '
              'thành viên khác.',
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Tên bot'),
          ),
          TextField(
            controller: _persona,
            minLines: 3,
            maxLines: 8,
            maxLength: 1500,
            decoration: const InputDecoration(
              labelText: 'Tính cách',
              hintText: 'Vd: Nói ngắn, hay đùa, xưng "tui", mê chạy trail.',
              alignLabelWithHint: true,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _saveProfile,
              child: Text(agent.created ? 'Lưu' : 'Tạo bot'),
            ),
          ),
          if (agent.created) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Bộ nhớ (${data.memories.length}/${data.memoryLimit})',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || data.memories.length >= data.memoryLimit
                      ? null
                      : () => _editMemory(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm'),
                ),
              ],
            ),
            Text(
              'Bot dùng mọi mục ở đây khi nói trong phòng bot, nơi các thành '
              'viên khác cùng đọc. Đừng để chuyện riêng tư trong bộ nhớ.',
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 8),
            if (data.memories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chưa có gì. Thêm tay, hoặc vào Chat riêng kể cho bot nghe.',
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            for (final m in data.memories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.text),
                subtitle: Text(m.fromChat ? 'Bot ghi khi chat' : 'Bạn thêm'),
                onTap: _busy ? null : () => _editMemory(m),
                trailing: IconButton(
                  tooltip: 'Xoá',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _deleteMemory(m),
                ),
              ),
          ],
        ],
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Bot của tôi'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog({required this.initial});

  final String initial;

  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Thêm điều cần nhớ' : 'Sửa mục nhớ'),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Vd: Chủ chạy sáng thứ 7 ở hồ Tây.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
