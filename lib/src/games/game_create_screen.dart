import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Admin mở ván Ma Sói. Vai bật tắt được lấy từ `createOptions` của
/// `GET /v1/games`, nên thêm vai ở backend thì app không phải sửa.
class GameCreateScreen extends ConsumerStatefulWidget {
  const GameCreateScreen({super.key});

  @override
  ConsumerState<GameCreateScreen> createState() => _GameCreateScreenState();
}

class _GameCreateScreenState extends ConsumerState<GameCreateScreen> {
  final _roles = <String, bool>{};
  DateTime? _deadline;
  bool _testMode = false;
  final _chatId = TextEditingController();
  final _threadId = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _chatId.dispose();
    _threadId.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _deadline ?? now.add(const Duration(days: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _deadline = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _create(GameList list) async {
    final threadText = _threadId.text.trim();
    final threadId = threadText.isEmpty ? null : int.tryParse(threadText);
    if (threadText.isNotEmpty && threadId == null) {
      setState(() => _error = 'ID topic phải là số.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(runNowApiClientProvider)
          .createGame(
            roles: {
              for (final option in list.roleOptions)
                option.key: _roles[option.key] ?? option.defaultOn,
            },
            registrationDeadline: _deadline,
            testMode: _testMode,
            chatId: _testMode ? _chatId.text.trim() : null,
            threadId: threadId,
          );
      ref.invalidate(gameListProvider);
      if (mounted) context.pushReplacement('/games/$id');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = error is RunNowApiException
            ? error.message
            : 'Không tạo được ván, thử lại sau.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final list = ref.watch(gameListProvider);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Mở ván Ma Sói'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: switch (list) {
        AsyncData(value: final list?) when list.canCreate => _form(list),
        AsyncData() => const _Message('Chỉ admin mở được ván Ma Sói.'),
        AsyncError() => _Message(
          'Chưa đọc được cấu hình ván.',
          onRetry: () => ref.invalidate(gameListProvider),
        ),
        _ => const RunNowLoading(label: 'Đang tải'),
      },
    );
  }

  Widget _form(GameList list) {
    final deadline = _deadline;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final option in list.roleOptions)
                SwitchListTile(
                  title: Text(option.label),
                  value: _roles[option.key] ?? option.defaultOn,
                  onChanged: _working
                      ? null
                      : (on) => setState(() => _roles[option.key] = on),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              ListTile(
                title: const Text('Hạn đăng ký'),
                subtitle: Text(
                  deadline == null
                      ? 'Không hạn, admin tự bấm bắt đầu'
                      : DateFormat('HH:mm dd/MM').format(deadline),
                ),
                trailing: deadline == null
                    ? const Icon(Icons.event_rounded)
                    : IconButton(
                        tooltip: 'Bỏ hạn',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _working
                            ? null
                            : () => setState(() => _deadline = null),
                      ),
                onTap: _working ? null : _pickDeadline,
              ),
              SwitchListTile(
                title: const Text('Ván thử'),
                subtitle: const Text(
                  'Chạy ở group test, chỉ admin và người test thấy',
                ),
                value: _testMode,
                onChanged: _working
                    ? null
                    : (on) => setState(() => _testMode = on),
              ),
              if (_testMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _chatId,
                    enabled: !_working,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chat ID group test',
                      hintText: '-100…',
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _threadId,
                  enabled: !_working,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ID topic (không bắt buộc)',
                    helperText: 'Bỏ trống thì bot đăng vào General',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _working ? null : () => _create(list),
          child: Text(_working ? 'Đang mở ván…' : 'Mở ván'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ],
        ),
      ),
    );
  }
}
