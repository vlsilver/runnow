import 'package:flutter/widgets.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowAchievementTokens;

/// Màu phần ruột của thẻ thành tích: nền, lớp phủ sau chữ, chữ, mặt sau dữ
/// liệu, tranh đường chạy và lá úp. Khung, holo và ánh vẫn thuộc bậc nên không
/// nằm ở đây; màu nhấn và chữ ánh của bậc nằm ở đây vì chúng in trên nền ruột,
/// nền sáng cần bản đậm thì mới đọc được.
@immutable
class RunCardSkin {
  const RunCardSkin({
    required this.field,
    required this.shade,
    required this.hero,
    required this.ink,
    required this.textShadow,
    required this.hairline,
    required this.backTop,
    required this.backBottom,
    required this.backRay,
    required this.emblemRing,
    required this.dataBack,
    required this.dataMapEdge,
    required this.dataGrid,
    required this.dataLabel,
    required this.dataCredit,
    required this.darkMap,
    required this.routeLine,
    required this.routeStart,
    required this.routeContour,
    required this.stamp,
    required this.failVeil,
    required this.failInk,
    required this.accents,
    required this.titles,
    required this.rainbow,
    required this.aurora,
    required this.routes,
  });

  /// Nền dưới tranh, lộ ra khi tranh chưa tải xong.
  final Color field;

  /// Lớp phủ sau khối chữ trên tranh.
  final Color shade;

  /// Số km, số liệu mặt sau, chữ lá úp.
  final Color hero;

  /// Chữ thường: tên thẻ bậc Thường, mô tả, chân thẻ.
  final Color ink;
  final Color textShadow;
  final Color hairline;

  /// Nền mặt sau huy hiệu và lá úp.
  final Color backTop;
  final Color backBottom;
  final Color backRay;
  final Color emblemRing;

  /// Mặt sau dữ liệu: nền, viền bản đồ, lưới biểu đồ, nhãn, ghi công bản đồ.
  final Color dataBack;
  final Color dataMapEdge;
  final Color dataGrid;
  final Color dataLabel;
  final Color dataCredit;

  /// Bản đồ mặt sau dùng nền tối hay sáng.
  final bool darkMap;

  /// Nét đường chạy và nét biểu đồ pace.
  final Color routeLine;
  final Color routeStart;
  final Color routeContour;

  /// Nền con dấu đường chạy trên tranh.
  final Color stamp;
  final Color failVeil;
  final Color failInk;

  /// Màu nhấn từng bậc: đá, nhãn bậc, tên chủ, chân thẻ.
  final Map<GameCardTier, Color> accents;

  /// Chữ ánh của tên thẻ bậc Hiếm và Siêu hiếm (trên xuống dưới).
  final Map<GameCardTier, List<Color>> titles;

  /// Dải màu chạy qua tên thẻ bậc Huyền thoại và Thần thoại.
  final List<Color> rainbow;
  final List<Color> aurora;

  /// Tranh đường chạy từng bậc: nền giữa, nền mép, màu phát sáng.
  final Map<GameCardTier, (Color, Color, Color)> routes;

  Color accent(GameCardTier tier) => accents[tier]!;
  Color glow(GameCardTier tier) => routes[tier]!.$3;

  /// Bộ màu thẻ có từ đầu: ruột tối trung tính.
  static const classic = RunCardSkin(
    field: _T.field,
    shade: _T.shade,
    hero: _T.hero,
    ink: RunNowGameTokens.nightInk,
    textShadow: _T.textShadow,
    hairline: _T.hairline,
    backTop: _T.backTop,
    backBottom: _T.backBottom,
    backRay: _T.backRay,
    emblemRing: _T.emblemRing,
    dataBack: _T.dataBack,
    dataMapEdge: _T.dataMapEdge,
    dataGrid: _T.dataGrid,
    dataLabel: _T.dataLabel,
    dataCredit: _T.dataCredit,
    darkMap: true,
    routeLine: _T.routeLine,
    routeStart: _T.routeStart,
    routeContour: _T.routeContour,
    stamp: _T.stamp,
    failVeil: _T.failVeil,
    failInk: _T.failInk,
    accents: {
      GameCardTier.common: _T.accentCommon,
      GameCardTier.rare: _T.accentRare,
      GameCardTier.superRare: _T.accentEpic,
      GameCardTier.legendary: _T.accentLegendary,
      GameCardTier.mythic: _T.accentMythic,
    },
    titles: {
      GameCardTier.rare: [_T.titleSilver1, _T.titleSilver2, _T.titleSilver3],
      GameCardTier.superRare: [_T.titleGold1, _T.titleGold2, _T.titleGold3],
    },
    rainbow: [
      _T.titlePink,
      _T.titleAmber,
      _T.titleMint,
      _T.titleSky,
      _T.titleViolet,
      _T.titlePink,
    ],
    aurora: [
      _T.titleIce,
      _T.titleTeal,
      _T.titleBlue,
      _T.titleLilac,
      _T.titleTeal,
      _T.titleIce,
    ],
    routes: {
      GameCardTier.common: (
        _T.routeFieldCommon,
        _T.routeFieldCommonEdge,
        _T.routeGlowCommon,
      ),
      GameCardTier.rare: (
        _T.routeFieldRare,
        _T.routeFieldRareEdge,
        _T.routeGlowRare,
      ),
      GameCardTier.superRare: (
        _T.routeFieldEpic,
        _T.routeFieldEpicEdge,
        _T.routeGlowEpic,
      ),
      GameCardTier.legendary: (
        _T.routeFieldLegendary,
        _T.routeFieldLegendaryEdge,
        _T.routeGlowLegendary,
      ),
      GameCardTier.mythic: (
        _T.routeFieldMythic,
        _T.routeFieldMythicEdge,
        _T.routeGlowMythic,
      ),
    },
  );

  /// Bộ màu thẻ đang dùng ở [context]; ngoài [RunCardSkinScope] thì là
  /// [classic].
  static RunCardSkin of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RunCardSkinScope>()?.skin ??
      classic;
}

/// Đặt bộ màu cho mọi thẻ thành tích bên dưới.
class RunCardSkinScope extends InheritedWidget {
  const RunCardSkinScope({super.key, required this.skin, required super.child});

  final RunCardSkin skin;

  @override
  bool updateShouldNotify(RunCardSkinScope old) => !identical(old.skin, skin);
}
