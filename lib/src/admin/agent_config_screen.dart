import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Admin sửa trần và giá model của bot cá nhân. Nhãn, giải thích, đơn vị và
/// khoảng hợp lệ của từng ô đều lấy từ backend: admin cần đọc giải thích mới
/// biết đặt số nào, và backend thêm hay đổi field thì app không phải ra bản
/// mới.
class AgentConfigScreen extends ConsumerStatefulWidget {
  const AgentConfigScreen({super.key});

  @override
  ConsumerState<AgentConfigScreen> createState() => _AgentConfigScreenState();
}

class _AgentConfigScreenState extends ConsumerState<AgentConfigScreen> {
  AgentConfig? _config;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final config = await ref.read(runNowApiClientProvider).getAgentConfig();
      if (mounted) setState(() => _config = config);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
      // Đang có bản cũ trên màn thì vẫn để đó, nhưng phải báo: version cũ thì
      // lần lưu sau sẽ lại bị config_changed.
      if (_config != null) _toast(_errorText(error, 'Không tải lại được.'));
    }
  }

  /// Mỗi lần lưu gửi kèm version của lần đọc gần nhất. Thành công thì lấy
  /// luôn bản backend trả, kể cả version mới, khỏi phải GET lại.
  Future<void> _save({
    Map<String, num?>? values,
    List<AgentModelPrice>? prices,
  }) async {
    final config = _config;
    if (config == null || _busy) return;
    setState(() => _busy = true);
    try {
      final next = await ref
          .read(runNowApiClientProvider)
          .updateAgentConfig(
            version: config.version,
            values: values,
            prices: prices,
          );
      if (mounted) setState(() => _config = next);
    } on RunNowApiException catch (error) {
      if (error.code == 'config_changed') {
        _toast('Admin khác vừa sửa, đã tải lại');
        await _load();
      } else {
        _toast(error.message);
      }
    } catch (error) {
      _toast(_errorText(error, 'Không lưu được, thử lại sau.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editField(AgentConfigField field) async {
    final result = await showDialog<({num? value})>(
      context: context,
      builder: (context) => _FieldDialog(field: field),
    );
    if (result == null) return;
    await _save(values: {field.key: result.value});
  }

  /// [index] null là thêm dòng mới, [model] điền sẵn tên model.
  Future<void> _editPrice({int? index, String model = ''}) async {
    final config = _config;
    if (config == null) return;
    final initial = index == null
        ? AgentModelPrice(model: model, values: const {})
        : config.prices[index];
    final result = await showDialog<AgentModelPrice>(
      context: context,
      builder: (context) => _PriceDialog(
        initial: initial,
        adding: index == null,
        priceFields: config.priceFields,
        takenModels: {
          for (var i = 0; i < config.prices.length; i++)
            if (i != index) config.prices[i].model,
        },
      ),
    );
    if (result == null) return;
    final prices = [...config.prices];
    if (index == null) {
      prices.add(result);
    } else {
      prices[index] = result;
    }
    await _save(prices: prices);
  }

  Future<void> _deletePrice(int index) async {
    final config = _config;
    if (config == null) return;
    final model = config.prices[index].model;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá giá của $model?'),
        content: const Text(
          'Model này còn chạy thì bot tính theo giá dự phòng cao.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _save(prices: [...config.prices]..removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final config = _config;
    final Widget body;
    if (config == null) {
      final error = _loadError;
      body = Center(
        child: error == null
            ? const CircularProgressIndicator()
            : error is RunNowApiException && error.code == 'not_admin'
            ? const Text('Chỉ admin xem được trang này.')
            : TextButton(
                onPressed: _load,
                child: const Text('Không tải được. Chạm để thử lại.'),
              ),
      );
    } else {
      final heading = TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: palette.ink,
      );
      final muted = TextStyle(color: palette.textMuted);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _UsageCard(config: config),
          const SizedBox(height: 24),
          Text('Giới hạn', style: heading),
          const SizedBox(height: 8),
          for (final field in config.fields)
            _FieldCard(
              field: field,
              onEdit: _busy ? null : () => _editField(field),
            ),
          const SizedBox(height: 24),
          Text('Giá model', style: heading),
          Text(
            'Bot tính chi phí từng lượt theo bảng này. Bấm vào một dòng để '
            'xem từng cột nghĩa là gì.',
            style: muted,
          ),
          const SizedBox(height: 8),
          for (final model in config.models)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(model.model),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model.use.isNotEmpty) Text(model.use),
                  if (!model.priced) const _UnpricedWarning(),
                ],
              ),
              trailing: model.priced
                  ? null
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _editPrice(model: model.model),
                      child: const Text('Thêm giá'),
                    ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < config.prices.length; i++)
            _PriceCard(
              price: config.prices[i],
              priceFields: config.priceFields,
              onEdit: _busy ? null : () => _editPrice(index: i),
              onDelete: _busy ? null : () => _deletePrice(i),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _editPrice(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm dòng giá'),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Trần và giá'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: body,
    );
  }
}

String _errorText(Object error, String fallback) =>
    error is RunNowApiException ? error.message : fallback;

/// 3 thay vì 3.0, 0.075 giữ nguyên.
String _number(num? n) {
  if (n == null) return '—';
  if (n.isFinite && n == n.roundToDouble()) return '${n.toInt()}';
  return '$n';
}

String _withUnit(num? n, String unit) =>
    unit.isEmpty ? _number(n) : '${_number(n)} $unit';

String _usd(num n) => '\$${n.toStringAsFixed(2)}';

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.config});

  final AgentConfig config;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final usage = config.usage;
    // Trần là một field như mọi field khác; 0 hay chưa đặt là không chặn.
    final budgetField = config.field('dailyBudgetUsd');
    final budget = budgetField?.effective;
    final budgetText = budgetField == null
        ? null
        : budget == null || budget == 0
        ? 'không giới hạn'
        : 'trần ${_usd(budget)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hôm nay (${usage.day})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              [_usd(usage.costUsd), ?budgetText].join(' · '),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              '${usage.calls} lượt gọi · ${usage.searchCalls} lượt tìm kiếm',
              style: TextStyle(color: palette.textMuted),
            ),
            if (usage.budgetHit) ...[
              const SizedBox(height: 8),
              Text(
                'Đã chạm trần, bot đang nghỉ tới 0h',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.field, required this.onEdit});

  final AgentConfigField field;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = TextStyle(color: palette.textMuted);
    final current = field.value == null
        ? '${_withUnit(field.defaultValue, field.unit)} (mặc định)'
        : _withUnit(field.value, field.unit);
    return Card(
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (field.help.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(field.help, style: muted),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      current,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Mặc định: ${_withUnit(field.defaultValue, field.unit)}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sửa',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnpricedWarning extends StatelessWidget {
  const _UnpricedWarning();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Chưa có giá — đang tính theo giá dự phòng cao',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.price,
    required this.priceFields,
    required this.onEdit,
    required this.onDelete,
  });

  final AgentModelPrice price;
  final List<AgentPriceField> priceFields;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.runNowPalette.textMuted);
    return Card(
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      price.model,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sửa giá',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Xoá giá',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ],
              ),
              for (final f in priceFields)
                Text(
                  price.values[f.key] == null
                      ? '${f.label}: để trống'
                      : '${f.label}: ${_withUnit(price.values[f.key], f.unit)}',
                  style: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Đọc số admin gõ. Dấu phẩy coi như dấu chấm vì bàn phím tiếng Việt hay ra
/// dấu phẩy. Rỗng thì value và error đều null, nơi gọi tự quyết rỗng nghĩa
/// là gì.
({num? value, String? error}) _parseNumber(String raw, {bool isInt = false}) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return (value: null, error: null);
  if (isInt) {
    final n = int.tryParse(text);
    return n == null
        ? (value: null, error: 'Phải là số nguyên.')
        : (value: n, error: null);
  }
  final n = double.tryParse(text);
  return n == null || !n.isFinite
      ? (value: null, error: 'Phải là số.')
      : (value: n, error: null);
}

/// Pop `(value: n)` để lưu, `(value: null)` để về mặc định, null là huỷ.
class _FieldDialog extends StatefulWidget {
  const _FieldDialog({required this.field});

  final AgentConfigField field;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  // Chỉ điền giá trị đã đặt. Điền mặc định vào thì bấm Lưu sẽ ghim cứng số
  // đó, sau này backend đổi mặc định cũng không theo.
  late final _controller = TextEditingController(
    text: widget.field.value == null ? '' : _number(widget.field.value),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _range {
    final min = widget.field.min;
    final max = widget.field.max;
    return switch ((min, max)) {
      (final num lo, final num hi) => 'Từ ${_number(lo)} đến ${_number(hi)}',
      (final num lo, null) => 'Tối thiểu ${_number(lo)}',
      (null, final num hi) => 'Tối đa ${_number(hi)}',
      _ => null,
    };
  }

  void _submit() {
    final field = widget.field;
    final parsed = _parseNumber(_controller.text, isInt: field.isInt);
    final value = parsed.value;
    String? error = parsed.error;
    if (error == null && value == null) {
      error = 'Nhập một số, hoặc chọn Về mặc định.';
    }
    if (error == null &&
        value != null &&
        ((field.min != null && value < field.min!) ||
            (field.max != null && value > field.max!))) {
      error = '$_range.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((value: value));
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return AlertDialog(
      title: Text(field.label),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: field.isInt
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'Mặc định ${_number(field.defaultValue)}',
            helperText: _range,
            suffixText: field.unit.isEmpty ? null : field.unit,
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((value: null)),
          child: const Text('Về mặc định'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}

/// Sửa một dòng giá. Ô để trống gửi null; help của từng cột (backend gửi)
/// nói backend suy giá trống thế nào.
class _PriceDialog extends StatefulWidget {
  const _PriceDialog({
    required this.initial,
    required this.adding,
    required this.priceFields,
    required this.takenModels,
  });

  final AgentModelPrice initial;
  final bool adding;
  final List<AgentPriceField> priceFields;

  /// Model đã có dòng khác, để không tạo hai dòng cho một model.
  final Set<String> takenModels;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _model = TextEditingController(text: widget.initial.model);
  late final _numbers = {
    for (final f in widget.priceFields)
      f.key: TextEditingController(
        text: widget.initial.values[f.key] == null
            ? ''
            : _number(widget.initial.values[f.key]),
      ),
  };
  String? _modelError;
  final _errors = <String, String>{};

  @override
  void dispose() {
    _model.dispose();
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final model = _model.text.trim();
    final errors = <String, String>{};
    // Giữ cột app chưa biết từ dòng cũ, chỉ ghi đè cột đang hiện.
    final values = {...widget.initial.values};
    for (final f in widget.priceFields) {
      final parsed = _parseNumber(_numbers[f.key]!.text);
      final value = parsed.value;
      if (parsed.error != null) {
        errors[f.key] = parsed.error!;
      } else if (value != null && value < 0) {
        errors[f.key] = 'Không được âm.';
      }
      values[f.key] = value;
    }
    final modelError = model.isEmpty
        ? 'Nhập tên model.'
        : widget.takenModels.contains(model)
        ? 'Model này đã có dòng giá, sửa dòng đó.'
        : null;
    if (modelError != null || errors.isNotEmpty) {
      setState(() {
        _modelError = modelError;
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }
    Navigator.of(context).pop(AgentModelPrice(model: model, values: values));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.adding ? 'Thêm giá' : 'Sửa giá'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: 'Model',
                  errorText: _modelError,
                ),
              ),
              for (final f in widget.priceFields) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _numbers[f.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: f.label,
                    suffixText: f.unit.isEmpty ? null : f.unit,
                    helperText: f.help.isEmpty ? null : f.help,
                    helperMaxLines: 6,
                    errorText: _errors[f.key],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}
