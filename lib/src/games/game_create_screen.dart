import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_skill_cards.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/games/game_round_dial.dart';
import 'package:myrun/src/games/game_settings_panel.dart';
import 'package:myrun/src/games/game_time_picker.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Admin mở ván Ma Sói. Vai bật tắt được, tuỳ chọn luật, tab và kiểu ván dựng
/// sẵn lấy từ `createOptions` của `GET /v1/games`, nên thêm vai, tuỳ chọn hay
/// kiểu ván ở backend thì app không phải sửa. Backend chưa gửi tab thì vẽ danh
/// sách tuỳ chọn như cũ.
class GameCreateScreen extends ConsumerStatefulWidget {
  const GameCreateScreen({super.key});

  @override
  ConsumerState<GameCreateScreen> createState() => _GameCreateScreenState();
}

class _GameCreateScreenState extends ConsumerState<GameCreateScreen> {
  final _roles = <String, bool>{};

  /// Chỉ giữ tuỳ chọn người tạo đã chỉnh, đè lên kiểu ván đang chọn; còn lại
  /// backend tự áp mặc định.
  final _settings = <String, Object>{};

  /// Kiểu ván đang chọn; null là kiểu mặc định backend gửi.
  String? _presetKey;
  int _tab = 0;

  /// Số người đang xem trước bộ bài; null là số backend gợi ý.
  int? _deckPlayers;
  final _theme = gameMoonlitTheme();
  DateTime? _deadline;

  /// Tab Lịch: đóng đăng ký theo giờ (mặc định) hay chủ phòng đóng; bắt đầu
  /// theo giờ hay chủ phòng bấm (mặc định). Giờ chưa chọn thì lấy mặc định.
  bool _deadlineOn = true;
  bool _startOn = false;
  DateTime? _startAt;
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
    final pick = await showGameDeadlineSheet(context, initial: _deadline);
    if (pick == null || !mounted) return;
    setState(() => _deadline = pick.at);
  }

  /// Giờ [hour]:[minute] ngày mai.
  static DateTime _tomorrowAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// Giờ đóng đăng ký; chưa chọn thì 21h mai.
  DateTime get _deadlineAt => _deadline ?? _tomorrowAt(21, 0);

  /// Giờ chia bài; chưa chọn thì 30 phút sau giờ đóng đăng ký.
  DateTime get _startAtValue =>
      _startAt ??
      (_deadlineOn ? _deadlineAt : _tomorrowAt(21, 0)).add(
        const Duration(minutes: 30),
      );

  Future<void> _pickTabDeadline() async {
    final pick = await showGameDeadlineSheet(
      context,
      initial: _deadlineAt,
      noneLabel: null,
    );
    final at = pick?.at;
    if (at == null || !mounted) return;
    setState(() => _deadline = at);
  }

  Future<void> _pickStartAt() async {
    final pick = await showGameDeadlineSheet(
      context,
      initial: _startAtValue,
      title: 'Bắt đầu ván',
      after: _deadlineOn ? _deadlineAt : null,
      noneLabel: null,
    );
    final at = pick?.at;
    if (at == null || !mounted) return;
    setState(() => _startAt = at);
  }

  GamePreset? _preset(GameList list) {
    final presets = list.presets;
    return presets.where((p) => p.key == _presetKey).firstOrNull ??
        presets.where((p) => p.isDefault).firstOrNull ??
        presets.firstOrNull;
  }

  bool get _edited => _settings.isNotEmpty || _roles.isNotEmpty;

  /// Giá trị hiện tại của mọi tuỳ chọn: đã chỉnh, rồi tới kiểu ván, rồi mặc
  /// định.
  Map<String, Object?> _settingValues(GameList list) {
    final preset = _preset(list);
    return {
      for (final s in list.settings)
        s.key: _settings[s.key] ?? preset?.settings[s.key] ?? s.defaultValue,
    };
  }

  bool _roleOn(GameList list, GameRoleOption option) =>
      _roles[option.key] ??
      _preset(list)?.roles[option.key] ??
      option.defaultOn;

  /// Gửi giá trị của kiểu ván và phần đã chỉnh, bỏ tuỳ chọn đang hết tác
  /// dụng; null khi không có gì.
  Map<String, Object>? _settingsToSend(GameList list) {
    final values = _settingValues(list);
    final byKey = {for (final s in list.settings) s.key: s};
    final merged = {...?_preset(list)?.settings, ..._settings};
    final out = {
      for (final e in merged.entries)
        if (byKey[e.key]?.enabledBy(values) ?? true) e.key: e.value,
    };
    // Gửi đủ bốn pha như đang vẽ, kể cả khi chưa chỉnh: không gửi thì backend
    // co lịch gốc theo tỉ lệ, lệch với giờ app đã cho xem.
    if (_roundShape(list, values) case final shape?) {
      for (var i = 0; i < shape.keys.length; i++) {
        out[shape.keys[i]] = shape.phases[i].toDouble();
      }
      if (out.containsKey('roundsPerDay')) {
        out['roundsPerDay'] = shape.rounds.toDouble();
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Lịch một vòng khi backend cho chỉnh độ dài pha (pha có `settingKey`);
  /// null là backend cũ. Ván km mở theo giờ gốc và vòng dài đúng 24 tiếng
  /// chia số vòng, nên mốc cuối khoá.
  _RoundShape? _roundShape(GameList list, Map<String, Object?> values) {
    final round = list.round;
    if (round == null || round.phases.isEmpty) return null;
    final byKey = {for (final s in list.settings) s.key: s};
    final keys = [for (final p in round.phases) p.settingKey ?? ''];
    if (!keys.every((k) => byKey[k]?.type == GameSetting.phase)) return null;
    const day = 24 * 60;
    var rounds = _number(values['roundsPerDay'], 1).round().clamp(1, 24);
    var phases = [for (final k in keys) _number(values[k], 0).round()];
    final sum = phases.fold<int>(0, (a, p) => a + p);
    if (values['kmOff'] != true) {
      // Ván km chia đều 24 tiếng; số vòng lẻ (từ ván cổ điển) lùi về số chia
      // hết gần nhất.
      while (24 % rounds != 0) {
        rounds--;
      }
      final total = day ~/ rounds;
      if (sum != total) phases = gameFitPhases(phases, total);
      return (
        keys: keys,
        phases: phases,
        rounds: rounds,
        start: (_number(byKey['startHour']?.defaultValue, 22) * 60).round(),
        lockEnd: true,
        maxTotal: total,
      );
    }
    final maxTotal = day ~/ rounds ~/ 60 * 60;
    if (sum > maxTotal) phases = gameFitPhases(phases, maxTotal);
    return (
      keys: keys,
      phases: phases,
      rounds: rounds,
      start: (_number(values['startHour'], 22) * 60).round(),
      lockEnd: false,
      maxTotal: maxTotal,
    );
  }

  void _setPhases(List<String> keys, List<int> phases) => setState(() {
    for (var i = 0; i < keys.length; i++) {
      _settings[keys[i]] = phases[i].toDouble();
    }
  });

  void _pickPreset(GamePreset preset) => setState(() {
    _presetKey = preset.key;
    _settings.clear();
    _roles.clear();
  });

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
                option.key: _roleOn(list, option),
            },
            registrationDeadline: list.groups.isEmpty
                ? _deadline
                : _deadlineOn
                ? _deadlineAt
                : null,
            startAt: list.groups.isNotEmpty && _startOn ? _startAtValue : null,
            testMode: _testMode,
            chatId: _testMode ? _chatId.text.trim() : null,
            threadId: threadId,
            settings: _settingsToSend(list),
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
    final list = ref.watch(gameListProvider);
    // Màn tạo ván cùng tông ánh trăng với trang ván.
    return Theme(
      data: _theme,
      child: Builder(
        builder: (context) {
          final palette = context.runNowPalette;
          final form = switch (list) {
            AsyncData(value: final list?) when list.canCreate => list,
            _ => null,
          };
          return Scaffold(
            backgroundColor: palette.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Quay lại',
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: switch (list) {
                      _ when form != null && form.groups.isNotEmpty =>
                        _tabbedForm(form),
                      _ when form != null => _form(form),
                      AsyncData() => const _Message(
                        'Chỉ admin mở được ván Ma Sói.',
                      ),
                      AsyncError() => _Message(
                        'Chưa đọc được cấu hình ván.',
                        onRetry: () => ref.invalidate(gameListProvider),
                      ),
                      _ => const RunNowLoading(label: 'Đang tải'),
                    },
                  ),
                ],
              ),
            ),
            bottomNavigationBar: form == null
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: GameCreateOpenButton(
                        working: _working,
                        onPressed: _working ? null : () => _create(form),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  /// Form cũ, dùng khi backend chưa gửi tab.
  Widget _form(GameList list) {
    final settings = list.settings.where(gameSettingSupported).toList();
    final values = _settingValues(list);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const GameCreateHeader(),
        const SizedBox(height: 18),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final option in list.roleOptions)
                SwitchListTile(
                  title: Text(option.label),
                  value: _roleOn(list, option),
                  onChanged: _working
                      ? null
                      : (on) => setState(() => _roles[option.key] = on),
                ),
            ],
          ),
        ),
        if (settings.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: GameSettingsPanel(
              settings: settings,
              values: values,
              enabled: !_working,
              onChanged: (key, value) => setState(() => _settings[key] = value),
            ),
          ),
        ],
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [_deadlineTile(), ..._postFields()]),
        ),
        ..._submitError(),
      ],
    );
  }

  /// Tab Lịch: đóng đăng ký và bắt đầu, mỗi khối chọn theo giờ hay để chủ
  /// phòng tự làm.
  List<Widget> _schedule(Map<String, Object?> values, Widget why) {
    final now = DateTime.now();
    final deadline = _deadlineAt;
    final start = _startAtValue;
    // Đêm 1 mở ở giờ mở vòng đầu tiên cách lúc chia bài ít nhất 2 tiếng.
    final hour = _number(values['startHour'], 22).round();
    final ready = start.add(const Duration(hours: 2));
    var night1 = DateTime(ready.year, ready.month, ready.day, hour);
    if (night1.isBefore(ready)) {
      night1 = DateTime(night1.year, night1.month, night1.day + 1, hour);
    }
    String at(DateTime d) =>
        '${DateFormat('HH:mm').format(d)} · ${gameDayLabel(d).replaceFirst(',', '')}';
    return [
      GameCreateLabel('Đăng ký', trailing: why),
      GameCreateSegment(
        labels: const ['Theo giờ', 'Chủ phòng đóng'],
        selected: _deadlineOn ? 0 : 1,
        onSelect: _working ? null : (i) => setState(() => _deadlineOn = i == 0),
      ),
      const SizedBox(height: 10),
      if (_deadlineOn)
        GameScheduleCard(
          icon: Icons.event_rounded,
          caption: 'ĐÓNG ĐĂNG KÝ',
          title: at(deadline),
          subtitle: gameUntil(deadline, now),
          onTap: _working ? null : _pickTabDeadline,
        )
      else
        const GameCreateManual(
          icon: Icons.event_rounded,
          text: 'Mở tới khi chủ phòng bắt đầu ván',
        ),
      const SizedBox(height: 10),
      const GameCreateLabel('Bắt đầu'),
      GameCreateSegment(
        labels: const ['Theo giờ', 'Chủ phòng bấm'],
        selected: _startOn ? 0 : 1,
        onSelect: _working ? null : (i) => setState(() => _startOn = i == 0),
      ),
      const SizedBox(height: 10),
      if (_startOn)
        GameScheduleCard(
          icon: Icons.nightlight_round,
          caption: 'CHIA BÀI LÚC',
          title: at(start),
          subtitle:
              '${gameUntil(start, now)} · Đêm 1 mở ${hour}h '
              '${DateFormat('dd/MM').format(night1)}',
          onTap: _working ? null : _pickStartAt,
        )
      else
        const GameCreateManual(
          icon: Icons.nightlight_round,
          text: 'Chủ phòng bấm Bắt đầu khi đủ người',
        ),
    ];
  }

  Widget _deadlineTile() {
    final deadline = _deadline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GameScheduleCard(
        icon: Icons.event_rounded,
        caption: 'ĐÓNG ĐĂNG KÝ',
        title: deadline == null
            ? 'Không hạn'
            : '${DateFormat('HH:mm').format(deadline)} · '
                  '${gameDayLabel(deadline)}',
        subtitle: deadline == null
            ? 'Chạm để đặt giờ đóng'
            : '${gameUntil(deadline, DateTime.now())}, quá giờ này không ai '
                  'vào thêm',
        active: deadline != null,
        onTap: _working ? null : _pickDeadline,
      ),
    );
  }

  /// Ván thử, chat id và topic bot đăng vào.
  /// Sheet gọi lại để vẽ lại chính nó; form cũ thì chỉ setState của màn.
  List<Widget> _postFields({void Function(VoidCallback)? onChanged}) {
    final update = onChanged ?? setState;
    return [
      SwitchListTile(
        title: const Text('Ván thử'),
        subtitle: const Text('Chạy ở group test, chỉ admin và người test thấy'),
        value: _testMode,
        onChanged: _working ? null : (on) => update(() => _testMode = on),
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
          onChanged: (_) => update(() {}),
          decoration: const InputDecoration(
            labelText: 'ID topic (không bắt buộc)',
            helperText: 'Bỏ trống thì bot đăng vào General',
          ),
        ),
      ),
    ];
  }

  /// Lỗi lúc mở ván, ngay trên nút mở ván ghim dưới màn.
  List<Widget> _submitError() => [
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

  // ---- Form theo tab ----

  Widget _tabbedForm(GameList list) {
    final preset = _preset(list);
    final values = _settingValues(list);
    final groups = list.groups;
    final tab = _tab.clamp(0, groups.length - 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const GameCreateHeader(),
        const SizedBox(height: 18),
        if (list.presets.isNotEmpty) ...[
          GameCreateLabel(
            'Kiểu ván',
            trailing: preset == null || preset.details.isEmpty
                ? null
                : GameCreateLink(
                    'Xem chi tiết',
                    onTap: () => showGameCreateSheet(
                      context,
                      title: 'Kiểu ${preset.label}',
                      items: [for (final d in preset.details) ('', d)],
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          // Ba ô cao bằng nhau dù tên dài ngắn khác nhau.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in list.presets.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GamePresetTile(
                      preset: p,
                      selected: !_edited && p.key == preset?.key,
                      onTap: _working ? null : () => _pickPreset(p),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        GameCreatePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const GameCreateLabel('Tuỳ chỉnh'),
              const SizedBox(height: 8),
              GameCreateTabBar(
                groups: groups,
                selected: tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 4),
              ..._tabBody(list, groups[tab], values),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GameCreateRow(
          icon: Icons.send_rounded,
          label: 'Bot đăng vào',
          value: _postSummary(),
          onTap: _working ? null : _editPost,
        ),
        ..._submitError(),
      ],
    );
  }

  /// Sheet chỉnh ván thử, chat id và topic; ghi thẳng vào state của màn.
  Future<void> _editPost() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheet).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _postFields(
            onChanged: (change) {
              setState(change);
              setSheet(() {});
            },
          ),
        ),
      ),
    ),
  );

  String _postSummary() {
    final thread = _threadId.text.trim();
    final where = thread.isEmpty ? 'General' : 'Topic $thread';
    return _testMode ? 'Ván thử · $where' : where;
  }

  List<Widget> _tabBody(
    GameList list,
    GameSettingGroup group,
    Map<String, Object?> values,
  ) {
    final inGroup = [
      for (final s in list.settings)
        if (s.group == group.key && gameSettingSupported(s)) s,
    ];
    final live = [
      for (final s in inGroup)
        if (s.enabledBy(values)) s,
    ];
    final offNote = group.offNote;
    final round = list.round;
    final shape = _roundShape(list, values);
    final startHour = list.settings
        .where((s) => s.key == 'startHour' && s.enabledBy(values))
        .firstOrNull;
    final why = GameCreateLink(
      'Là gì?',
      onTap: () => showGameCreateSheet(
        context,
        title: group.label,
        items: _explain(list, group, inGroup, startLocked: startHour == null),
      ),
    );
    // "Là gì?" nằm trên tiêu đề khối app tự vẽ ở đầu tab. Tab km không có vì
    // thẻ nào cũng có Chi tiết riêng; tab lạ thì đặt riêng một hàng.
    final out = <Widget>[
      if (!const {'time', 'round', 'roles', 'km'}.contains(group.key))
        Align(alignment: Alignment.centerRight, child: why),
    ];
    if (group.key == 'time') {
      out.addAll(_schedule(values, why));
    }
    final deck = list.deck;
    if (group.key == 'roles') {
      out.add(GameCreateLabel('Bộ bài', trailing: why));
      if (deck != null) {
        out.addAll(_deck(list, deck, live, values));
      } else {
        out.add(_roleGrid(list, live, values));
      }
    }
    for (final s in live) {
      if (s.section != null) continue;
      if (group.key == 'roles' && s.type == GameSetting.toggle) continue;
      // Có bộ bài thì số sói và vai thêm chỉnh ngay trong bộ bài.
      if (group.key == 'roles' && deck != null) continue;
      if (shape != null) {
        // Độ dài vòng là tổng bốn pha, giờ mở là dòng Mở vòng dưới vòng đồng
        // hồ, dù backend xếp nó ở tab nào.
        if (s.key == 'roundHours' || s.key == 'startHour') continue;
        if (s.key == 'roundsPerDay') {
          out.add(_scheduleWidget(s, shape, values));
          continue;
        }
      }
      out.add(_settingWidget(s, values));
    }
    out.addAll(_sections(list, live, values));
    // Tab Lịch luôn có đăng ký và bắt đầu; lời giải thích giờ mở của ván km
    // nằm ở "Là gì?" của tab Vòng chơi.
    if (live.isEmpty && offNote != null && group.key != 'time') {
      out.add(GameCreateNote(icon: Icons.nightlight_round, text: offNote));
    }
    if (round != null && shape != null && group.key == 'round') {
      out
        ..add(const SizedBox(height: 8))
        ..add(GameCreateLabel('Kéo mốc để chia giờ', trailing: why))
        ..add(
          GameRoundDial(
            plan: round,
            phases: shape.phases,
            startMinute: shape.start,
            lockEnd: shape.lockEnd,
            maxTotal: shape.maxTotal,
            onChanged: _working ? null : (p) => _setPhases(shape.keys, p),
            onStart: _working || shape.lockEnd || startHour == null
                ? null
                : (start, phases) => setState(() {
                    _settings[startHour.key] = (start ~/ 60).toDouble();
                    _setPhases(shape.keys, phases);
                  }),
          ),
        );
    } else if (round != null &&
        group.key == 'round' &&
        round.phases.isNotEmpty) {
      out
        ..add(const SizedBox(height: 14))
        ..add(GameCreateLabel(group.label, trailing: why))
        ..add(
          GameRoundTimeline(
            plan: round,
            startHour: _number(values['startHour'], 22),
            roundHours: _number(values['roundHours'], 24),
          ),
        );
    }
    return out;
  }

  /// Số vòng mỗi ngày khi có vòng đồng hồ: ván km chọn số vòng chia hết 24
  /// tiếng, ván cổ điển chọn số vòng vừa trong ngày.
  Widget _scheduleWidget(
    GameSetting s,
    _RoundShape shape,
    Map<String, Object?> values,
  ) {
    void setRounds(int n) => setState(() => _settings[s.key] = n.toDouble());
    final lo = (s.min ?? 1).round(), hi = (s.max ?? 6).round();
    // Ván km: vòng chia đều 24 tiếng. Ván cổ điển: chọn số vòng trước, vòng
    // dài hơn phần mỗi vòng được thì các pha co lại cho vừa (_roundShape).
    final asked = [for (final k in shape.keys) _number(values[k], 0).round()];
    final sum = asked.fold<int>(0, (a, p) => a + p);
    int length(int n) {
      if (shape.lockEnd) return 24 * 60 ~/ n;
      return math.min(sum, 24 * 60 ~/ n ~/ 60 * 60);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCreateLabel(s.label),
          const SizedBox(height: 8),
          GameRoundsSegments(
            options: [
              for (var n = lo; n <= hi; n++)
                if (!shape.lockEnd || 24 % n == 0) n,
            ],
            selected: shape.rounds,
            length: (n) => gameHours(length(n)),
            onSelect: _working ? null : setRounds,
          ),
        ],
      ),
    );
  }

  /// Tuỳ chọn cùng `section` vẽ thành một khối có nhãn, theo thứ tự backend
  /// gửi. Lựa chọn có nhãn ngắn thành thẻ chế độ; tuỳ chọn có icon thành thẻ
  /// kỹ năng, dòng con (parent) nằm trong thẻ cha; tuỳ chọn của vai không có
  /// trong bộ bài thì ẩn. Còn lại: ô số trước, rồi thẻ bật tắt thu gọn được.
  List<Widget> _sections(
    GameList list,
    List<GameSetting> live,
    Map<String, Object?> values,
  ) {
    bool inDeck(String role) {
      if (role == 'wolf' || values[role] == true) return true;
      for (final o in list.roleOptions) {
        if (o.key == role) return _roleOn(list, o);
      }
      return false;
    }

    final shown = [
      for (final s in live)
        if (s.role == null || inDeck(s.role!)) s,
    ];
    // Bật tắt của tab Vai là đặc quyền phe: vẽ thành dòng có ô tích dù có
    // icon.
    bool power(GameSetting s) =>
        s.type == GameSetting.toggle && s.group == 'roles';
    final cards = {
      for (final s in shown)
        if (s.icon != null && !power(s)) s.key,
    };
    final bySection = <String, List<GameSetting>>{};
    for (final s in shown) {
      if (s.section case final section?) {
        (bySection[section] ??= []).add(s);
      }
    }
    void set(String key, Object v) => setState(() => _settings[key] = v);
    Widget card(GameSetting s, List<GameSetting> items) {
      final value = values[s.key];
      final on = s.type == GameSetting.toggle
          ? value == true
          : _number(value, 0) > 0;
      return GameSkillCard(
        setting: s,
        warn: on ? s.warn : null,
        trailing: s.type == GameSetting.toggle
            ? Switch(
                value: value == true,
                onChanged: _working ? null : (v) => set(s.key, v),
              )
            : GameSkillStepper(
                label: s.label,
                value: _number(value, s.min ?? 0),
                min: s.min ?? double.negativeInfinity,
                max: s.max ?? double.infinity,
                step: s.step ?? 1,
                unit: s.unit,
                onChanged: _working ? null : (v) => set(s.key, v),
              ),
        children: [
          for (final c in items)
            if (c.parent == s.key && c.type == GameSetting.number)
              GameSkillSubLine(
                setting: c,
                value: _number(values[c.key], c.min ?? 0),
                onChanged: _working ? null : (v) => set(c.key, v),
              ),
        ],
      );
    }

    Widget plain(GameSetting s) {
      if (s.type == GameSetting.choice &&
          s.choices.any((c) => c.hint != null)) {
        return GameModeCards(
          setting: s,
          value: values[s.key],
          onChanged: _working ? null : (v) => set(s.key, v),
        );
      }
      return _settingWidget(s, values);
    }

    return [
      for (final MapEntry(key: label, value: items) in bySection.entries) ...[
        const SizedBox(height: 12),
        if (items.any(power))
          GameCreateLabel(
            label,
            color: _M.phaseTrial,
            leading: gameKeyIcon('wolf', color: _M.phaseTrial, size: 16),
            trailing: GameCreateLink(
              'Là gì?',
              onTap: () => showGameCreateSheet(
                context,
                title: label,
                items: [
                  for (final s in items)
                    (
                      s.label,
                      switch (s.warn) {
                        final w? when w.isNotEmpty => '${s.description} ⚠ $w',
                        _ => s.description,
                      },
                    ),
                ],
              ),
            ),
          )
        else
          GameCreateLabel(label),
        const SizedBox(height: 8),
        for (final s in items)
          if (s.parent != null && cards.contains(s.parent))
            const SizedBox.shrink()
          else if (cards.contains(s.key))
            card(s, items)
          else if (s.type != GameSetting.toggle)
            // Khối đặc quyền chưa bật cái nào thì ô số của khối mờ đi.
            Opacity(
              opacity:
                  items.any(power) &&
                      !items.any((p) => power(p) && values[p.key] == true)
                  ? 0.45
                  : 1,
              child: plain(s),
            ),
        for (final s in items)
          if (s.type == GameSetting.toggle && !cards.contains(s.key))
            GamePowerCard(
              setting: s,
              on: values[s.key] == true,
              onChanged: _working ? null : (v) => set(s.key, v),
            ),
      ],
    ];
  }

  static double _number(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;

  /// Bộ bài của tab Vai: chọn theo số người hay tự chỉnh, bảng chia chuẩn,
  /// số người xem trước và số lá từng vai. Theo số người thì chỉ vai thêm
  /// (tuỳ chọn bật tắt của tab Vai) có nút; tự chỉnh thì số sói vào tuỳ chọn
  /// [GameDeckPlan.wolvesKey] và vai đặc biệt bật tắt như công tắc vai.
  List<Widget> _deck(
    GameList list,
    GameDeckPlan deck,
    List<GameSetting> live,
    Map<String, Object?> values,
  ) {
    final n = (_deckPlayers ?? deck.preview).clamp(
      deck.minPlayers,
      deck.maxPlayers,
    );
    final wolves = _number(values[deck.wolvesKey], 0).round();
    final fixed = wolves > 0;
    final roles = list.roleOptions;
    final extended = [
      for (final s in live)
        if (s.type == GameSetting.toggle && s.section == null) s,
    ];
    final counts = deck.counts(
      n: n,
      specials: [for (final o in roles) o.key],
      on: (key) => _roleOn(list, roles.firstWhere((o) => o.key == key)),
      extended: [
        for (final s in extended)
          if (values[s.key] == true) s.key,
      ],
      wolves: wolves,
    );
    final room = (counts['villager'] ?? 0) > 0;
    final busy = _working;
    void set(VoidCallback change) => busy ? null : setState(change);

    void pickMode(int i) => set(() {
      if (i == 0) {
        _settings[deck.wolvesKey] = 0.0;
        _roles.clear();
        return;
      }
      // Tự chỉnh bắt đầu từ đúng bộ bài đang xem.
      _settings[deck.wolvesKey] = (counts['wolf'] ?? 1).toDouble();
      for (final o in roles) {
        _roles[o.key] = counts[o.key] == 1;
      }
    });

    final wolf = counts['wolf'] ?? 0;
    final tiles = <Widget>[
      GameDeckTile(
        role: 'wolf',
        label: 'Sói',
        count: wolf,
        editable: fixed,
        onRemove: wolf > 1
            ? () => set(() => _settings[deck.wolvesKey] = wolf - 1.0)
            : null,
        onAdd: wolf < n ~/ 3 && room
            ? () => set(() => _settings[deck.wolvesKey] = wolf + 1.0)
            : null,
      ),
      for (final o in roles)
        GameDeckTile(
          role: o.key,
          label: o.label,
          count: counts[o.key] ?? 0,
          editable: fixed,
          onRemove: counts[o.key] == 1
              ? () => set(() => _roles[o.key] = false)
              : null,
          onAdd: counts[o.key] == 0 && room
              ? () => set(() => _roles[o.key] = true)
              : null,
        ),
      for (final s in extended)
        GameDeckTile(
          role: s.key,
          label: s.label,
          count: counts[s.key] ?? 0,
          editable: true,
          onRemove: values[s.key] == true
              ? () => set(() => _settings[s.key] = false)
              : null,
          onAdd: values[s.key] != true && room
              ? () => set(() => _settings[s.key] = true)
              : null,
        ),
      GameDeckTile(
        role: 'villager',
        label: 'Dân',
        count: counts['villager'] ?? 0,
      ),
    ];
    return [
      GameCreateSegment(
        labels: const ['Theo số người chơi', 'Tự chỉnh'],
        selected: fixed ? 1 : 0,
        onSelect: busy ? null : pickMode,
      ),
      const SizedBox(height: 10),
      Text(
        fixed ? deck.fixedNote : deck.note,
        style: const TextStyle(fontSize: 12.5, height: 1.45, color: _M.muted),
      ),
      const SizedBox(height: 10),
      if (!fixed) ...[
        GameDeckTiers(plan: deck, players: n),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: Text(
              fixed ? 'Số người' : 'Xem trước với',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          GameSkillStepper(
            label: 'số người',
            value: n.toDouble(),
            min: deck.minPlayers.toDouble(),
            max: deck.maxPlayers.toDouble(),
            step: 1,
            unit: 'người',
            small: true,
            onChanged: (v) => setState(() => _deckPlayers = v.round()),
          ),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, box) {
          const gap = 8.0;
          final width = (box.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final t in tiles) SizedBox(width: width, child: t)],
          );
        },
      ),
      const SizedBox(height: 8),
    ];
  }

  /// Lưới vai: Sói luôn có, vai bật tắt được, rồi vai thêm (tuỳ chọn bật tắt
  /// của tab Vai).
  Widget _roleGrid(
    GameList list,
    List<GameSetting> live,
    Map<String, Object?> values,
  ) {
    final chips = <Widget>[
      const GameRoleChip(role: 'wolf', label: 'Sói', on: true, onTap: null),
      for (final o in list.roleOptions)
        GameRoleChip(
          role: o.key,
          label: o.label,
          on: _roleOn(list, o),
          onTap: _working
              ? null
              : () => setState(() => _roles[o.key] = !_roleOn(list, o)),
        ),
      for (final s in live)
        if (s.type == GameSetting.toggle && s.section == null)
          GameRoleChip(
            role: s.key,
            label: s.label,
            on: values[s.key] == true,
            onTap: _working
                ? null
                : () =>
                      setState(() => _settings[s.key] = values[s.key] != true),
          ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 8.0;
          final width = (box.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final c in chips) SizedBox(width: width, child: c)],
          );
        },
      ),
    );
  }

  Widget _settingWidget(GameSetting s, Map<String, Object?> values) {
    final value = values[s.key];
    return switch (s.type) {
      GameSetting.number => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: GameCreateStepper(
          label: s.label,
          hint: s.hint,
          value: _number(value, s.min ?? 0),
          min: s.min ?? double.negativeInfinity,
          max: s.max ?? double.infinity,
          step: s.step ?? 1,
          unit: s.unit,
          onChanged: _working
              ? null
              : (v) => setState(() => _settings[s.key] = v),
        ),
      ),
      GameSetting.toggle => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          s.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: switch (s.hint) {
          final h? when h.isNotEmpty => Text(
            h,
            style: const TextStyle(fontSize: 12, color: _M.muted),
          ),
          _ => null,
        },
        value: value == true,
        onChanged: _working
            ? null
            : (v) => setState(() => _settings[s.key] = v),
      ),
      _ => GameCreateChoices(
        setting: s,
        value: value,
        onChanged: _working
            ? null
            : (v) => setState(() => _settings[s.key] = v),
      ),
    };
  }

  /// Các mục của sheet "Là gì?" cho một tab.
  List<(String, String)> _explain(
    GameList list,
    GameSettingGroup group,
    List<GameSetting> inGroup, {
    required bool startLocked,
  }) {
    final round = list.round;
    // Giờ mở bị khoá (ván km) thì lời giải thích của tab chứa startHour nói
    // vì sao, đặt cạnh dòng Mở vòng trên tab Vòng chơi.
    final startGroup = list.settings
        .where((s) => s.key == 'startHour')
        .firstOrNull
        ?.group;
    final startNote = list.groups
        .where((g) => g.key == startGroup)
        .firstOrNull
        ?.offNote;
    return [
      if (group.key == 'roles')
        for (final o in list.roleOptions)
          if (o.description.isNotEmpty) (o.label, o.description),
      if (group.key == 'round' && round != null)
        for (final p in round.phases) (p.label, p.description),
      if (group.key == 'round' && startLocked && startNote != null)
        ('Mở vòng', startNote),
      for (final s in inGroup) ...[
        (s.label, s.description),
        for (final c in s.choices) ('· ${c.label}', c.description),
      ],
      if (group.key == 'time') ...[
        (
          'Đăng ký',
          'Theo giờ: quá giờ này không ai vào thêm. Chủ phòng đóng: mở tới '
              'lúc ván bắt đầu.',
        ),
        (
          'Bắt đầu',
          'Theo giờ: tới giờ bot chia bài, thiếu người thì ván chờ chủ phòng '
              'bấm.',
        ),
      ],
      if (group.key == 'time' && round != null && round.start.isNotEmpty)
        ('Bắt đầu và kết thúc', round.start),
    ];
  }
}

typedef _M = RunNowMoonlitTokens;

/// Lịch một vòng khi có vòng đồng hồ: khoá của bốn ô pha, độ dài từng pha
/// (phút), số vòng mỗi ngày đã khớp luật, giờ mở đêm (phút trong ngày), mốc
/// cuối có khoá không và độ dài vòng tối đa.
typedef _RoundShape = ({
  List<String> keys,
  List<int> phases,
  int rounds,
  int start,
  bool lockEnd,
  int maxTotal,
});

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
