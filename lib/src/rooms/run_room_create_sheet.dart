import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Giới hạn khớp backend (`run_rooms.go`): tên 1..60, 2..20 người, mật khẩu
/// 4..24, hẹn trước tối đa 7 ngày. Backend vẫn kiểm lại, app chặn sớm cho
/// người dùng đỡ gửi rồi mới biết sai.
const runRoomTitleMax = 60;
const runRoomMinRunners = 2;
const runRoomMaxRunners = 20;
const runRoomPasswordMin = 4;
const runRoomPasswordMax = 24;

/// Mở sheet tạo phòng; tạo xong thì vào màn phòng.
Future<void> showCreateRunRoomSheet(BuildContext context) async {
  final roomId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CreateRunRoomSheet(),
  );
  if (roomId == null || !context.mounted) return;
  context.push('/rooms/$roomId');
}

class CreateRunRoomSheet extends ConsumerStatefulWidget {
  const CreateRunRoomSheet({super.key});

  @override
  ConsumerState<CreateRunRoomSheet> createState() => _CreateRunRoomSheetState();
}

class _CreateRunRoomSheetState extends ConsumerState<CreateRunRoomSheet> {
  final _title = TextEditingController();
  final _password = TextEditingController();
  RunRoomPrivacy _privacy = RunRoomPrivacy.public;
  int _maxRunners = 8;
  DateTime? _startsAt;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Lỗi nhập liệu đầu tiên, null khi gửi được.
  String? _validate() {
    final title = _title.text.trim();
    if (title.isEmpty) return 'Đặt tên cho phòng.';
    if (title.characters.length > runRoomTitleMax) {
      return 'Tên phòng tối đa $runRoomTitleMax ký tự.';
    }
    if (_privacy == RunRoomPrivacy.password) {
      final length = _password.text.characters.length;
      if (length < runRoomPasswordMin || length > runRoomPasswordMax) {
        return 'Mật khẩu từ $runRoomPasswordMin đến $runRoomPasswordMax ký tự.';
      }
    }
    return null;
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 6)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now),
    );
    if (time == null) return;
    setState(
      () => _startsAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _submit() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(runNowApiClientProvider)
          .createRunRoom(
            title: _title.text.trim(),
            privacy: _privacy.value,
            maxRunners: _maxRunners,
            password: _privacy == RunRoomPrivacy.password
                ? _password.text
                : null,
            startsAt: _startsAt,
          );
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) setState(() => _error = runRoomErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final starts = _startsAt;
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        gradient: LinearGradient(
          colors: [palette.glassStart, palette.glassEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Mở phòng chạy',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: runRoomTitleMax,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên phòng',
                  hintText: 'VD: Chạy hồ Tây sáng thứ 7',
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<RunRoomPrivacy>(
                segments: [
                  for (final p in RunRoomPrivacy.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_privacy},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _privacy = value.single),
              ),
              const SizedBox(height: 6),
              Text(switch (_privacy) {
                RunRoomPrivacy.public =>
                  'Ai cũng thấy phòng ở Trang chủ và vào thẳng.',
                RunRoomPrivacy.private =>
                  'Chỉ người có link mới thấy; bạn duyệt từng người.',
                RunRoomPrivacy.password =>
                  'Chỉ người có link và mật khẩu mới vào được.',
              }, style: TextStyle(color: onSurface.withValues(alpha: 0.65))),
              if (_privacy == RunRoomPrivacy.password) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  maxLength: runRoomPasswordMax,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu'),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tối đa',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bớt',
                    onPressed: _maxRunners > runRoomMinRunners
                        ? () => setState(() => _maxRunners--)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Text(
                    '$_maxRunners người',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    tooltip: 'Thêm',
                    onPressed: _maxRunners < runRoomMaxRunners
                        ? () => setState(() => _maxRunners++)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      starts == null
                          ? 'Chạy ngay bây giờ'
                          : 'Hẹn ${DateFormat('HH:mm, dd/MM').format(starts)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (starts != null)
                    TextButton(
                      onPressed: () => setState(() => _startsAt = null),
                      child: const Text('Chạy ngay'),
                    ),
                  TextButton(
                    onPressed: _pickStart,
                    child: const Text('Hẹn giờ'),
                  ),
                ],
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 6),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Đang mở phòng…' : 'Mở phòng'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
