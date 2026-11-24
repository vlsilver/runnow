import 'package:flutter/widgets.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';

/// Khung thiết kế của mặt thẻ, cùng toạ độ với `faceBox`.
const editFaceSize = Size(300, 420);

/// Một màu đặc trưng của bộ thẻ, hiện ở hàng màu đầu tiên của màn chỉnh.
typedef FaceTone = ({String label, Color color});

/// Bố cục chủ thẻ đã chỉnh cho mặt trước đang vẽ, cùng các màu đặc trưng của
/// bộ để đọc [PartTone]. Đặt quanh cả mặt trước, kèm [link] gắn ở góc trên
/// trái mặt thẻ để phần đã dời vẽ theo toạ độ thẻ.
class CardPartsScope extends InheritedWidget {
  const CardPartsScope({
    super.key,
    required this.layout,
    required this.tones,
    required this.link,
    required super.child,
  });

  final RunCardLayout layout;
  final List<FaceTone> tones;
  final LayerLink link;

  static CardPartsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardPartsScope>();

  /// Màu thật của [color]; null là phần giữ màu gốc.
  Color? colorOf(PartColor? color) => switch (color) {
    null => null,
    PartCustom(:final color) => color,
    PartTone(:final index) => index < tones.length ? tones[index].color : null,
  };

  @override
  bool updateShouldNotify(CardPartsScope old) =>
      old.layout != layout || old.tones != tones || old.link != link;
}

/// Bọc [face] (cả mặt trước) để các [PartSlot] bên trong đọc bố cục.
Widget withCardParts({
  required RunCardLayout layout,
  required List<FaceTone> tones,
  required Widget face,
}) {
  final link = LayerLink();
  return CardPartsScope(
    layout: layout,
    tones: tones,
    link: link,
    child: CompositedTransformTarget(
      link: link,
      child: Builder(
        builder: (context) => switch (CardEditScope.maybeOf(context)) {
          final edit? => KeyedSubtree(key: edit.face, child: face),
          null => face,
        },
      ),
    ),
  );
}

/// Màn chỉnh đặt scope này quanh thẻ: mỗi phần gắn [keys] để màn đo chỗ mà
/// kéo, phần [selected] có khung. [face] gắn vào mặt trước, nơi chữ lấy toạ
/// độ; [art] gắn vào vùng tranh, nơi đường chạy lấy toạ độ.
class CardEditScope extends InheritedWidget {
  const CardEditScope({
    super.key,
    required this.keys,
    required this.face,
    required this.art,
    required this.selected,
    required this.outline,
    required super.child,
  });

  final Map<CardPart, GlobalKey> keys;
  final GlobalKey face;
  final GlobalKey art;
  final CardPart? selected;

  /// Màu khung của phần đang chọn.
  final Color outline;

  static CardEditScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardEditScope>();

  @override
  bool updateShouldNotify(CardEditScope old) =>
      old.selected != selected ||
      old.keys != keys ||
      old.face != face ||
      old.art != art ||
      old.outline != outline;
}

/// Khe của một phần chữ trong bố cục gốc của bộ. Chưa chỉnh thì vẽ y như
/// [child]; đổi cỡ thì to ra từ [anchor]; tô màu thì phủ màu lên nét; dời thì
/// vẽ ở chỗ đã lưu trên thẻ, khe vẫn giữ chỗ để phần còn lại của bộ không xê
/// dịch.
class PartSlot extends StatelessWidget {
  const PartSlot(
    this.part, {
    super.key,
    this.anchor = Alignment.center,
    this.tint = true,
    required this.child,
  });

  final CardPart part;

  /// Tô cả phần bằng màu chọn. Tắt khi phần tự vẽ màu chọn vào nét của nó
  /// (con dấu đường chạy: tô cả khối thì nền dấu thành một mảng màu).
  final bool tint;

  /// Điểm của phần nằm ở toạ độ đã lưu, cũng là điểm phần to ra từ đó. Đặt
  /// theo góc mà bố cục gốc bám vào (số km bám đáy trái).
  final Alignment anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = CardPartsScope.maybeOf(context);
    final edit = CardEditScope.maybeOf(context);
    if (scope == null) return child;
    final at = scope.layout.of(part);
    Widget body = child;
    if (at.hidden) {
      // Trong màn chỉnh vẫn gắn khoá, để màn biết bộ có phần này mà cho hiện lại.
      if (edit != null) {
        body = _Editable(
          key: edit.keys[part],
          anchor: anchor,
          selected: false,
          color: edit.outline,
          child: body,
        );
      }
      return Visibility.maintain(visible: false, child: body);
    }
    if (scope.colorOf(at.color) case final color? when tint) {
      body = ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: body,
      );
    }
    if (edit != null) {
      body = _Editable(
        key: edit.keys[part],
        anchor: anchor,
        selected: edit.selected == part,
        color: edit.outline,
        child: body,
      );
    }
    if (at.size != PartPlacement.initial.size) {
      body = Transform.scale(scale: at.scale, alignment: anchor, child: body);
    }
    if (at case PartPlacement(:final x?, :final y?)) {
      body = CompositedTransformFollower(
        link: scope.link,
        showWhenUnlinked: false,
        followerAnchor: anchor,
        offset: Offset(
          editFaceSize.width * x / 100,
          editFaceSize.height * y / 100,
        ),
        child: body,
      );
    }
    return body;
  }
}

/// Đường chạy chủ thẻ đã chỉnh, cho các tranh vẽ đường chạy trong [box] mặc
/// định của bộ. Chỗ lưu là tâm khung, theo phần trăm vùng tranh.
class RouteEdit {
  const RouteEdit._(this.placement, this.color);

  final PartPlacement placement;

  /// Màu nét đường chạy; null là màu gốc của bộ.
  final Color? color;

  static RouteEdit? of(BuildContext context) {
    final scope = CardPartsScope.maybeOf(context);
    if (scope == null) return null;
    final at = scope.layout.of(CardPart.route);
    return RouteEdit._(at, scope.colorOf(at.color));
  }

  bool get hidden => placement.hidden;

  /// Khung đường chạy trong vùng tranh [size], từ khung [box] gốc của bộ.
  Rect boxIn(Rect box, Size size) {
    final center = switch (placement) {
      PartPlacement(:final x?, :final y?) => Offset(
        size.width * x / 100,
        size.height * y / 100,
      ),
      _ => box.center,
    };
    return Rect.fromCenter(
      center: center,
      width: box.width * placement.scale,
      height: box.height * placement.scale,
    );
  }
}

/// Trong màn chỉnh, gắn khóa đo cho vùng tranh và khung đường chạy [box] lên
/// [art]; ngoài màn chỉnh trả nguyên [art].
Widget editableRouteArt(BuildContext context, Rect box, Widget art) {
  final edit = CardEditScope.maybeOf(context);
  if (edit == null) return art;
  return Stack(
    fit: StackFit.expand,
    children: [
      KeyedSubtree(key: edit.art, child: art),
      Positioned.fromRect(
        rect: box,
        child: _Editable(
          key: edit.keys[CardPart.route],
          anchor: Alignment.center,
          selected: edit.selected == CardPart.route,
          color: edit.outline,
          child: const SizedBox.expand(),
        ),
      ),
    ],
  );
}

/// Điểm neo của phần mà [key] (một khoá trong [CardEditScope.keys]) đang gắn;
/// null là phần đó chưa vẽ.
Alignment? editAnchorOf(GlobalKey key) => switch (key.currentWidget) {
  _Editable(:final anchor) => anchor,
  _ => null,
};

/// Trong màn chỉnh, phần đang chọn có khung. Không thêm đệm, vì đệm làm phần
/// lệch khỏi điểm neo so với lúc xem.
class _Editable extends StatelessWidget {
  const _Editable({
    super.key,
    required this.anchor,
    required this.selected,
    required this.color,
    required this.child,
  });

  final Alignment anchor;
  final bool selected;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: selected ? Border.all(color: color, width: 1.5) : null,
    ),
    child: child,
  );
}
