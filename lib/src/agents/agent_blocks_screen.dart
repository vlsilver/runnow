import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Người mình đã chặn trong phòng bot. Chặn nằm ở menu nhấn giữ tin trong
/// phòng; bỏ chặn ở đây. Mở lại phòng thì tin của họ hiện lại.
class AgentBlocksScreen extends ConsumerStatefulWidget {
  const AgentBlocksScreen({super.key});

  @override
  ConsumerState<AgentBlocksScreen> createState() => _AgentBlocksScreenState();
}

class _AgentBlocksScreenState extends ConsumerState<AgentBlocksScreen> {
  bool _busy = false;

  Future<void> _unblock(AgentBlocked blocked) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(runNowApiClientProvider).unblockAgentRoomUser(blocked.uid);
      ref.invalidate(agentBlocksProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RunNowApiException
                  ? error.message
                  : 'Không bỏ chặn được, thử lại sau.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final blocks = ref.watch(agentBlocksProvider);
    final data = blocks.value;
    final Widget body;
    if (data == null) {
      body = blocks.hasError
          ? Center(
              child: TextButton(
                onPressed: () => ref.invalidate(agentBlocksProvider),
                child: const Text('Không tải được. Chạm để thử lại.'),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (data.isEmpty) {
      body = Center(
        child: Text(
          'Bạn chưa chặn ai.',
          style: TextStyle(color: palette.textMuted),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final b in data)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_off_outlined),
              title: Text(b.name.isEmpty ? 'Thành viên' : b.name),
              trailing: TextButton(
                onPressed: _busy ? null : () => _unblock(b),
                child: const Text('Bỏ chặn'),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Người đã chặn'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: body,
    );
  }
}
