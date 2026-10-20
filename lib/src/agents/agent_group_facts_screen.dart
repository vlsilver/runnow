import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

final agentGroupFactsProvider = FutureProvider.autoDispose<AgentGroupFacts>(
  retry: (_, _) => null,
  (ref) => ref.watch(runNowApiClientProvider).getAgentGroupFacts(),
);

/// "Bot biết gì về nhóm": điều bot tự học từ tin trong nhóm, dùng chung cho
/// mọi bot và 3i. Ai trong phòng bot cũng xem được, chỉ admin cho bot quên.
class AgentGroupFactsScreen extends ConsumerStatefulWidget {
  const AgentGroupFactsScreen({super.key});

  @override
  ConsumerState<AgentGroupFactsScreen> createState() =>
      _AgentGroupFactsScreenState();
}

class _AgentGroupFactsScreenState extends ConsumerState<AgentGroupFactsScreen> {
  bool _busy = false;

  Future<void> _forget(AgentLearnedFact fact) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cho bot quên điều này?'),
        content: Text(fact.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quên'),
          ),
        ],
      ),
    );
    if (yes != true || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(runNowApiClientProvider).deleteAgentGroupFact(fact.id);
      ref.invalidate(agentGroupFactsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RunNowApiException
                  ? error.message
                  : 'Không xoá được, thử lại sau.',
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
    final facts = ref.watch(agentGroupFactsProvider);
    final data = facts.value;
    final Widget body;
    if (data == null) {
      body = facts.hasError
          ? Center(
              child: TextButton(
                onPressed: () => ref.invalidate(agentGroupFactsProvider),
                child: const Text('Không tải được. Chạm để thử lại.'),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Bot rút ra từ tin trong phòng bot và group Telegram. Mọi bot và 3i '
            'đều dùng khi nói chuyện.',
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 8),
          if (data.facts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Bot chưa học được gì về nhóm.',
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          for (final f in data.facts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(f.text),
              subtitle: f.migrated ? const Text('Từ trí nhớ cũ của 3i') : null,
              trailing: data.canDelete
                  ? IconButton(
                      tooltip: 'Quên',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _forget(f),
                    )
                  : null,
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Bot biết gì về nhóm'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: body,
    );
  }
}
