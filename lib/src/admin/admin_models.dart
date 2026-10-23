/// Trang admin: uid theo từng quyền và chat Telegram mà api đang dùng. Token
/// không có ở đây, backend không trả ra.
class AdminSettings {
  const AdminSettings({
    required this.roles,
    required this.chatId,
    required this.botUsername,
  });

  factory AdminSettings.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'] is Map ? json['roles'] as Map : const {};
    final telegram = json['telegram'] is Map
        ? json['telegram'] as Map
        : const {};
    return AdminSettings(
      roles: {
        for (final entry in roles.entries)
          '${entry.key}': [
            if (entry.value is List)
              for (final uid in entry.value as List) '$uid',
          ],
      },
      chatId: '${telegram['chatId'] ?? ''}',
      botUsername: '${telegram['botUsername'] ?? ''}',
    );
  }

  final Map<String, List<String>> roles;
  final String chatId;
  final String botUsername;

  List<String> uidsOf(String role) => roles[role] ?? const [];
}

/// Trần, giá model và chi phí hôm nay của bot cá nhân. Nhãn, giải thích, giới
/// hạn của từng field đều do backend gửi, app chỉ dựng lại, nên thêm hay đổi
/// field không cần ra bản app mới.
class AgentConfig {
  const AgentConfig({
    required this.fields,
    required this.priceFields,
    required this.prices,
    required this.models,
    required this.usage,
    required this.version,
  });

  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> objects(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (item is Map<String, dynamic>) item,
    ];
    return AgentConfig(
      fields: [
        for (final f in objects(json['fields'])) AgentConfigField.fromJson(f),
      ],
      priceFields: [
        for (final f in objects(json['priceFields']))
          AgentPriceField.fromJson(f),
      ],
      prices: [
        for (final p in objects(json['prices'])) AgentModelPrice.fromJson(p),
      ],
      models: [
        for (final m in objects(json['models'])) AgentRunningModel.fromJson(m),
      ],
      usage: AgentUsage.fromJson(
        json['usage'] is Map<String, dynamic>
            ? json['usage'] as Map<String, dynamic>
            : const {},
      ),
      version: '${json['version'] ?? ''}',
    );
  }

  final List<AgentConfigField> fields;
  final List<AgentPriceField> priceFields;
  final List<AgentModelPrice> prices;

  /// Model backend đang chạy, kể cả model chưa có dòng trong [prices].
  final List<AgentRunningModel> models;
  final AgentUsage usage;

  /// Gửi lại khi sửa để backend biết mình sửa trên bản nào. Rỗng là chưa ai
  /// lưu lần nào.
  final String version;

  AgentConfigField? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}

class AgentConfigField {
  const AgentConfigField({
    required this.key,
    required this.label,
    required this.help,
    required this.kind,
    required this.unit,
    this.min,
    this.max,
    this.defaultValue,
    this.value,
  });

  factory AgentConfigField.fromJson(Map<String, dynamic> json) =>
      AgentConfigField(
        key: '${json['key'] ?? ''}',
        label: '${json['label'] ?? json['key'] ?? ''}',
        help: '${json['help'] ?? ''}',
        kind: '${json['kind'] ?? 'number'}',
        unit: '${json['unit'] ?? ''}',
        min: json['min'] as num?,
        max: json['max'] as num?,
        defaultValue: json['default'] as num?,
        value: json['value'] as num?,
      );

  final String key;
  final String label;
  final String help;

  /// `int` hay `number`. Kind lạ coi như `number`: nhập được số thập phân,
  /// còn lại để backend kiểm.
  final String kind;
  final String unit;
  final num? min;
  final num? max;
  final num? defaultValue;

  /// null là chưa đặt, backend dùng [defaultValue].
  final num? value;

  bool get isInt => kind == 'int';
  num? get effective => value ?? defaultValue;
}

class AgentPriceField {
  const AgentPriceField({
    required this.key,
    required this.label,
    required this.help,
    required this.unit,
  });

  factory AgentPriceField.fromJson(Map<String, dynamic> json) =>
      AgentPriceField(
        key: '${json['key'] ?? ''}',
        label: '${json['label'] ?? json['key'] ?? ''}',
        help: '${json['help'] ?? ''}',
        unit: '${json['unit'] ?? ''}',
      );

  final String key;
  final String label;
  final String help;
  final String unit;
}

/// Một dòng giá. Giữ mọi cột số backend gửi, kể cả cột app chưa biết, vì lưu
/// là gửi cả mảng: bỏ cột lạ thì lần lưu sau xoá mất giá đó.
class AgentModelPrice {
  const AgentModelPrice({required this.model, required this.values});

  factory AgentModelPrice.fromJson(Map<String, dynamic> json) =>
      AgentModelPrice(
        model: '${json['model'] ?? ''}',
        values: {
          for (final entry in json.entries)
            if (entry.key != 'model' && entry.value is num?)
              entry.key: entry.value as num?,
        },
      );

  final String model;

  /// null là để trống, backend tự suy (help của từng cột nói suy thế nào).
  final Map<String, num?> values;

  Map<String, dynamic> toJson() => {'model': model, ...values};
}

class AgentRunningModel {
  const AgentRunningModel({
    required this.model,
    required this.use,
    required this.priced,
  });

  factory AgentRunningModel.fromJson(Map<String, dynamic> json) =>
      AgentRunningModel(
        model: '${json['model'] ?? ''}',
        use: '${json['use'] ?? ''}',
        priced: json['priced'] == true,
      );

  final String model;
  final String use;
  final bool priced;
}

class AgentUsage {
  const AgentUsage({
    required this.day,
    required this.costUsd,
    required this.calls,
    required this.searchCalls,
    required this.budgetHit,
  });

  factory AgentUsage.fromJson(Map<String, dynamic> json) => AgentUsage(
    day: '${json['day'] ?? ''}',
    costUsd: (json['costUsd'] as num?) ?? 0,
    calls: (json['calls'] as num?)?.toInt() ?? 0,
    searchCalls: (json['searchCalls'] as num?)?.toInt() ?? 0,
    budgetHit: json['budgetHit'] == true,
  );

  final String day;
  final num costUsd;
  final int calls;
  final int searchCalls;
  final bool budgetHit;
}
