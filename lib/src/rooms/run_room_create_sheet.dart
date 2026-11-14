import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/games/game_time_picker.dart';
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

/// Giờ hay chạy, bấm một lần thay vì chọn ngày rồi giờ.
const List<GameTimeQuick> runRoomQuickTimes = [
  (label: 'Sáng mai 5h30', day: 1, hour: 5, minute: 30),
  (label: 'Chiều nay 18h', day: 0, hour: 18, minute: 0),
  (label: 'Chiều mai 18h', day: 1, hour: 18, minute: 0),
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

String _hhmm(DateTime t) =>
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

  /// null là chạy ngay.
  late DateTime? _startsAt = widget.scheduled ? _defaultStart() : null;
  RunContractRoute? _route;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 05:30 sáng mai, mốc mở sẵn khi chuyển sang hẹn giờ.
  DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 5, 30);
  }

  Future<void> _pickStart() async {
    final pick = await showGameDeadlineSheet(
      context,
      initial: _startsAt,
      title: 'Giờ xuất phát',
      noneLabel: null,
      days: runRoomScheduleDays,
      quick: runRoomQuickTimes,
      colors: GameTimeColors.of(context),
    );
    final at = pick?.at;
    if (at == null || !mounted) return;
    setState(() {
      _startsAt = at;
      _error = null;
    });
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
    final starts = _startsAt;
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
            startsAt: _startsAt,
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
    final at = _startsAt;
    if (at == null) return 'Mở phòng ngay';
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final when = sameDay ? 'hôm nay' : _weekdayLong[at.weekday - 1];
    return 'Mở phòng · ${_hhmm(at)} $when';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final sectionLabel = TextStyle(
      color: palette.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
    );
    final startsAt = _startsAt;
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
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
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
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Text('XUẤT PHÁT', style: sectionLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ChoiceTile(
                      icon: Icons.bolt_rounded,
                      label: 'Chạy ngay',
                      selected: startsAt == null,
                      onTap: () => setState(() {
                        _startsAt = null;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChoiceTile(
                      icon: Icons.alarm_rounded,
                      label: 'Hẹn giờ',
                      selected: startsAt != null,
                      onTap: () =>
                          setState(() => _startsAt ??= _defaultStart()),
                    ),
                  ),
                ],
              ),
              if (startsAt != null) ...[
                const SizedBox(height: 8),
                _StartCard(at: startsAt, onTap: _busy ? null : _pickStart),
              ],
              const SizedBox(height: 14),
              Text('AI VÀO ĐƯỢC', style: sectionLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final p in RunRoomPrivacy.values) ...[
                    if (p != RunRoomPrivacy.values.first)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceTile(
                        icon: switch (p) {
                          RunRoomPrivacy.public => Icons.public_rounded,
                          RunRoomPrivacy.private => Icons.how_to_reg_rounded,
                          RunRoomPrivacy.password => Icons.key_rounded,
                        },
                        label: p.label,
                        selected: _privacy == p,
                        stacked: true,
                        onTap: () => setState(() => _privacy = p),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(switch (_privacy) {
                RunRoomPrivacy.public =>
                  'Ai cũng thấy phòng ở Trang chủ và vào thẳng.',
                RunRoomPrivacy.private =>
                  'Chỉ người có link mới thấy; bạn duyệt từng người.',
                RunRoomPrivacy.password =>
                  'Chỉ người có link và mật khẩu mới vào được.',
              }, style: TextStyle(color: palette.textMuted, fontSize: 12.5)),
              if (_privacy == RunRoomPrivacy.password) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  maxLength: runRoomPasswordMax,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu',
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Row(
                icon: Icons.groups_rounded,
                label: 'Tối đa',
                trailing: [
                  IconButton(
                    tooltip: 'Bớt',
                    visualDensity: VisualDensity.compact,
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
                    visualDensity: VisualDensity.compact,
                    onPressed: _maxRunners < runRoomMaxRunners
                        ? () => setState(() => _maxRunners++)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_route case final route?)
                _Row(
                  leading: SizedBox(
                    width: 56,
                    height: 40,
                    child: RunRoomRouteSketch(
                      route: route,
                      color: palette.accent,
                      padding: const EdgeInsets.all(4),
                    ),
                  ),
                  label: 'Tuyến ${runRoomRouteKm(route)}',
                  trailing: [
                    TextButton(
                      onPressed: _busy ? null : () => _pickRoute(gpx: false),
                      child: const Text('Vẽ lại'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _route = null),
                      child: const Text('Bỏ'),
                    ),
                  ],
                )
              else
                _Row(
                  icon: Icons.route_rounded,
                  label: 'Tuyến chạy',
                  trailing: [
                    TextButton.icon(
                      onPressed: _busy ? null : () => _pickRoute(gpx: false),
                      icon: const Icon(Icons.edit_rounded, size: 17),
                      label: const Text('Vẽ'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _pickRoute(gpx: true),
                      icon: const Icon(Icons.file_download_rounded, size: 17),
                      label: const Text('GPX'),
                    ),
                  ],
                ),
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

/// Ô chọn một trong vài lựa chọn: ô đang chọn tô nền accent.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.stacked = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Icon nằm trên chữ, cho hàng ba ô hẹp.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final fg = selected ? palette.onAccent : palette.ink;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg,
        fontSize: stacked ? 13 : 15,
        fontWeight: FontWeight.w800,
      ),
    );
    final mark = Icon(icon, size: stacked ? 20 : 20, color: fg);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? palette.accent : palette.glassStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? palette.accent : palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: stacked ? 9 : 13,
              ),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [mark, const SizedBox(height: 3), text],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        mark,
                        const SizedBox(width: 6),
                        Flexible(child: text),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ giờ xuất phát đã hẹn: giờ to, ngày, còn bao lâu; chạm để đổi.
class _StartCard extends StatelessWidget {
  const _StartCard({required this.at, required this.onTap});

  final DateTime at;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    const fg = Colors.white;
    return Semantics(
      button: true,
      label: 'Đổi giờ xuất phát',
      child: Material(
        color: palette.accentNight,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('room-start-card'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Text(
                  _hhmm(at),
                  style: const TextStyle(
                    color: fg,
                    fontSize: 34,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gameDayLabel(at),
                        style: const TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        gameUntil(at, DateTime.now()),
                        style: TextStyle(
                          color: palette.warmMark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một hàng cài đặt: icon hoặc hình, nhãn, phần điều khiển bên phải.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.trailing,
    this.icon,
    this.leading,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          leading ?? Icon(icon, size: 20, color: palette.accentDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
