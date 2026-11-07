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
    required this.routes,
    this.onDarkArt,
    this.element,
  });

  /// Tên ổn định của bộ màu, vào khoá cache ảnh khoe.
  final String id;

  /// Hành của bộ màu; null là [classic], bộ màu gốc của từng tranh.
  final RunNowElement? element;

  /// Nền dưới tranh, lộ ra khi tranh chưa tải xong.
  final Color field;

  /// Quầng ôm nét chữ trên tranh.
  final Color shade;

  /// Số km, số liệu mặt sau, chữ lá úp.
  final Color hero;

  /// Chữ thường: tên thẻ bậc Thường, mô tả, chân thẻ.
  final Color ink;
  final Color textShadow;

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

  /// Chữ ánh của tên thẻ từ bậc Hiếm trở lên (trên xuống dưới): đồng, bạc,
  /// vàng, kim cương. Bậc không có ở đây thì tên in bằng [ink].
  final Map<GameCardTier, List<Color>> titles;

  /// Tranh đường chạy từng bậc: nền giữa, nền mép, màu phát sáng.
  final Map<GameCardTier, (Color, Color, Color)> routes;

  /// Bộ màu cho chữ mặt trước khi in trên tranh tối (tranh vẽ, poster);
  /// null là chính bộ này, vốn đã là chữ sáng.
  final RunCardSkin? onDarkArt;

  Color accent(GameCardTier tier) => accents[tier]!;
  Color glow(GameCardTier tier) => routes[tier]!.$3;

  /// Màu nền của tranh tự vẽ (trời, nền chặng, nền mặt sau) nhuốm về tông
  /// đậm của hành. Nét vẽ và màu nhận diện của thẻ (linh vật, huy chương,
  /// trăng phe) không đi qua đây, nên đổi bộ màu không đổi tranh. Tranh là
  /// cảnh đêm nên bộ sáng nhuốm như bộ tối cùng hành: kéo về màu giấy thì
  /// tranh xám đục. [classic] giữ nguyên màu gốc.
  Color tintArt(Color color) {
    final element = this.element;
    return element == null ? color : Color.lerp(color, element.ramp[4], 0.35)!;
  }

  /// Bộ màu thẻ có từ đầu: ruột tối trung tính.
  static const classic = RunCardSkin(
    id: 'classic',
    field: _T.field,
    shade: _T.shade,
    hero: _T.hero,
    ink: RunNowGameTokens.nightInk,
    textShadow: _T.textShadow,
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
      GameCardTier.rare: [_T.titleBronze1, _T.titleBronze2, _T.titleBronze3],
      GameCardTier.superRare: [
        _T.titleSilver1,
        _T.titleSilver2,
        _T.titleSilver3,
      ],
      GameCardTier.legendary: [_T.titleGold1, _T.titleGold2, _T.titleGold3],
      GameCardTier.mythic: [
        _T.titleDiamond1,
        _T.titleDiamond2,
        _T.titleDiamond3,
      ],
    },
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

  static final _secrets = <RunNowElement, RunCardSkin>{};

  /// Bộ màu của thẻ Ẩn: ruột tối nhuốm hành, mọi bậc nhấn và chữ ánh cùng
  /// màu hành. Thẻ Ẩn luôn mặc bộ này, không theo lựa chọn của người xem.
  static RunCardSkin secret(RunNowElement element) =>
      _secrets.putIfAbsent(element, () {
        final ramp = element.ramp;
        final night = _night(element);
        final accent = Color.lerp(ramp[0], _T.secretLift, 0.45)!;
        final route = (
          Color.lerp(ramp[4], _T.secretDeep, 0.6)!,
          Color.lerp(ramp[4], _T.secretDeep, 0.82)!,
          ramp[1],
        );
        return RunCardSkin(
          id: 'secret.${element.name}',
          element: element,
          field: night.field,
          shade: night.shade,
          hero: night.hero,
          ink: night.ink,
          textShadow: night.textShadow,
          backTop: night.backTop,
          backBottom: night.backBottom,
          backRay: night.backRay,
          emblemRing: night.emblemRing,
          dataBack: night.dataBack,
          dataMapEdge: night.dataMapEdge,
          dataGrid: night.dataGrid,
          dataLabel: night.dataLabel,
          dataCredit: night.dataCredit,
          darkMap: true,
          routeLine: night.routeLine,
          routeStart: night.routeStart,
          routeContour: night.routeContour,
          stamp: night.stamp,
          failVeil: night.failVeil,
          failInk: night.failInk,
          accents: {for (final tier in GameCardTier.values) tier: accent},
          titles: {
            for (final tier in GameCardTier.values)
              tier: [accent, ramp[1], ramp[3]],
          },
          routes: {for (final tier in GameCardTier.values) tier: route},
        );
      });

  /// Ruột tối như [classic], nền nhuốm hành và đường chạy màu hành.
  static RunCardSkin _night(RunNowElement element) {
    final ramp = element.ramp;
    Color tint(Color base, Color hue, double amount) =>
        Color.alphaBlend(hue.withValues(alpha: amount), base);
    return RunCardSkin(
      id: 'dark.${element.name}',
      element: element,
      field: tint(classic.field, ramp[4], 0.18),
      shade: tint(classic.shade, ramp[4], 0.22),
      hero: classic.hero,
      ink: classic.ink,
      textShadow: classic.textShadow,
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
      element: element,
      field: element.tint,
      shade: element.tint,
      hero: ink,
      ink: ink,
      textShadow: _T.paperShadow,
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
        GameCardTier.rare: [_T.paperBronze1, _T.paperBronze2, _T.paperBronze3],
        GameCardTier.superRare: [
          _T.paperSilver1,
          _T.paperSilver2,
          _T.paperSilver3,
        ],
        GameCardTier.legendary: [_T.paperGold1, _T.paperGold2, _T.paperGold3],
        GameCardTier.mythic: [
          _T.paperDiamond1,
          _T.paperDiamond2,
          _T.paperDiamond3,
        ],
      },
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
      onDarkArt: _night(element),
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
