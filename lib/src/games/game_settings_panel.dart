import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_models.dart';

/// Các tuỳ chọn luật trên màn tạo ván, vẽ theo `createOptions.settings`. Mỗi
/// tuỳ chọn hiện tên và mô tả để người tạo ván biết nó làm gì. Tuỳ chọn có
/// điều kiện bật chưa đúng thì làm mờ và không bấm được.
class GameSettingsPanel extends StatelessWidget {
  const GameSettingsPanel({
    super.key,
    required this.settings,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  /// Chỉ gồm tuỳ chọn app biết vẽ, xem [gameSettingSupported].
  final List<GameSetting> settings;

  /// Giá trị hiện tại theo key, đã gồm mặc định.
  final Map<String, Object?> values;
  final void Function(String key, Object value) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final setting in settings)
          _tile(setting, enabled && setting.enabledBy(values)),
      ],
    );
  }

  Widget _tile(GameSetting setting, bool on) {
    final value = values[setting.key];
    final title = Text(setting.label);
    final subtitle = Text(setting.description);
    switch (setting.type) {
      case GameSetting.toggle:
        return SwitchListTile(
          title: title,
          subtitle: subtitle,
          value: value == true,
          onChanged: on ? (v) => onChanged(setting.key, v) : null,
        );
      case GameSetting.number:
        final n = (value as num? ?? setting.min ?? 0).toDouble();
        final step = setting.step ?? 1;
        final lo = setting.min ?? double.negativeInfinity;
        final hi = setting.max ?? double.infinity;
        final unit = setting.unit;
        return ListTile(
          enabled: on,
          title: title,
          subtitle: subtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Giảm ${setting.label}',
                icon: const Icon(Icons.remove_rounded),
                onPressed: on && n - step >= lo - 1e-9
                    ? () => onChanged(setting.key, _snap(n - step))
                    : null,
              ),
              Text(unit == null ? _format(n) : '${_format(n)} $unit'),
              IconButton(
                tooltip: 'Tăng ${setting.label}',
                icon: const Icon(Icons.add_rounded),
                onPressed: on && n + step <= hi + 1e-9
                    ? () => onChanged(setting.key, _snap(n + step))
                    : null,
              ),
            ],
          ),
        );
      default: // GameSetting.choice
        return RadioGroup<String>(
          groupValue: value as String?,
          onChanged: (v) {
            if (on && v != null) onChanged(setting.key, v);
          },
          child: Column(
            children: [
              ListTile(enabled: on, title: title, subtitle: subtitle),
              for (final choice in setting.choices)
                RadioListTile<String>(
                  enabled: on,
                  value: choice.value,
                  title: Text(choice.label),
                  subtitle: Text(choice.description),
                ),
            ],
          ),
        );
    }
  }
}

/// App cũ gặp kiểu tuỳ chọn mới thì bỏ qua; backend tự áp giá trị mặc định.
bool gameSettingSupported(GameSetting setting) => switch (setting.type) {
  GameSetting.toggle || GameSetting.number => true,
  GameSetting.choice => setting.choices.isNotEmpty,
  _ => false,
};

/// Cộng trừ số lẻ như 0.5 cộng dồn sai số; làm tròn để gửi đúng bước.
double _snap(double v) => (v * 1000).roundToDouble() / 1000;

String _format(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
