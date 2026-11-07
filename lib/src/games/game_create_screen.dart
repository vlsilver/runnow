import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
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
  final _theme = gameMoonlitTheme();
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
    final pick = await showGameDeadlineSheet(context, initial: _deadline);
    if (pick == null || !mounted) return;
    setState(() => _deadline = pick.at);
  }

  Future<void> _pickStartHour(GameSetting s, int hour) async {
    final pick = await showGameHourSheet(context, title: s.label, hour: hour);
    if (pick == null || !mounted) return;
    setState(() => _settings[s.key] = pick.toDouble());
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
            registrationDeadline: _deadline,
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
          return Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              title: const Text('Mở ván Ma Sói'),
              backgroundColor: palette.background,
              elevation: 0,
            ),
            body: switch (list) {
              AsyncData(value: final list?)
                  when list.canCreate && list.groups.isNotEmpty =>
                _tabbedForm(list),
              AsyncData(value: final list?) when list.canCreate => _form(list),
              AsyncData() => const _Message('Chỉ admin mở được ván Ma Sói.'),
              AsyncError() => _Message(
                'Chưa đọc được cấu hình ván.',
                onRetry: () => ref.invalidate(gameListProvider),
              ),
              _ => const RunNowLoading(label: 'Đang tải'),
            },
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
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
        ..._submit(list),
      ],
    );
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
            ? 'Admin tự bấm bắt đầu'
            : gameUntil(deadline, DateTime.now()),
        onTap: _working ? null : _pickDeadline,
      ),
    );
  }

  /// Ván thử, chat id và topic bot đăng vào.
  List<Widget> _postFields() => [
    SwitchListTile(
      title: const Text('Ván thử'),
      subtitle: const Text('Chạy ở group test, chỉ admin và người test thấy'),
      value: _testMode,
      onChanged: _working ? null : (on) => setState(() => _testMode = on),
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
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'ID topic (không bắt buộc)',
          helperText: 'Bỏ trống thì bot đăng vào General',
        ),
      ),
    ),
  ];

  List<Widget> _submit(GameList list) => [
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
  ];

  // ---- Form theo tab ----

  Widget _tabbedForm(GameList list) {
    final preset = _preset(list);
    final values = _settingValues(list);
    final groups = list.groups;
    final tab = _tab.clamp(0, groups.length - 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
          if (preset != null) ...[
            const SizedBox(height: 8),
            Text(
              _edited ? 'Đã chỉnh từ kiểu ${preset.label}' : preset.summary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: _M.muted),
            ),
          ],
          const SizedBox(height: 16),
        ],
        GameCreatePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GameCreateLabel(
                'Tuỳ chỉnh',
                trailing: _edited
                    ? const Text(
                        'ĐÃ CHỈNH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: _M.amber,
                        ),
                      )
                    : null,
              ),
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
        GameCreatePanel(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.send_rounded, color: _M.amberBright),
              title: const Text('Bot đăng vào'),
              subtitle: Text(_postSummary()),
              children: _postFields(),
            ),
          ),
        ),
        ..._submit(list),
      ],
    );
  }

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
    final out = <Widget>[
      Align(
        alignment: Alignment.centerRight,
        child: GameCreateLink(
          'Là gì?',
          onTap: () => showGameCreateSheet(
            context,
            title: group.label,
            items: _explain(list, group, inGroup),
          ),
        ),
      ),
    ];
    if (group.key == 'time') out.add(_deadlineTile());
    if (group.key == 'roles') out.add(_roleGrid(list, live, values));
    for (final s in live) {
      if (s.section != null) continue;
      if (group.key == 'roles' && s.type == GameSetting.toggle) continue;
      if (shape != null) {
        // Độ dài vòng là tổng bốn pha trên vòng đồng hồ.
        if (s.key == 'roundHours') continue;
        if (s.key == 'startHour' || s.key == 'roundsPerDay') {
          out.add(_scheduleWidget(s, shape));
          continue;
        }
      }
      out.add(_settingWidget(s, values));
    }
    out.addAll(_sections(live, values));
    if (live.isEmpty && offNote != null) {
      out.add(GameCreateNote(icon: Icons.nightlight_round, text: offNote));
    }
    if (round != null && group.key == 'time' && round.start.isNotEmpty) {
      out
        ..add(const SizedBox(height: 10))
        ..add(GameCreateNote(icon: Icons.schedule_rounded, text: round.start));
    }
    if (round != null && shape != null && group.key == 'round') {
      out
        ..add(const SizedBox(height: 8))
        ..add(
          GameRoundDial(
            plan: round,
            phases: shape.phases,
            startMinute: shape.start,
            lockEnd: shape.lockEnd,
            maxTotal: shape.maxTotal,
            onChanged: _working ? null : (p) => _setPhases(shape.keys, p),
          ),
        );
    } else if (round != null &&
        group.key == 'round' &&
        round.phases.isNotEmpty) {
      out
        ..add(const SizedBox(height: 14))
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

  /// Giờ mở vòng đầu và số vòng mỗi ngày của tab Lịch khi có vòng đồng hồ:
  /// ván km chọn số vòng chia hết 24 tiếng, ván cổ điển chọn giờ mở và số vòng
  /// vừa trong ngày.
  Widget _scheduleWidget(GameSetting s, _RoundShape shape) {
    final total = shape.phases.fold<int>(0, (a, p) => a + p);
    void setRounds(int n) => setState(() => _settings[s.key] = n.toDouble());
    if (s.key == 'startHour') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GameScheduleCard(
          icon: Icons.nightlight_round,
          caption: 'MỞ VÒNG ĐẦU LÚC',
          title: '${shape.start ~/ 60}h',
          subtitle: 'Chạm để đổi giờ',
          onTap: _working ? null : () => _pickStartHour(s, shape.start ~/ 60),
        ),
      );
    }
    if (shape.lockEnd) {
      final lo = (s.min ?? 1).round(), hi = (s.max ?? 6).round();
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
                  if (24 % n == 0) n,
              ],
              selected: shape.rounds,
              length: (n) => gameHours(24 * 60 ~/ n),
              onSelect: _working ? null : setRounds,
            ),
          ],
        ),
      );
    }
    return GameCreateStepper(
      label: s.label,
      hint: 'Vòng ${gameHours(total)}',
      value: shape.rounds.toDouble(),
      min: s.min ?? 1,
      max: (24 * 60 ~/ total).toDouble(),
      step: 1,
      unit: s.unit,
      onChanged: _working ? null : (v) => setRounds(v.round()),
    );
  }

  /// Tuỳ chọn cùng `section` vẽ thành một khối có nhãn, theo thứ tự backend
  /// gửi: ô số trước, rồi thẻ bật tắt thu gọn được.
  List<Widget> _sections(List<GameSetting> live, Map<String, Object?> values) {
    final bySection = <String, List<GameSetting>>{};
    for (final s in live) {
      if (s.section case final section?) {
        (bySection[section] ??= []).add(s);
      }
    }
    return [
      for (final MapEntry(key: label, value: items) in bySection.entries) ...[
        const SizedBox(height: 12),
        GameCreateLabel(label),
        const SizedBox(height: 8),
        for (final s in items)
          if (s.type != GameSetting.toggle) _settingWidget(s, values),
        for (final s in items)
          if (s.type == GameSetting.toggle)
            GamePowerCard(
              setting: s,
              on: values[s.key] == true,
              onChanged: _working
                  ? null
                  : (v) => setState(() => _settings[s.key] = v),
            ),
      ],
    ];
  }

  static double _number(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;

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
        title: Text(s.label),
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
    List<GameSetting> inGroup,
  ) {
    final round = list.round;
    return [
      if (group.key == 'roles')
        for (final o in list.roleOptions)
          if (o.description.isNotEmpty) (o.label, o.description),
      if (group.key == 'round' && round != null)
        for (final p in round.phases) (p.label, p.description),
      for (final s in inGroup) ...[
        (s.label, s.description),
        for (final c in s.choices) ('· ${c.label}', c.description),
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
