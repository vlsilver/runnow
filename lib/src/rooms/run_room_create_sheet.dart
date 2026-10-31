import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_route_sketch.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/screens/run_contract_route_create_screen.dart';
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

/// Số ngày chọn được tính cả hôm nay: hôm nay tới 6 ngày sau, còn trong hạn
/// 7 ngày của backend dù chọn giờ muộn nhất.
const runRoomScheduleDays = 7;

/// Giờ hay chạy, bấm một lần thay vì lăn bánh xe.
const runRoomQuickTimes = [
  TimeOfDay(hour: 5, minute: 30),
  TimeOfDay(hour: 6, minute: 0),
  TimeOfDay(hour: 18, minute: 0),
  TimeOfDay(hour: 19, minute: 0),
];

const _weekdayLong = [
  'thứ Hai',
  'thứ Ba',
  'thứ Tư',
  'thứ Năm',
  'thứ Sáu',
  'thứ Bảy',
  'Chủ nhật',
];

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Mở sheet tạo phòng; tạo xong thì vào màn phòng. [scheduled] chọn sẵn
/// sáng mai cho lối vào "Phòng Live hẹn giờ".
Future<void> showCreateRunRoomSheet(
  BuildContext context, {
  bool scheduled = false,
}) async {
  final roomId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CreateRunRoomSheet(scheduled: scheduled),
  );
  if (roomId == null || !context.mounted) return;
  context.push('/rooms/$roomId');
}

class CreateRunRoomSheet extends ConsumerStatefulWidget {
  const CreateRunRoomSheet({this.scheduled = false, super.key});

  final bool scheduled;

  @override
  ConsumerState<CreateRunRoomSheet> createState() => _CreateRunRoomSheetState();
}

class _CreateRunRoomSheetState extends ConsumerState<CreateRunRoomSheet> {
  final _title = TextEditingController();
  final _password = TextEditingController();
  RunRoomPrivacy _privacy = RunRoomPrivacy.public;
  int _maxRunners = 8;

  /// null là chạy ngay; 0 là hôm nay, 1 là mai…
  late int? _day = widget.scheduled ? 1 : null;
  TimeOfDay _time = runRoomQuickTimes.first;
  RunContractRoute? _route;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _startsAt() {
    final day = _day;
    if (day == null) return null;
    final today = _today();
    return DateTime(
      today.year,
      today.month,
      today.day + day,
      _time.hour,
      _time.minute,
    );
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
    final starts = _startsAt();
    if (starts != null && !starts.isAfter(DateTime.now())) {
      return 'Giờ này đã qua, chọn giờ khác hoặc chạy ngay.';
    }
    return null;
  }

  Future<void> _pickRoute({required bool gpx}) async {
    final picked = await Navigator.of(context, rootNavigator: true)
        .push<RunContractRoute>(
          MaterialPageRoute(
            builder: (_) =>
                RunContractRouteCreateScreen(pickOnly: true, startWithGpx: gpx),
          ),
        );
    if (picked == null || !mounted) return;
    setState(() => _route = runRoomRoutePreview(picked));
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
            startsAt: _startsAt(),
            route: _route,
          );
      askRoomPushPermission(ref);
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      if (mounted) setState(() => _error = runRoomErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _submitLabel() {
    final day = _day;
    if (day == null) return 'Mở phòng ngay';
    final when = day == 0
        ? 'hôm nay'
        : _weekdayLong[_today().add(Duration(days: day)).weekday - 1];
    return 'Mở phòng · ${_hhmm(_time)} $when';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final sectionLabel = TextStyle(
      color: palette.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    final today = _today();
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
              const SizedBox(height: 4),
              Text('TUYẾN CHẠY · TUỲ CHỌN', style: sectionLabel),
              const SizedBox(height: 8),
              if (_route case final route?) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: palette.tint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 56,
                        child: RunRoomRouteSketch(
                          route: route,
                          color: palette.accent,
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tuyến ${runRoomRouteKm(route)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Cả phòng thấy tuyến này trên map.',
                              style: TextStyle(color: palette.textMuted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _route = null),
                        child: const Text('Bỏ'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickRoute(gpx: false),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text(_route == null ? 'Vẽ tuyến' : 'Vẽ lại'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickRoute(gpx: true),
                      icon: const Icon(Icons.file_download_rounded, size: 18),
                      label: const Text('Nhập GPX'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 4),
              Text('GIỜ XUẤT PHÁT', style: sectionLabel),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    _DayChip(
                      top: 'Bây giờ',
                      bottom: 'Ngay',
                      selected: _day == null,
                      onTap: () => setState(() => _day = null),
                    ),
                    for (var d = 0; d < runRoomScheduleDays; d++)
                      _DayChip(
                        top: runRoomDayLabel(
                          today.add(Duration(days: d)),
                          today,
                        ),
                        bottom: _dayMonth(today.add(Duration(days: d))),
                        selected: _day == d,
                        onTap: () => setState(() => _day = d),
                      ),
                  ],
                ),
              ),
              if (_day != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.tint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _TimeWheel(
                        time: _time,
                        onChanged: (t) => setState(() => _time = t),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in runRoomQuickTimes)
                              ChoiceChip(
                                label: Text(_hhmm(t)),
                                selected: t == _time,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _time = t),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Đang mở phòng…' : _submitLabel()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dayMonth(DateTime d) => '${d.day}/${d.month}';

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.top,
    required this.bottom,
    required this.selected,
    required this.onTap,
  });

  final String top;
  final String bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final fg = selected ? palette.accent : palette.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.ink : palette.tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                Text(
                  top,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                ),
                Text(
                  bottom,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bánh xe giờ và phút (bước 5 phút). Bấm chip giờ nhanh thì bánh xe lăn
/// theo, nên [time] từ ngoài vào là nguồn đúng.
class _TimeWheel extends StatefulWidget {
  const _TimeWheel({required this.time, required this.onChanged});

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  late final _hours = FixedExtentScrollController(
    initialItem: widget.time.hour,
  );
  late final _minutes = FixedExtentScrollController(
    initialItem: widget.time.minute ~/ 5,
  );

  @override
  void didUpdateWidget(_TimeWheel old) {
    super.didUpdateWidget(old);
    // Lăn sau frame: jumpToItem bắn onSelectedItemChanged, mà gọi setState
    // của sheet trong lúc đang build là lỗi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = widget.time;
      if (_hours.hasClients && _hours.selectedItem != t.hour) {
        _hours.jumpToItem(t.hour);
      }
      if (_minutes.hasClients && _minutes.selectedItem != t.minute ~/ 5) {
        _minutes.jumpToItem(t.minute ~/ 5);
      }
    });
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Widget _wheel(
    FixedExtentScrollController controller,
    int count,
    String Function(int) label,
    ValueChanged<int> onSelected,
  ) => SizedBox(
    width: 52,
    height: 120,
    child: CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: 34,
      childCount: count,
      selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
        capStartEdge: false,
        capEndEdge: false,
      ),
      onSelectedItemChanged: onSelected,
      itemBuilder: (context, i) => Center(
        child: Text(
          label(i),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _wheel(
        _hours,
        24,
        (i) => i.toString().padLeft(2, '0'),
        (i) => widget.onChanged(TimeOfDay(hour: i, minute: widget.time.minute)),
      ),
      const Text(
        ':',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      _wheel(
        _minutes,
        12,
        (i) => (i * 5).toString().padLeft(2, '0'),
        (i) =>
            widget.onChanged(TimeOfDay(hour: widget.time.hour, minute: i * 5)),
      ),
    ],
  );
}
