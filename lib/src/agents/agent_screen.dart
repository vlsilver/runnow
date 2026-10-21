import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Tab MyBot: thẻ bot của mình, tin mới trong phòng bot, bộ nhớ và những điều
/// bot tự học. Tạo và sửa tên, tính cách nằm ở màn `/agent/setup`.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  bool _busy = false;

  /// Chạy một thao tác ghi, báo lỗi nếu có, rồi đọc lại hồ sơ.
  Future<void> _run(Future<void> Function(RunNowApiClient api) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(runNowApiClientProvider));
      ref.invalidate(agentMeProvider);
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

  /// Mở màn con; quay về thì đọc lại hồ sơ, vì bot có thể vừa nhớ hay quên
  /// gì, và tin mới trong phòng.
  Future<void> _open(String path) async {
    await context.push(path);
    if (!mounted) return;
    ref.invalidate(agentMeProvider);
    ref.invalidate(agentRoomPreviewProvider);
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
    final yes = await _confirm(
      title: 'Xoá mục nhớ?',
      content: memory.text,
      action: 'Xoá',
    );
    if (yes) await _run((api) => api.deleteAgentMemory(memory.id));
  }

  Future<void> _forgetLearned(AgentLearnedFact fact) async {
    final yes = await _confirm(
      title: 'Cho bot quên điều này?',
      content: fact.text,
      action: 'Quên',
    );
    if (yes) await _run((api) => api.deleteAgentLearned(fact.id));
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(agentMeProvider);
    final data = me.value;
    final agent = data?.agent;
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
    } else if (!data.enabled || agent == null) {
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
      body = ListView(
        // Chừa chỗ cho thanh tab nổi phía dưới.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (agent.created) ...[
            _BotHeroCard(
              agent: agent,
              memoryCount: data.memories.length,
              memoryLimit: data.memoryLimit,
              learnedCount: data.learned.length,
              onChat: () => _open('/agent/dm'),
              onRoom: () => _open('/agent/room'),
            ),
            const SizedBox(height: 16),
            _RoomPreviewCard(onOpen: () => _open('/agent/room')),
            const SizedBox(height: 22),
            _MemorySection(
              memories: data.memories,
              limit: data.memoryLimit,
              busy: _busy,
              onAdd: () => _editMemory(null),
              onEdit: _editMemory,
              onDelete: _deleteMemory,
            ),
          ] else
            _CreateBotCard(onCreate: () => _open('/agent/setup')),
          const SizedBox(height: 22),
          // Bot tự học cả khi chưa tạo bot (vd. trí nhớ cũ của 3i), nên mục
          // này luôn hiện để người dùng xem và xoá được.
          _LearnedSection(
            learned: data.learned,
            busy: _busy,
            onForget: _forgetLearned,
            onGroupFacts: () => _open('/agent/group-facts'),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyBot'),
        actions: [
          if (agent?.created ?? false)
            IconButton(
              tooltip: 'Sửa bot',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _open('/agent/setup'),
            ),
        ],
      ),
      body: body,
    );
  }
}

/// Thẻ tối đầu tab, cùng cách tô màu với thẻ điểm sức mạnh ở Hành Trình.
class _BotHeroCard extends StatelessWidget {
  const _BotHeroCard({
    required this.agent,
    required this.memoryCount,
    required this.memoryLimit,
    required this.learnedCount,
    required this.onChat,
    required this.onRoom,
  });

  final AgentProfile agent;
  final int memoryCount;
  final int memoryLimit;
  final int learnedCount;
  final VoidCallback onChat;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final dark = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    return _HeroShell(
      palette: dark,
      children: [
        Row(
          children: [
            _BotOrb(palette: dark, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (agent.persona.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      agent.persona,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark.textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: dark.ink.withValues(alpha: 0.12)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _HeroStat(
                palette: dark,
                value: '$memoryCount',
                suffix: ' /$memoryLimit',
                label: 'mục nhớ',
              ),
            ),
            Expanded(
              child: _HeroStat(
                palette: dark,
                value: '$learnedCount',
                label: 'điều tự học',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onChat,
                style: FilledButton.styleFrom(
                  backgroundColor: dark.accent,
                  foregroundColor: RunNowThemeTokens.lightInk,
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat riêng'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRoom,
                style: OutlinedButton.styleFrom(
                  foregroundColor: dark.ink,
                  side: BorderSide(color: dark.ink.withValues(alpha: 0.28)),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Phòng bot'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Thẻ đầu tab khi chưa có bot.
class _CreateBotCard extends StatelessWidget {
  const _CreateBotCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final dark = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    return _HeroShell(
      palette: dark,
      children: [
        _BotOrb(palette: dark, size: 56),
        const SizedBox(height: 14),
        Text(
          'Tạo bot của riêng bạn',
          style: TextStyle(
            color: dark.ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Đặt tên và tính cách cho bot. Kể cho bot nghe về bạn, bot sẽ thay '
          'bạn nói chuyện với bot của các thành viên khác.',
          style: TextStyle(color: dark.textMuted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            backgroundColor: dark.accent,
            foregroundColor: RunNowThemeTokens.lightInk,
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Tạo bot'),
        ),
      ],
    );
  }
}

class _HeroShell extends StatelessWidget {
  const _HeroShell({required this.palette, required this.children});

  final RunNowPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.tint.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _BotOrb extends StatelessWidget {
  const _BotOrb({required this.palette, required this.size});

  final RunNowPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: LinearGradient(
          colors: [palette.tertiary, palette.accentDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.palette,
    required this.value,
    required this.label,
    this.suffix,
  });

  final RunNowPalette palette;
  final String value;
  final String? suffix;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: value,
            children: [
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          style: TextStyle(
            color: palette.ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Hai tin mới nhất trong phòng bot, đọc một lần mỗi lần mở tab.
class _RoomPreviewCard extends ConsumerWidget {
  const _RoomPreviewCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final preview = ref.watch(agentRoomPreviewProvider);
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final muted = TextStyle(color: palette.textMuted, fontSize: 14);
    final Widget content;
    if (preview.hasError && !preview.hasValue) {
      content = InkWell(
        onTap: () => ref.invalidate(agentRoomPreviewProvider),
        child: Text('Không tải được phòng bot. Chạm để thử lại.', style: muted),
      );
    } else if (!preview.hasValue) {
      content = const LinearProgressIndicator(minHeight: 2);
    } else if (preview.value!.isEmpty) {
      content = Text('Phòng chưa có tin nào.', style: muted);
    } else {
      content = Column(
        children: [
          for (final m in preview.value!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomPreviewLine(message: m, myUid: myUid),
            ),
        ],
      );
    }
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('Phòng bot'),
            const SizedBox(height: 12),
            content,
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: palette.accentDeep,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Row(
                children: [
                  Expanded(child: Text('Vào phòng')),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPreviewLine extends StatelessWidget {
  const _RoomPreviewLine({required this.message, required this.myUid});

  final AgentRoomMessage message;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = message.name.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: message.fromAgent ? palette.ink : palette.accentDeep,
            // Bot thì vuông bo góc, người thì tròn, như trong phòng.
            borderRadius: BorderRadius.circular(message.fromAgent ? 10 : 15),
          ),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              color: palette.background,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agentRoomSenderLabel(message, myUid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                message.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemorySection extends StatelessWidget {
  const _MemorySection({
    required this.memories,
    required this.limit,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AgentMemory> memories;
  final int limit;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<AgentMemory> onEdit;
  final ValueChanged<AgentMemory> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final full = memories.length >= limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          'Bot biết gì về bạn',
          trailing: '${memories.length}/$limit',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            'Bot dùng mọi mục ở đây khi nói trong phòng bot, nơi các thành '
            'viên khác cùng đọc. Đừng để chuyện riêng tư trong bộ nhớ.',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ),
        _Card(
          child: Column(
            children: [
              if (memories.isEmpty)
                _EmptyRow(
                  'Chưa có gì. Thêm tay, hoặc vào Chat riêng kể cho bot nghe.',
                ),
              for (final m in memories) ...[
                _FactRow(
                  text: m.text,
                  source: m.fromChat ? 'Bot ghi khi chat' : 'Bạn thêm',
                  onTap: busy ? null : () => onEdit(m),
                  action: IconButton(
                    tooltip: 'Xoá',
                    icon: const Icon(Icons.delete_outline),
                    color: palette.textMuted,
                    onPressed: busy ? null : () => onDelete(m),
                  ),
                ),
                const _RowDivider(),
              ],
              if (memories.isNotEmpty || !full)
                ListTile(
                  enabled: !busy && !full,
                  leading: Icon(Icons.add_rounded, color: palette.accentDeep),
                  title: Text(
                    full ? 'Bộ nhớ đã đầy' : 'Thêm điều cần nhớ',
                    style: TextStyle(
                      color: full ? palette.textMuted : palette.accentDeep,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: onAdd,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LearnedSection extends StatelessWidget {
  const _LearnedSection({
    required this.learned,
    required this.busy,
    required this.onForget,
    required this.onGroupFacts,
  });

  final List<AgentLearnedFact> learned;
  final bool busy;
  final ValueChanged<AgentLearnedFact> onForget;
  final VoidCallback onGroupFacts;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Bot tự học về bạn', trailing: '${learned.length}'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            'Bot rút ra từ tin bạn nói trong phòng bot và group Telegram, rồi '
            'dùng khi nói chuyện với bạn và mọi người. Mục nào sai hay bạn '
            'không muốn bot nhớ thì cho bot quên.',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ),
        _Card(
          child: Column(
            children: [
              if (learned.isEmpty)
                const _EmptyRow('Bot chưa học được gì về bạn.'),
              for (final f in learned) ...[
                _FactRow(
                  text: f.text,
                  source: f.migrated ? 'Từ trí nhớ cũ của 3i' : 'Bot tự học',
                  action: TextButton(
                    onPressed: busy ? null : () => onForget(f),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textMuted,
                    ),
                    child: const Text('Quên'),
                  ),
                ),
                const _RowDivider(),
              ],
              ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: const Text(
                  'Bot biết gì về nhóm',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onGroupFacts,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.runNowPalette.glassStart,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Nhãn mục kiểu chữ hoa nhỏ, giống nhãn mục ở Cài đặt.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                color: palette.accentDeep,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.text,
    required this.source,
    required this.action,
    this.onTap,
  });

  final String text;
  final String source;
  final Widget action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        source,
        style: TextStyle(
          color: context.runNowPalette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      trailing: action,
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: context.runNowPalette.textMuted),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      color: context.runNowPalette.border.withValues(alpha: 0.6),
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
