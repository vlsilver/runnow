import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

/// Một phần chủ thẻ chỉnh được trên mặt trước. [code] vào chuỗi lưu trên
/// backend nên không đổi.
enum CardPart {
  km('km', 'Số km', canHide: false),
  time('time', 'Thời gian'),
  pace('pace', 'Pace'),
  route('route', 'Đường chạy');

  const CardPart(this.code, this.label, {this.canHide = true});

  final String code;
  final String label;

  /// Thẻ buổi chạy luôn phải có km, nên số km không ẩn được.
  final bool canHide;
}

/// Màu chủ thẻ tô cho một phần: một trong các màu đặc trưng của bộ (theo thứ
/// tự bộ đó khai), hay một màu tự chọn.
@immutable
sealed class PartColor {
  const PartColor();

  /// Mã trong chuỗi lưu: số thứ tự màu đặc trưng, hay sáu chữ hex.
  String get code;

  static PartColor? parse(String raw) {
    if (RegExp(r'^[0-9]$').hasMatch(raw)) return PartTone(int.parse(raw));
    if (RegExp(r'^[0-9a-f]{6}$').hasMatch(raw)) {
      return PartCustom(Color(int.parse(raw, radix: 16)));
    }
    return null;
  }
}

final class PartTone extends PartColor {
  const PartTone(this.index);

  final int index;

  @override
  String get code => '$index';

  @override
  bool operator ==(Object other) => other is PartTone && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

final class PartCustom extends PartColor {
  /// Chỉ giữ màu đặc, vì chuỗi lưu không có kênh alpha.
  PartCustom(Color color) : color = color.withAlpha(0xFF);

  final Color color;

  @override
  String get code =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

  @override
  bool operator ==(Object other) => other is PartCustom && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Những gì chủ thẻ đổi ở một phần. [x], [y] null là phần còn đứng ở chỗ
/// gốc của bộ; có thì là điểm neo của phần, theo phần trăm khung (0..100).
/// [color] null là màu gốc.
@immutable
class PartPlacement {
  const PartPlacement({
    this.x,
    this.y,
    this.size = 2,
    this.hidden = false,
    this.color,
  }) : assert((x == null) == (y == null));

  static const initial = PartPlacement();

  final int? x;
  final int? y;
  final int size;
  final bool hidden;
  final PartColor? color;

  static const scales = [0.7, 0.85, 1.0, 1.2, 1.45];

  double get scale => scales[size];

  bool get moved => x != null;

  PartPlacement moveTo(int x, int y) =>
      PartPlacement(x: x, y: y, size: size, hidden: hidden, color: color);

  PartPlacement copyWith({int? size, bool? hidden, PartColor? color}) =>
      PartPlacement(
        x: x,
        y: y,
        size: size ?? this.size,
        hidden: hidden ?? this.hidden,
        color: color ?? this.color,
      );

  /// Tô [color]; null là trả về màu gốc của bộ.
  PartPlacement withColor(PartColor? color) =>
      PartPlacement(x: x, y: y, size: size, hidden: hidden, color: color);

  @override
  bool operator ==(Object other) =>
      other is PartPlacement &&
      other.x == x &&
      other.y == y &&
      other.size == size &&
      other.hidden == hidden &&
      other.color == color;

  @override
  int get hashCode => Object.hash(x, y, size, hidden, color);
}

/// Những phần chủ thẻ đã chỉnh trên mặt trước; phần không có ở đây vẽ y như
/// bộ thẻ gốc.
///
/// Dạng lưu ([code]) là "km:30,66,2;time:,,3,h1;route:50,30,2,ff8800": chỗ
/// để trống là chưa dời, trường thứ tư là cờ "h" (ẩn) rồi mã [PartColor].
/// Backend chỉ kiểm chữ thường, số và ":,;" tối đa 200 ký tự, không đọc nội
/// dung. Phần nào lạ hay sai thì bỏ, để bản app sau thêm phần mới vẫn đọc
/// được chuỗi cũ và ngược lại.
@immutable
class RunCardLayout {
  const RunCardLayout([this.parts = const {}]);

  static const initial = RunCardLayout();

  final Map<CardPart, PartPlacement> parts;

  PartPlacement of(CardPart part) => parts[part] ?? PartPlacement.initial;

  /// Đặt lại [part]; về y như gốc thì bỏ khỏi chuỗi lưu.
  RunCardLayout place(CardPart part, PartPlacement placement) {
    final fixed = part.canHide ? placement : placement.copyWith(hidden: false);
    return RunCardLayout({
      for (final MapEntry(:key, :value) in parts.entries)
        if (key != part) key: value,
      if (fixed != PartPlacement.initial) part: fixed,
    });
  }

  String get code => [
    for (final part in CardPart.values)
      if (parts[part] case final p?)
        '${part.code}:${p.x ?? ''},${p.y ?? ''},${p.size}${_flags(p)}',
  ].join(';');

  static String _flags(PartPlacement p) {
    final flags = '${p.hidden ? 'h' : ''}${p.color?.code ?? ''}';
    return flags.isEmpty ? '' : ',$flags';
  }

  /// [raw] là `look.layout` của doc thẻ.
  static RunCardLayout parse(String? raw) {
    final names = {for (final p in CardPart.values) p.code: p};
    var layout = initial;
    for (final item in (raw ?? '').split(';')) {
      if (item.split(':') case [final key, final value]) {
        final part = names[key];
        final placement = _placement(value);
        if (part == null || placement == null) continue;
        layout = layout.place(part, placement);
      }
    }
    return layout;
  }

  static int? _percent(String raw) => switch (int.tryParse(raw)) {
    final v? when v >= 0 && v <= 100 => v,
    _ => null,
  };

  static PartPlacement? _placement(String raw) {
    final bits = raw.split(',');
    if (bits.length < 3 || bits.length > 4) return null;
    final at = bits[0].isEmpty && bits[1].isEmpty
        ? null
        : (_percent(bits[0]), _percent(bits[1]));
    if (at != null && (at.$1 == null || at.$2 == null)) return null;
    final size = int.tryParse(bits[2]);
    if (size == null || size < 0 || size >= PartPlacement.scales.length) {
      return null;
    }
    final flags = bits.length == 4 ? bits[3] : '';
    final hidden = flags.startsWith('h');
    final rest = hidden ? flags.substring(1) : flags;
    final color = rest.isEmpty ? null : PartColor.parse(rest);
    if (rest.isNotEmpty && color == null) return null;
    return PartPlacement(
      x: at?.$1,
      y: at?.$2,
      size: size,
      hidden: hidden,
      color: color,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RunCardLayout && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
