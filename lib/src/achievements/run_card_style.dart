import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/achievements/run_card_look_sync.dart';
import 'package:myrun/src/achievements/run_card_models.dart';

/// Bộ thẻ: một cặp mặt trước, mặt sau cùng phong cách. Tên enum vào file lưu
/// trong máy và khoá cache ảnh khoe, nên không đổi tên.
enum RunCardSet {
  current('Hiện tại', ownColors: false),
  basic('Basic', ownColors: false, hasMapOption: true),
  splits('Từng km', ownColors: false, hasMapOption: true),
  blueprint('Bản vẽ', hasMapOption: true),
  city('Thành phố', hasMapOption: true),
  cassette('Cassette', hasMapOption: true),
  constellation('Chòm sao', hasMapOption: true),
  blocks('Khối chữ', hasMapOption: true),
  stopwatch('Đồng hồ', hasMapOption: true),
  flipBoard('Bảng lật', hasMapOption: true),
  bib('Số áo', hasMapOption: true),
  finish('Băng đích', hasMapOption: true),
  paperMap('Bản đồ', hasMapOption: true),
  receipt('Biên lai', hasMapOption: true),
  medal('Huy chương', hasMapOption: true),
  iron('Thép', hasMapOption: true),
  pixel('Pixel', ownColors: false, hasMapOption: true);

  const RunCardSet(
    this.label, {
    this.ownColors = true,
    this.hasMapOption = false,
  });

  final String label;

  /// Bộ có bảng màu riêng thì có ba kiểu chữ và không theo bộ màu thẻ.
  final bool ownColors;

  /// Mặt sau bật được bản đồ thật. Bộ Hiện tại luôn có sẵn nên không cần
  /// công tắc.
  final bool hasMapOption;
}

/// Cách đặt chữ ở mặt trước của các bộ có màu riêng.
enum RunCardTextLayout {
  full('Đầy đủ'),
  top('Số trên'),
  compact('Gọn');

  const RunCardTextLayout(this.label);

  final String label;
}

@immutable
class RunCardStyle {
  const RunCardStyle(this.set, [this.text = RunCardTextLayout.full])
    : map = false;

  const RunCardStyle.withMap(this.set, [this.text = RunCardTextLayout.full])
    : map = true;

  static const current = RunCardStyle(RunCardSet.current);

  final RunCardSet set;
  final RunCardTextLayout text;

  /// Mặt sau có bản đồ thật. Mặc định tắt vì bản đồ lộ khu xuất phát khi khoe.
  final bool map;

  /// Dạng lưu và vào khoá cache, ví dụ "blueprint.top", "city.top.map". Tắt
  /// bản đồ thì không có hậu tố, nên id và file khoe đã có trên máy vẫn dùng.
  String get id => '${set.name}.${text.name}${map ? '.$_mapSuffix' : ''}';

  static const _mapSuffix = 'map';

  static RunCardStyle? parse(String raw) {
    final parts = raw.split('.');
    if (parts.length < 2 || parts.length > 3) return null;
    if (parts.length == 3 && parts[2] != _mapSuffix) return null;
    final set = RunCardSet.values.asNameMap()[parts[0]];
    final text = RunCardTextLayout.values.asNameMap()[parts[1]];
    if (set == null || text == null) return null;
    return parts.length == 3
        ? RunCardStyle.withMap(set, text)
        : RunCardStyle(set, text);
  }

  @override
  bool operator ==(Object other) =>
      other is RunCardStyle &&
      other.set == set &&
      other.text == text &&
      other.map == map;

  @override
  int get hashCode => Object.hash(set, text, map);
}

/// Kiểu chủ thẻ đã lưu trên backend; null khi chưa lưu hoặc là bộ app này
/// chưa biết.
RunCardStyle? savedRunCardStyle(RunCard card) => switch (card.lookStyle) {
  final raw? => RunCardStyle.parse(raw),
  null => null,
};

/// Kiểu thẻ máy này chọn. Chỉ lưu trong máy như bộ màu: kiểu chỉ là lớp bọc
/// ngoài, không đụng số liệu thẻ, đổi máy thì về [RunCardStyle.current].
class RunCardStyleController extends ChangeNotifier {
  RunCardStyleController({
    FlutterSecureStorage? storage,
    bool loadFromStorage = true,
    this.onCardStyle,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    if (loadFromStorage) _load();
  }

  static const _key = 'runnow_card_style';

  /// Giữ vừa đủ để thẻ cũ vẫn tìm được kiểu lúc nó ra đời mà file lưu không
  /// phình mãi; quá mức này thì thẻ rất cũ về kiểu đầu danh sách còn lại.
  static const _maxDefaults = 40;

  final FlutterSecureStorage _storage;

  /// Gọi khi người dùng đặt kiểu cho một thẻ, để gửi lên backend.
  final void Function(String cardId, RunCardStyle style)? onCardStyle;

  var _defaults = <({int at, RunCardStyle style})>[];
  var _cards = <String, RunCardStyle>{};

  /// Thẻ vừa đặt kiểu trong phiên này: tin máy cho tới khi backend lưu xong.
  final _session = <String>{};

  /// Người dùng đã chọn trong phiên thì giá trị đọc muộn từ máy không được đè.
  bool _chosen = false;

  /// Đổi mỗi lần lựa chọn đổi, để scope báo các thẻ vẽ lại.
  int revision = 0;

  /// Kiểu của [card]. Thẻ người khác khoe mặc đúng kiểu chủ thẻ đã lưu, chưa
  /// lưu thì kiểu gốc. Thẻ của mình theo [styleOf].
  RunCardStyle styleFor(RunCard card) {
    final saved = savedRunCardStyle(card);
    if (card.ownerUid != null) return saved ?? RunCardStyle.current;
    return styleOf(card.id, card.rolledAt, saved: saved);
  }

  /// Kiểu của thẻ của mình: kiểu vừa đặt trong phiên, rồi [saved] là kiểu đã
  /// lưu trên backend (đặt từ máy nào cũng thấy), rồi tới lựa chọn máy này giữ.
  RunCardStyle styleOf(
    String cardId,
    DateTime? rolledAt, {
    RunCardStyle? saved,
  }) {
    if (_session.contains(cardId)) return _cards[cardId]!;
    return saved ?? localStyleOf(cardId, rolledAt) ?? RunCardStyle.current;
  }

  /// Lựa chọn máy này giữ cho thẻ: kiểu riêng của thẻ nếu có; không thì mặc
  /// định còn hiệu lực lúc lật thẻ đó, nên đổi mặc định không làm thẻ cũ đổi
  /// theo. Null là máy này chưa chọn gì cho thẻ.
  RunCardStyle? localStyleOf(String cardId, DateTime? rolledAt) {
    final own = _cards[cardId];
    if (own != null) return own;
    final at = rolledAt?.millisecondsSinceEpoch;
    if (at == null) return null;
    for (final item in _defaults.reversed) {
      if (item.at <= at) return item.style;
    }
    return null;
  }

  /// Áp [style] cho thẻ đang xem và làm mặc định cho thẻ lật từ giờ.
  Future<void> apply(RunCardStyle style, {String? cardId, DateTime? now}) {
    _chosen = true;
    if (cardId != null) {
      _cards[cardId] = style;
      _session.add(cardId);
      onCardStyle?.call(cardId, style);
    }
    if (_defaults.isEmpty || _defaults.last.style != style) {
      _defaults = [
        ..._defaults,
        (at: (now ?? DateTime.now()).millisecondsSinceEpoch, style: style),
      ];
      if (_defaults.length > _maxDefaults) {
        _defaults = _defaults.sublist(_defaults.length - _maxDefaults);
      }
    }
    revision++;
    notifyListeners();
    return _storage.write(key: _key, value: encode());
  }

  @visibleForTesting
  String encode() => jsonEncode({
    'd': [
      for (final item in _defaults) [item.at, item.style.id],
    ],
    'c': {for (final e in _cards.entries) e.key: e.value.id},
  });

  /// Sai dạng thì coi như chưa chọn gì, thẻ vẫn vẽ được kiểu gốc.
  @visibleForTesting
  void decode(String? raw) {
    if (raw == null) return;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException catch (error) {
      debugPrint('Kiểu thẻ đã lưu hỏng: $error');
      return;
    }
    if (json is! Map) return;
    _defaults = [
      if (json['d'] case final List items)
        for (final item in items)
          if (item case [final int at, final String id])
            if (RunCardStyle.parse(id) case final style?)
              (at: at, style: style),
    ];
    _cards = {
      if (json['c'] case final Map cards)
        for (final e in cards.entries)
          if (e.value case final String id)
            e.key.toString(): ?RunCardStyle.parse(id),
    };
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _key);
    if (_chosen || raw == null) return;
    decode(raw);
    revision++;
    notifyListeners();
  }
}

final runCardStyleControllerProvider =
    ChangeNotifierProvider<RunCardStyleController>(
      (ref) => RunCardStyleController(
        onCardStyle: (cardId, style) =>
            ref.read(runCardLookSyncProvider).cardStyle(cardId, style.id),
      ),
    );

/// Đặt kiểu cho mọi thẻ buổi chạy bên dưới, cùng cách với bộ màu.
class RunCardStyleScope extends InheritedWidget {
  const RunCardStyleScope({
    super.key,
    required this.resolve,
    required this.revision,
    required super.child,
  });

  /// Mọi thẻ bên dưới mặc đúng [style]: xem trước và màn khoe.
  RunCardStyleScope.fixed({
    super.key,
    required RunCardStyle style,
    required super.child,
  }) : resolve = ((_) => style),
       revision = style.hashCode;

  final RunCardStyle Function(RunCard card) resolve;
  final int revision;

  /// Thẻ Ẩn luôn mặc kiểu gốc. Ngoài scope cũng là kiểu gốc.
  static RunCardStyle of(BuildContext context, RunCard card) {
    if (card.secret != null) return RunCardStyle.current;
    final scope = context
        .dependOnInheritedWidgetOfExactType<RunCardStyleScope>();
    return scope?.resolve(card) ?? RunCardStyle.current;
  }

  @override
  bool updateShouldNotify(RunCardStyleScope old) => old.revision != revision;
}

/// Đọc danh sách bộ từ giá trị Remote Config `run_card_sets`, dạng
/// "basic,medal,receipt". Tên chưa biết (bộ của bản app mới hơn) thì bỏ qua;
/// rỗng thì đủ mọi bộ theo thứ tự gốc.
List<RunCardSet> parseRunCardSets(String raw) {
  final known = RunCardSet.values.asNameMap();
  final picked = [for (final name in raw.split(',')) ?known[name.trim()]];
  return picked.isEmpty ? RunCardSet.values : picked.toSet().toList();
}

/// Bộ hiện ở sheet chọn và thứ tự, để đổi hay tắt một bộ không cần ra app mới.
final runCardSetsProvider = StreamProvider<List<RunCardSet>>((ref) async* {
  final rc = FirebaseRemoteConfig.instance;
  List<RunCardSet> read() {
    try {
      return parseRunCardSets(rc.getString('run_card_sets'));
    } catch (error) {
      debugPrint('Không đọc được run_card_sets: $error');
      return RunCardSet.values;
    }
  }

  yield read();
  try {
    await for (final _ in rc.onConfigUpdated) {
      await rc.activate();
      yield read();
    }
  } catch (error) {
    debugPrint('Remote Config run_card_sets ngừng cập nhật: $error');
  }
});
