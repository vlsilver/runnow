import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

/// Thẻ Quản trò của tab Giao tiếp. Ván nào cũng có Quản trò; chủ ván chọn tính
/// cách và có đưa Quản trò lên Telegram không. [telegramBody] là chỗ chọn
/// group, chỉ hiện khi bật Telegram.
class GameHostCard extends StatefulWidget {
  const GameHostCard({
    super.key,
    required this.summary,
    required this.persona,
    required this.personaValue,
    required this.onPersona,
    required this.telegram,
    required this.telegramOn,
    required this.onTelegram,
    required this.telegramBody,
  });

  /// Dòng dưới tên: Quản trò nói ở đâu.
  final String summary;

  /// Ô tính cách backend gửi; null là backend không có.
  final GameSetting? persona;
  final String personaValue;
  final ValueChanged<String>? onPersona;

  /// Công tắc Telegram backend gửi; null là backend không có.
  final GameSetting? telegram;
  final bool telegramOn;
  final ValueChanged<bool>? onTelegram;
  final Widget telegramBody;

  @override
  State<GameHostCard> createState() => _GameHostCardState();
}

class _GameHostCardState extends State<GameHostCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final persona = widget.persona;
    final telegram = widget.telegram;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: context.runNowPalette.radius(12),
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.moonlit.amber,
                      borderRadius: context.runNowPalette.radius(12),
                    ),
                    child: Text(
                      'QT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: context.moonlit.onAmber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quản trò',
                          style: TextStyle(
                            fontFamily: 'Barlow Condensed',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: context.moonlit.ink,
                          ),
                        ),
                        Text(
                          widget.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.moonlit.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: context.moonlit.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            if (persona != null) ...[
              const SizedBox(height: 12),
              _PersonaBlock(
                setting: persona,
                value: widget.personaValue,
                onChanged: widget.onPersona,
              ),
            ],
            if (telegram != null) ...[
              const SizedBox(height: 12),
              _Row(
                icon: Icons.send_rounded,
                title: 'Lên Telegram',
                sub: widget.telegramOn
                    ? 'Người chơi cần liên kết Telegram'
                    : 'Quản trò chỉ nói trong app',
                trailing: RunNowSwitch(
                  value: widget.telegramOn,
                  onChanged: widget.onTelegram,
                ),
              ),
            ],
            if (telegram == null || widget.telegramOn) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.moonlit.border, width: 2),
                  ),
                ),
                child: widget.telegramBody,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Tính cách: chip soạn sẵn chọn ngay trên thẻ, "Sửa lời dặn" mở sheet có lời
/// dặn đang dùng. Lời dặn khác mọi bản soạn sẵn là "Tự viết".
class _PersonaBlock extends StatelessWidget {
  const _PersonaBlock({
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final GameSetting setting;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = setting.presets;
    final picked = presets.where((p) => p.text == value.trim()).firstOrNull;
    final sub =
        picked?.label ?? (value.trim().isEmpty ? 'Giọng mặc định' : value);
    final onChanged = this.onChanged;
    return _Row(
      icon: Icons.star_outline_rounded,
      title: setting.label,
      sub: sub,
      trailing: TextButton(
        onPressed: onChanged == null
            ? null
            : () => _editPersona(context, setting, value, onChanged),
        child: const Text('Sửa lời dặn'),
      ),
      below: presets.isEmpty
          ? null
          : GamePersonaChips(
              presets: presets,
              value: value,
              onChanged: onChanged,
            ),
    );
  }
}

/// Chip các tính cách soạn sẵn và "Tự viết". Chạm chip là điền lời dặn của
/// chip; "Tự viết" xoá trắng cho người tạo tự viết.
class GamePersonaChips extends StatelessWidget {
  const GamePersonaChips({
    super.key,
    required this.presets,
    required this.value,
    required this.onChanged,
  });

  final List<({String label, String text})> presets;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final picked = presets.indexWhere((p) => p.text == value.trim());
    final onChanged = this.onChanged;
    Widget chip(String label, bool selected, String next) => ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onChanged == null ? null : (_) => onChanged(next),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: selected ? context.moonlit.amberBright : context.moonlit.muted,
      ),
      backgroundColor: context.moonlit.panel,
      selectedColor: context.moonlit.amberTint,
      side: BorderSide(
        color: selected ? context.moonlit.amber : context.moonlit.border,
      ),
      shape: context.runNowPalette.pillBorder,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < presets.length; i++)
          chip(presets[i].label, picked == i, presets[i].text),
        chip('Tự viết', picked < 0, picked < 0 ? value : ''),
      ],
    );
  }
}

Future<void> _editPersona(
  BuildContext context,
  GameSetting setting,
  String value,
  ValueChanged<String> onSave,
) async {
  final saved = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.moonlit.panel,
    showDragHandle: true,
    builder: (context) => _PersonaSheet(setting: setting, initial: value),
  );
  if (saved != null) onSave(saved);
}

class _PersonaSheet extends StatefulWidget {
  const _PersonaSheet({required this.setting, required this.initial});

  final GameSetting setting;
  final String initial;

  @override
  State<_PersonaSheet> createState() => _PersonaSheetState();
}

class _PersonaSheetState extends State<_PersonaSheet> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: context.moonlit.ink,
              ),
            ),
            if (s.presets.isNotEmpty) ...[
              const SizedBox(height: 12),
              GamePersonaChips(
                presets: s.presets,
                value: _text.text,
                onChanged: (v) => setState(() => _text.text = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: s.lines < 3 ? 6 : s.lines + 2,
              maxLength: s.max?.toInt(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Lời dặn cho Quản trò',
                helperText: s.description.isEmpty ? null : s.description,
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _text.text.trim()),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ Phòng chung và Thoại dưới thẻ Quản trò.
class GameTalkChannels extends StatelessWidget {
  const GameTalkChannels({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 12),
        _Panel(
          child: _Row(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Phòng chung',
            sub: 'Luôn có, mở từ lúc đăng ký',
          ),
        ),
        SizedBox(height: 12),
        Opacity(
          opacity: 0.55,
          child: _Panel(
            child: _Row(
              icon: Icons.mic_none_rounded,
              title: 'Thoại',
              sub: 'Nói chuyện lúc bàn ban ngày',
              trailing: Text(
                'SẮP CÓ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.moonlit.faint,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.moonlit.raised,
        borderRadius: context.runNowPalette.radius(18),
        border: Border.all(color: context.moonlit.border),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.sub,
    this.trailing,
    this.below,
  });

  final IconData icon;
  final String title;
  final String sub;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: context.moonlit.amberTint,
            borderRadius: context.runNowPalette.radius(10),
          ),
          child: Icon(icon, size: 17, color: context.moonlit.amberBright),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: context.moonlit.ink,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.moonlit.muted),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
    final below = this.below;
    if (below == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, const SizedBox(height: 10), below],
    );
  }
}
