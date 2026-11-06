import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/games/game_settings_panel.dart';
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
    return out.isEmpty ? null : out;
  }

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
    return ListTile(
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
      if (group.key == 'roles' && s.type == GameSetting.toggle) continue;
      out.add(_settingWidget(s, values));
    }
    if (live.isEmpty && offNote != null) {
      out.add(GameCreateNote(icon: Icons.nightlight_round, text: offNote));
    }
    if (round != null && group.key == 'time' && round.start.isNotEmpty) {
      out
        ..add(const SizedBox(height: 10))
        ..add(GameCreateNote(icon: Icons.schedule_rounded, text: round.start));
    }
    if (round != null && group.key == 'round' && round.phases.isNotEmpty) {
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
        if (s.type == GameSetting.toggle)
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
