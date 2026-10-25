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
    required this.id,
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
    this.scrimTop = (0.66, 0.34),
    this.scrimBottom = (0.96, 0.62),
  });

  /// Tên ổn định của bộ màu, vào khoá cache ảnh khoe.
  final String id;

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

  /// Độ đậm lớp phủ sau khối chữ trên và dưới: ở mép thẻ, ở mép trong khối
  /// chữ. Chữ mực trên lớp phủ sáng cần phủ dày hơn chữ trắng trên lớp tối.
  final (double, double) scrimTop;
  final (double, double) scrimBottom;

  Color accent(GameCardTier tier) => accents[tier]!;
  Color glow(GameCardTier tier) => routes[tier]!.$3;

  /// Bộ màu thẻ có từ đầu: ruột tối trung tính.
  static const classic = RunCardSkin(
    id: 'classic',
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

  static final _themed = <(RunNowAppearance, RunNowElement), RunCardSkin>{};

  /// Bộ màu thẻ theo một theme app: nền sáng hay tối, sắc nhấn theo hành.
  /// Cùng lựa chọn thì trả cùng một object để thẻ không vẽ lại thừa.
  static RunCardSkin forTheme(
    RunNowAppearance appearance,
    RunNowElement element,
  ) => _themed.putIfAbsent(
    (appearance, element),
    () => appearance == RunNowAppearance.light
        ? _paper(element)
        : _night(element),
  );

  /// Ruột tối như [classic], nền nhuốm hành và đường chạy màu hành.
  static RunCardSkin _night(RunNowElement element) {
    final ramp = element.ramp;
    Color tint(Color base, Color hue, double amount) =>
        Color.alphaBlend(hue.withValues(alpha: amount), base);
    return RunCardSkin(
      id: 'dark.${element.name}',
      field: tint(classic.field, ramp[4], 0.18),
      shade: tint(classic.shade, ramp[4], 0.22),
      hero: classic.hero,
      ink: classic.ink,
      textShadow: classic.textShadow,
      hairline: classic.hairline,
      backTop: tint(classic.backBottom, ramp[3], 0.32),
      backBottom: classic.backBottom,
      backRay: classic.backRay,
      emblemRing: classic.emblemRing,
      dataBack: tint(classic.dataBack, ramp[4], 0.14),
      dataMapEdge: classic.dataMapEdge,
      dataGrid: classic.dataGrid,
      dataLabel: classic.dataLabel,
      dataCredit: classic.dataCredit,
      darkMap: true,
      routeLine: ramp[0],
      routeStart: classic.routeStart,
      routeContour: classic.routeContour,
      stamp: tint(classic.shade, ramp[4], 0.22).withValues(alpha: 0.72),
      failVeil: classic.failVeil,
      failInk: classic.failInk,
      accents: classic.accents,
      titles: classic.titles,
      rainbow: classic.rainbow,
      aurora: classic.aurora,
      routes: classic.routes,
    );
  }

  /// Ruột giấy, chữ mực; màu bậc tông đậm, đường chạy màu hành.
  static RunCardSkin _paper(RunNowElement element) {
    final ramp = element.ramp;
    final paper = RunNowThemeTokens.lightNeutral[0];
    const ink = RunNowThemeTokens.lightInk;
    return RunCardSkin(
      id: 'light.${element.name}',
      field: element.tint,
      shade: element.tint,
      hero: ink,
      ink: ink,
      textShadow: _T.paperShadow,
      hairline: _T.paperHairline,
      backTop: Color.alphaBlend(ramp[1].withValues(alpha: 0.3), paper),
      backBottom: paper,
      backRay: _T.paperRay,
      emblemRing: _T.paperRing,
      dataBack: Color.lerp(element.tint, paper, 0.5)!,
      dataMapEdge: _T.paperMapEdge,
      dataGrid: _T.paperGrid,
      dataLabel: _T.paperLabel,
      dataCredit: _T.paperCredit,
      darkMap: false,
      routeLine: ramp[3],
      routeStart: paper,
      routeContour: _T.paperContour,
      stamp: _T.paperStamp,
      failVeil: _T.paperVeil,
      failInk: _T.paperFailInk,
      accents: const {
        GameCardTier.common: _T.paperAccentCommon,
        GameCardTier.rare: _T.paperAccentRare,
        GameCardTier.superRare: _T.paperAccentEpic,
        GameCardTier.legendary: _T.paperAccentLegendary,
        GameCardTier.mythic: _T.paperAccentMythic,
      },
      titles: const {
        GameCardTier.rare: [_T.paperSilver1, _T.paperSilver2, _T.paperSilver3],
        GameCardTier.superRare: [_T.paperGold1, _T.paperGold2, _T.paperGold3],
      },
      rainbow: const [
        _T.paperPink,
        _T.paperAmber,
        _T.paperMint,
        _T.paperSky,
        _T.paperViolet,
        _T.paperPink,
      ],
      aurora: const [
        _T.paperTeal,
        _T.paperCyan,
        _T.paperBlue,
        _T.paperLilac,
        _T.paperCyan,
        _T.paperTeal,
      ],
      routes: const {
        GameCardTier.common: (
          _T.paperRouteCommon,
          _T.paperRouteCommonEdge,
          _T.paperGlowCommon,
        ),
        GameCardTier.rare: (
          _T.paperRouteRare,
          _T.paperRouteRareEdge,
          _T.paperGlowRare,
        ),
        GameCardTier.superRare: (
          _T.paperRouteEpic,
          _T.paperRouteEpicEdge,
          _T.paperGlowEpic,
        ),
        GameCardTier.legendary: (
          _T.paperRouteLegendary,
          _T.paperRouteLegendaryEdge,
          _T.paperGlowLegendary,
        ),
        GameCardTier.mythic: (
          _T.paperRouteMythic,
          _T.paperRouteMythicEdge,
          _T.paperGlowMythic,
        ),
      },
      scrimTop: (0.86, 0.6),
      scrimBottom: (0.96, 0.8),
    );
  }

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
