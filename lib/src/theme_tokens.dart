import 'package:flutter/material.dart';

/// Single source of truth for elemental palettes — follows "Quy tắc màu · Runow"
/// (60/30/10 + semantic tokens).
///
/// Mỗi hành chỉ cung cấp brand 30%, biến đậm và tint.
/// Nền/surface là neutral cố định để giao diện sạch và không bị nhuộm màu.
abstract final class RunNowThemeTokens {
  static const waterMain = Color(0xff0e96a8);

  // ── Sắc hành (ramp): index 2 = brand (30%), index 3 = brand-strong ────────
  static const woodRamp = <Color>[
    Color(0xffc9f06a),
    Color(0xffa8e22e),
    Color(0xff8fd400), // brand
    Color(0xff4c9a00), // brand-strong
    Color(0xff2f6300),
  ];
  static const fireRamp = <Color>[
    Color(0xffffb3a3),
    Color(0xffff7a5e),
    Color(0xffff5230), // brand
    Color(0xffe23b27), // brand-strong
    Color(0xff9c2418),
  ];
  static const earthRamp = <Color>[
    Color(0xffe8b884),
    Color(0xffda9a52),
    Color(0xffce7b2c), // brand
    Color(0xffb5681f), // brand-strong
    Color(0xff7e470f),
  ];
  static const metalRamp = <Color>[
    Color(0xffe6d08a),
    Color(0xffd8bc5c),
    Color(0xffc9a53a), // brand
    Color(0xff9a7a1e), // brand-strong
    Color(0xff6b5413),
  ];
  static const waterRamp = <Color>[
    Color(0xff7fc9d4),
    Color(0xff36aebe),
    waterMain, // brand
    Color(0xff0e7c8c), // brand-strong
    Color(0xff0a5663),
  ];

  // ── Tint nhạt theo hành (chip / nút phụ trên nền sáng) ────────────────────
  static const woodTint = Color(0xffeef2e6);
  static const fireTint = Color(0xfffbeee8);
  static const earthTint = Color(0xfff4ecdb);
  static const metalTint = Color(0xfff4f1e6);
  static const waterTint = Color(0xffe9f0f2);

  // Material neutral theo design: [background 60, surface, border, text].
  static const lightNeutral = <Color>[
    Color(0xfff4f2ec),
    Color(0xffffffff),
    Color(0xffe6e1d6),
    Color(0xff1f1d1a),
  ];
  static const darkNeutral = <Color>[
    Color(0xff121116), // bg
    Color(0xff1c1b22), // surface
    Color(0xff2c2b33), // border
    Color(0xffeceae3), // text
  ];

  static const lightInk = Color(0xff16160f); // mực (10) — nút chính/tiêu đề
  static const darkInk = Color(0xfff4f2ec);
  static const lightMuted = Color(0xff6f6a61);
  static const darkMuted = Color(0xff9a958b);

  // Các tông nền tối có thể chọn riêng: [bg, surface, border, text].
  static const darkSlate = <Color>[
    Color(0xff15161b),
    Color(0xff20222a),
    Color(0xff32343d),
    Color(0xfff1f2f5),
  ];
  static const darkDim = <Color>[
    Color(0xff17181d),
    Color(0xff23252d),
    Color(0xff363842),
    Color(0xfff4f5f7),
  ];
  static const darkCloud = <Color>[
    Color(0xff1b1c22),
    Color(0xff282a32),
    Color(0xff3c3e48),
    Color(0xfff7f7f9),
  ];
  static const darkWarm = <Color>[
    Color(0xff19160f),
    Color(0xff241f17),
    Color(0xff39322a),
    Color(0xfff4f0ea),
  ];
  static const darkCool = <Color>[
    Color(0xff10141a),
    Color(0xff1a1f27),
    Color(0xff2c333d),
    Color(0xffeff3f7),
  ];

  // Bộ vật liệu sáng/tối theo hành đều trỏ về trung tính chung (xem doc).
  static const woodLight = lightNeutral;
  static const fireLight = lightNeutral;
  static const earthLight = lightNeutral;
  static const metalLight = lightNeutral;
  static const waterLight = lightNeutral;

  // Dark mode theo tài liệu cũng dùng bộ trung tính chung.
  static const woodDark = darkNeutral;
  static const fireDark = darkNeutral;
  static const earthDark = darkNeutral;
  static const metalDark = darkNeutral;
  static const waterDark = darkNeutral;
}

/// Colors whose meaning must not change when the elemental palette changes.
/// Khoá theo ngũ hành: thành công=Mộc, cảnh báo=Kim, lỗi=Hỏa, thông tin=Thủy.
abstract final class RunNowSemanticColors {
  static const danger = Color(0xffe23b27); // Hỏa
  static const success = Color(0xff3e8e00); // Mộc
  static const warning = Color(0xffc9a53a); // Kim
  static const info = Color(0xff0e96a8); // Thủy
  static const inactive = Color(0xff667085);
  static const gpsGood = success;
  static const gpsFair = warning;
  static const gpsWeak = danger;
  static const gpsLocking = info;
}

/// Stable series colors used to distinguish physiological/training datasets.
abstract final class RunNowDataColors {
  static const heart = Color(0xffff4d5f);
  static const pace = Color(0xff5bc8ff);
  static const elevation = Color(0xff38a3ff);
  static const cadence = Color(0xffa78bfa);
  static const energy = Color(0xff34d399);
  static const violet = Color(0xffa78bfa);
  static const zone1 = Color(0xff00d9ff);
  static const zone2 = Color(0xff19d27f);
  static const zone3 = Color(0xffffd166);
  static const zone4 = Color(0xffff8f00);
  static const zone5 = heart;

  // AI Coach — màu LOẠI BÀI (ngũ hành theo cường độ; cố định light/dark, không
  // đổi theo accent người dùng vì nó mã hoá cường độ tập).
  static const coachEasyLight = Color(0xff34965e);
  static const coachEasyDark = Color(0xff58c888);
  static const coachLongLight = Color(0xff2a73c9);
  static const coachLongDark = Color(0xff5fa0ee);
  static const coachTempoLight = Color(0xffb87a22);
  static const coachTempoDark = Color(0xffe2a94f);
  static const coachIntervalLight = Color(0xffd9502f);
  static const coachIntervalDark = Color(0xfff4785c);
  static const coachRestLight = Color(0xff7e8d97);
  static const coachRestDark = Color(0xff93a4ad);
  static const coachRaceLight = Color(0xffb92a57);
  static const coachRaceDark = Color(0xffef5b87);
  // Chữ trên nền accent (dark) + nền sheet Coach (dark).
  static const coachOnAccentDark = Color(0xff04201d);
  static const coachSheetDark = Color(0xff0e1a18);
}

/// Third-party brand colors are fixed by the provider, not by 3i themes.
abstract final class RunNowBrandColors {
  static const strava = Color(0xfffc5200);
}

// Màn "Hành Trình" dùng thẳng theme sáng/tối + 5 hành chung của app
// (`context.runNowPalette`, xem `journey_hub_screen.dart`) nên không còn
// bảng màu riêng ở đây nữa.

/// Bàn chơi Ma Sói: tông đêm của màn ván và chất liệu lá bài khoe. Không
/// theo hành hay sáng/tối của app, vì màn ván là một bàn chơi riêng.
class RunNowGameTokens {
  const RunNowGameTokens._();

  static const nightBackground = Color(0xFF0B0B10);
  static const nightSurface = Color(0xFF15151C);
  static const nightGlow = Color(0xFF2A1A3E);
  static const wolfGlow = Color(0xFF2E1416);
  static const nightInk = Color(0xFFF4F2EC);
  static const nightInkSoft = Color(0xFFE6E3DC);
  static const nightMuted = Color(0xFFB9B5AD);
  static const nightDanger = Color(0xFFFFB3A3);
  static const gold = Color(0xFFF5D77A);
  static const goldDeep = Color(0xFFE9C45A);
  static const goldPale = Color(0xFFFFF1B8);
  static const goldShade = Color(0xFFD8AE3C);
  static const onGold = Color(0xFF1F1606);
  static const heroTop = Color(0xFF1C1B3A);
  static const heroMid = Color(0xFF120F1C);
  static const heroBottom = Color(0xFF0D0C12);
  static const heroBorder = Color(0x4DC7B8FF);
  static const heroSub = Color(0xFFD9D2C0);
  static const dayTop = Color(0xFF3B2A14);
  static const dayMid = Color(0xFF1A1420);
  static const dayBottom = Color(0xFF120F18);
  static const dayBorder = Color(0x59E9C45A);
  static const sunLight = Color(0xFFFFF7D6);
  static const sunMid = Color(0xFFF0C75E);
  static const sunShade = Color(0xFFB98A24);
  static const kmOk = Color(0xFFB9D77A);
  static const kmShort = Color(0x669C2418);
  static const cardFieldTop = Color(0xFF26272F);
  static const cardFieldBottom = Color(0xFF121318);
  static const cardArt = Color(0xFF0D0E14);
  static const cardHills = Color(0xA605050A);
  static const cardShadow = Color(0x80000000);
  static const cardTextShadow = Color(0x73000000);
  static const gemOutline = Color(0x59000000);
  static const roleWolf = Color(0xFFE07A68);
  static const roleVillager = Color(0xFFC4C9A4);
  static const roleSeer = Color(0xFFB9ADDB);
  static const roleGuard = Color(0xFFA3B9D4);
  static const roleWitch = Color(0xFF9CC7C2);
  static const roleHunter = Color(0xFFD6AE80);
  static const roleCupid = Color(0xFFDBA3B6);
  // Khung theo bậc: sắt, đồng, bạc, vàng, kim cương.
  static const graphiteEdge = Color(0xFF3A3C44);
  static const graphiteCore = Color(0xFF1E2027);
  static const gemGraphite = Color(0xFF8D8980);
  static const bronzeEdge = Color(0xFF5A3519);
  static const bronzeLight = Color(0xFFE2A86A);
  static const bronzeDeep = Color(0xFF7A4A22);
  static const bronzeBright = Color(0xFFC98A4B);
  static const gemBronze = Color(0xFFD99A5E);
  static const silverEdge = Color(0xFF7D828B);
  static const silverLight = Color(0xFFDCDFE4);
  static const silverDeep = Color(0xFF6F747D);
  static const silverBright = Color(0xFFE4E7EC);
  static const gemSilver = Color(0xFFD4D8DE);
  static const goldEdge = Color(0xFF9C7C30);
  static const foilDark = Color(0xFF7E5A12);
  static const foilMid = Color(0xFFA8801E);
  static const foilDeep = Color(0xFF8A6416);
  // Kim cương chỉ trắng và xanh băng, sáng tối theo mặt cắt; không tán sắc.
  static const diamondWhite = Color(0xFFFFFFFF);
  static const diamondBright = Color(0xFFF4FAFF);
  static const diamondIce = Color(0xFFDDEBF7);
  static const diamondMist = Color(0xFFB9CCDB);
  static const diamondShade = Color(0xFF8FA7BA);
  static const diamondDeep = Color(0xFF5E7487);
  static const gemDiamond = Color(0xFFE6F3FF);
  static const backEdge = Color(0xFF3A3D48);
  static const backLight = Color(0xFFA9ADB6);
  static const backDeep = Color(0xFF2C2E36);
  static const backBright = Color(0xFFC7CAD1);
  static const backFieldTop = Color(0xFF1E2A4A);
  static const backFieldBottom = Color(0xFF0C0F1C);
  static const backRing = Color(0xFF8CC0FF);
  static const backLineStrong = Color(0xCCE9C45A);
  static const backLine = Color(0x80E9C45A);
  static const backLineSoft = Color(0x40E9C45A);
  static const moonLight = Color(0xFFFFFBE8);
  static const moonMid = Color(0xFFE8DFC0);
  static const moonShade = Color(0xFFB9AE8A);
  static const moonGlow = Color(0xFFFFF8D6);
  static const holoClear = Color(0x00FFF0DC);
  static const holoCream = Color(0xFFFFE2C4);
  static const holoIce = Color(0xFFD6ECF0);
  static const holoPearl = Color(0xFFF2F0EA);
  static const sparkleWarm = Color(0xFFFFF6C8);
}

/// Robot trên thẻ MyBot. Thân và kính giữ một màu ở mọi hành để nhìn ra cùng
/// một con robot; mắt, ăng-ten và ngực lấy màu của hành.
class RunNowBotTokens {
  const RunNowBotTokens._();

  static const shell = Color(0xFFE9EEF0);
  static const shellShade = Color(0xFFC3CCD3);
  static const visor = Color(0xFF10252B);
  static const shadow = Color(0x73000000);
  static const leg = Color(0xFF5A616B);

  /// Robot của thẻ chưa có tên: một bóng tối có dấu hỏi.
  static const ghost = Color(0xFF2A2F37);
  static const ghostVisor = Color(0xFF1A1E24);
  static const ghostInk = Color(0xFF4A515C);

  /// Đồ theo kiểu bot: nón tiệc, tai nghe, mũ và còi, khăn quàng.
  static const partyHat = Color(0xFFF06292);
  static const partyGold = Color(0xFFFFD166);
  static const headband = Color(0xFF2B2F36);
  static const cap = Color(0xFFE8553D);
  static const capBrim = Color(0xFFB8402C);
  static const lanyard = Color(0xFFCFD5DB);
  static const whistle = Color(0xFFF0C75E);
  static const scarf = Color(0xFFFF8A5B);
}

/// Thẻ MyBot ngoài con robot. Trời từ bậc Bạc trở lên là phần thưởng của
/// bậc nên giữ một màu ở mọi hành; nền màn lên bậc cũng vậy.
class RunNowBotCardTokens {
  const RunNowBotCardTokens._();

  /// Trời theo bậc: Bạc bình minh, Vàng hoàng hôn, Foil cực quang. Bậc
  /// Thường là đêm theo màu hành.
  static const dawnTop = Color(0xFF1D2F4D);
  static const dawnMid = Color(0xFF3F6690);
  static const dawnBottom = Color(0xFFA9C0D6);
  static const duskTop = Color(0xFF2B1D3A);
  static const duskMid = Color(0xFF9C3F52);
  static const duskBottom = Color(0xFFF0A35A);
  static const auroraTop = Color(0xFF0B0A24);
  static const auroraMid = Color(0xFF24145A);
  static const auroraBottom = Color(0xFF0E3A4E);
  static const auroraGreen = Color(0xFF50FFBE);
  static const auroraPink = Color(0xFFFF78DC);
  static const auroraViolet = Color(0xFFA078FF);
  static const auroraBlue = Color(0xFF50E6FF);

  /// Nền dưới tranh và biển tên.
  static const plaque = Color(0xFF151820);

  /// Nền câu đầu của tính cách ở màn sửa bot: câu thẻ lấy làm lời thoại.
  static const quoteHighlight = Color(0x40F0C75E);
  static const sunCore = Color(0xFFFFF3C4);
  static const sunHalo = Color(0xFFFFC36B);

  /// Ánh cầu vồng của bậc Foil, cùng vàng của lá bài.
  static const foilSky = Color(0xFF8FE3F0);
  static const foilPink = Color(0xFFE9A2FF);

  /// Chữ tên bậc Foil trên nền sáng, nơi hồng nhạt không đọc được.
  static const foilInk = Color(0xFF9B4FC4);
  static const revealGlow = Color(0xFF2A2416);
  static const revealEdge = Color(0xFF121116);
}

/// Thẻ thành tích: tranh phủ cả thẻ, kim loại của bậc (sắt, đồng, bạc, vàng,
/// kim cương) chỉ còn ở ô đá và viền trong. Tông đêm như lá Ma
/// Sói, nhưng nền là ảnh thật nên chữ cần lớp tối phía dưới để đọc được.
class RunNowAchievementTokens {
  const RunNowAchievementTokens._();

  static const accentCommon = Color(0xFFC3C8CF);
  static const accentRare = Color(0xFFE2A86A);
  static const accentEpic = Color(0xFFE3E8EE);
  static const accentLegendary = Color(0xFFF3D27A);
  static const accentMythic = Color(0xFFDDEFFF);

  // Kim loại của bậc, mỗi thứ sáng, giữa, tối: ô đá, viền trong.
  static const ironLight = Color(0xFF9AA1AA);
  static const ironMid = Color(0xFF6B727C);
  static const ironDark = Color(0xFF3A3F46);
  static const bronzeLight = Color(0xFFF0C08A);
  static const bronzeMid = Color(0xFFC98A4B);
  static const bronzeDark = Color(0xFF7A4A22);
  static const silverLight = Color(0xFFFFFFFF);
  static const silverMid = Color(0xFFC9D0D8);
  static const silverDark = Color(0xFF7E8690);
  static const goldLight = Color(0xFFFFF1BD);
  static const goldMid = Color(0xFFE2B85A);
  static const goldDark = Color(0xFF8A6218);
  static const diamondLight = Color(0xFFFFFFFF);
  static const diamondMid = Color(0xFFDDEBF7);
  static const diamondDark = Color(0xFF8FA7BA);
  static const cartouche = Color(0x9E0A0A0E);
  static const gemEdge = Color(0x59000000);
  static const gemGlint = Color(0xCCFFFFFF);
  static const sweep = Color(0xFFFFFFFF);
  static const rim = Color(0xB3000000);

  // Thẻ Ẩn pha ramp của hành về hai đầu này để ra tông sáng nhất, tối nhất.
  static const secretLift = Color(0xFFFFFFFF);
  static const secretDeep = Color(0xFF000000);

  static const graphite1 = Color(0xFF50545D);
  static const graphite2 = Color(0xFF2B2D33);
  static const graphite3 = Color(0xFF454850);
  static const graphite4 = Color(0xFF26282D);
  static const starDiamond = Color(0xFFF2F9FF);

  static const drop = Color(0x99000000);

  static const sheen = Color(0x57FFFFFF);
  static const sheenBronze = Color(0x57FFD6AA);
  static const sheenGold = Color(0x5CFFF0CD);
  static const sheenDiamond = Color(0x66EBF7FF);
  static const sheenTail = Color(0x0FFFFFFF);

  static const field = Color(0xFF0D0E14);
  static const shade = Color(0xFF08090E);
  static const hero = Color(0xFFF7F5EF);
  static const textShadow = Color(0x99000000);

  static const titleSilver1 = Color(0xFFFFFFFF);
  static const titleSilver2 = Color(0xFFE6EBF0);
  static const titleSilver3 = Color(0xFFA2ABB6);
  static const titleGold1 = Color(0xFFFFF6D2);
  static const titleGold2 = Color(0xFFF6D77F);
  static const titleGold3 = Color(0xFFC08D2E);
  static const titleBronze1 = Color(0xFFFBE2C6);
  static const titleBronze2 = Color(0xFFD9A06A);
  static const titleBronze3 = Color(0xFF8C5628);
  static const titleDiamond1 = Color(0xFFFFFFFF);
  static const titleDiamond2 = Color(0xFFDDEBF7);
  static const titleDiamond3 = Color(0xFF9AB0C2);

  static const backTop = Color(0xFF20244A);
  static const backBottom = Color(0xFF0B0C14);
  static const backRay = Color(0x09FFFFFF);
  static const emblemRing = Color(0x0AFFFFFF);

  // Nền "đường chạy" của thẻ buổi chạy: nền tối theo bậc, đường sáng màu bậc.
  static const routeFieldCommon = Color(0xFF2A2F38);
  static const routeFieldCommonEdge = Color(0xFF101217);
  static const routeFieldRare = Color(0xFF3A2616);
  static const routeFieldRareEdge = Color(0xFF120B06);
  static const routeFieldEpic = Color(0xFF2B3038);
  static const routeFieldEpicEdge = Color(0xFF0E1014);
  static const routeFieldLegendary = Color(0xFF3D2C10);
  static const routeFieldLegendaryEdge = Color(0xFF120D06);
  static const routeGlowCommon = Color(0xFF9FB3C8);
  static const routeGlowRare = Color(0xFFE2A86A);
  static const routeGlowEpic = Color(0xFFE3E8EE);
  static const routeGlowLegendary = Color(0xFFFFC65C);
  static const routeFieldMythic = Color(0xFF1C2A38);
  static const routeFieldMythicEdge = Color(0xFF06090E);
  static const routeGlowMythic = Color(0xFFDDF0FF);
  static const routeContour = Color(0x0FFFFFFF);
  static const routeLine = Color(0xFFFFFFFF);
  static const routeStart = Color(0xFF0B0B10);

  // Con dấu đường chạy trên ảnh và mặt sau dữ liệu của thẻ buổi chạy.
  static const stamp = Color(0xB808090E);
  static const stampDrop = Color(0x73000000);
  static const dataBack = Color(0xFF0D0F15);
  static const dataMapEdge = Color(0x24FFFFFF);
  static const dataGrid = Color(0x14FFFFFF);
  static const dataLabel = Color(0xB8F4F2EC);

  // Lá úp lật trượt: màn tối phủ cả mặt, chữ và icon đỏ nhạt.
  static const failVeil = Color(0xB8070910);
  static const failInk = Color(0xFFFF8A80);
  static const dataCredit = Color(0x8CF4F2EC);

  // Bộ màu thẻ sáng: ruột giấy, chữ mực. Màu bậc và chữ ánh lấy tông đậm để
  // đọc được trên nền sáng; khung và holo của bậc dùng chung với bản tối.
  static const paperShadow = Color(0x66FFFFFF);
  static const paperRay = Color(0x0A000000);
  static const paperRing = Color(0x0F000000);
  static const paperMapEdge = Color(0x24000000);
  static const paperGrid = Color(0x14000000);
  static const paperLabel = Color(0xB816160F);
  static const paperCredit = Color(0x8C16160F);
  static const paperContour = Color(0x0F000000);
  static const paperStamp = Color(0xB8F4F2EC);
  static const paperVeil = Color(0xC7F4F2EC);
  static const paperFailInk = Color(0xFFD9452F);
  static const paperAccentCommon = Color(0xFF59606B);
  static const paperAccentRare = Color(0xFF8A4E1C);
  static const paperAccentEpic = Color(0xFF4A5462);
  static const paperAccentLegendary = Color(0xFF9A6A10);
  static const paperAccentMythic = Color(0xFF3C6A8E);
  static const paperBronze1 = Color(0xFF6E3A12);
  static const paperBronze2 = Color(0xFFA8682E);
  static const paperBronze3 = Color(0xFF5A2E0C);
  static const paperSilver1 = Color(0xFF3A434F);
  static const paperSilver2 = Color(0xFF6B7684);
  static const paperSilver3 = Color(0xFF2E3540);
  static const paperGold1 = Color(0xFF6F4A0C);
  static const paperGold2 = Color(0xFFA9781E);
  static const paperGold3 = Color(0xFF5E400C);
  static const paperDiamond1 = Color(0xFF2E4A63);
  static const paperDiamond2 = Color(0xFF5F86A6);
  static const paperDiamond3 = Color(0xFF23384C);
  static const paperRouteCommon = Color(0xFFECEAE4);
  static const paperRouteCommonEdge = Color(0xFFD6D2C8);
  static const paperGlowCommon = Color(0xFF7C8896);
  static const paperRouteRare = Color(0xFFF4E6D8);
  static const paperRouteRareEdge = Color(0xFFE2CBB2);
  static const paperGlowRare = Color(0xFFB06A2C);
  static const paperRouteEpic = Color(0xFFECEEF1);
  static const paperRouteEpicEdge = Color(0xFFD3D8DE);
  static const paperGlowEpic = Color(0xFF6B7684);
  static const paperRouteLegendary = Color(0xFFF6EBD2);
  static const paperRouteLegendaryEdge = Color(0xFFE3CFA2);
  static const paperGlowLegendary = Color(0xFFC98A12);
  static const paperRouteMythic = Color(0xFFE6F0F8);
  static const paperRouteMythicEdge = Color(0xFFCBDCEA);
  static const paperGlowMythic = Color(0xFF4F86B5);
}

/// Tranh vẽ bằng code trên thẻ Ma Sói: mỗi phe một bầu trời. Phe Sói trăng
/// máu, phe Dân trăng bạc trên làng thắp đèn, Cặp đôi trăng hồng. Màu giữ
/// nguyên ở mọi bộ màu thẻ vì tranh là dấu hiệu của phe.
class RunNowCardSceneTokens {
  const RunNowCardSceneTokens._();

  static const crater = Color(0x17000000);
  static const grainLight = Color(0xFFFFFFFF);
  static const grainDark = Color(0xFF000000);
  static const posterFloorShade = Color(0xFF000000);
  static const starWhite = Color(0xFFFFFFFF);

  static const wolvesSky1 = Color(0xFF12030A);
  static const wolvesSky2 = Color(0xFF3A0B16);
  static const wolvesSky3 = Color(0xFF1A0710);
  static const wolvesSky4 = Color(0xFF07020A);
  static const wolvesStar = Color(0xFFFFDCDC);
  static const wolvesMoonCore = Color(0xFFFFB38A);
  static const wolvesMoonRim = Color(0xFFB3241F);
  static const wolvesMoonGlow = Color(0x80DC2828);
  static const wolvesFog = Color(0x2EB42832);
  static const wolvesPines = Color(0xFF230610);
  static const wolvesRock = Color(0xFF0B0206);
  static const wolvesClaw = Color(0xBFFF5A50);

  static const villageSky1 = Color(0xFF060C1C);
  static const villageSky2 = Color(0xFF14254A);
  static const villageSky3 = Color(0xFF1D2F4F);
  static const villageSky4 = Color(0xFF0A1020);
  static const villageStar = Color(0xFFE6ECFF);
  static const villageMoonCore = Color(0xFFF6F3E4);
  static const villageMoonRim = Color(0xFFC9CDD9);
  static const villageMoonGlow = Color(0x59C8D7FF);
  static const villageEye = Color(0xFF1B2A4A);
  static const villageFog = Color(0x29A0B4E6);
  static const villagePines = Color(0xFF0D1730);
  static const villageHouse = Color(0xFF070C18);
  static const villageWindow = Color(0xFFFFC56B);
  static const villageWolfEye = Color(0xFFFF5A4A);

  static const loversSky1 = Color(0xFF14061A);
  static const loversSky2 = Color(0xFF4A1640);
  static const loversSky3 = Color(0xFF24102E);
  static const loversSky4 = Color(0xFF0B0410);
  static const loversStar = Color(0xFFFFE1F0);
  static const loversMoonCore = Color(0xFFFFE0EC);
  static const loversMoonRim = Color(0xFFE7779E);
  static const loversMoonGlow = Color(0x66FF78AA);
  static const loversArrow = Color(0xFF3A0F2C);
  static const loversPines = Color(0xFF1E0A22);
  static const loversHill = Color(0xFF0C0410);

  // Mặt sau: sói hú trong vầng trăng của phe.
  static const wolvesEmblemTop = Color(0xFF2B0711);
  static const wolvesEmblemBottom = Color(0xFF0B0206);
  static const wolvesEmblemGlow = Color(0x73DC2828);
  static const wolvesEmblemDark = Color(0xFF14030A);
  static const villageEmblemTop = Color(0xFF16264A);
  static const villageEmblemBottom = Color(0xFF050A16);
  static const villageEmblemRim = Color(0xFFC3C8D6);
  static const villageEmblemDark = Color(0xFF0B1428);
  static const loversEmblemTop = Color(0xFF3D1238);
  static const loversEmblemBottom = Color(0xFF0D0412);
  static const loversEmblemDark = Color(0xFF1C0818);

  // Thẻ Hành trình: poster từng chặng.
  static const marathonSky1 = Color(0xFFF2A65A);
  static const marathonSky2 = Color(0xFFF7D29A);
  static const marathonSky3 = Color(0xFFE58C4F);
  static const marathonSun = Color(0xFFFFF1D0);
  static const marathonSunGlow = Color(0xB3FFE6AA);
  static const marathonHill = Color(0xFFC96A3A);
  static const marathonTemple = Color(0xFF7A3A22);
  static const marathonHillFront = Color(0xFF8F4426);
  static const marathonPath = Color(0xFFFBE3B8);
  static const marathonBranch = Color(0xFF4F5A2A);
  static const marathonLeaf = Color(0xFF5F6B30);

  static const montBlancSky1 = Color(0xFF9FD0EA);
  static const montBlancSky2 = Color(0xFFE5F2F7);
  static const montBlancSky3 = Color(0xFFBFE0EE);
  static const montBlancSun = Color(0xFFFFFBE6);
  static const montBlancSunGlow = Color(0x99FFFFE6);
  static const montBlancPeakFar = Color(0xFF5D7F9C);
  static const montBlancSnow = Color(0xFFFFFFFF);
  static const montBlancPeakMid = Color(0xFF36597A);
  static const montBlancPeakNear = Color(0xFF1F3D57);
  static const montBlancPines = Color(0xFF15293B);
  static const montBlancPath = Color(0xFFFFD36B);

  static const xuyenVietSky1 = Color(0xFF0F4C5C);
  static const xuyenVietSky2 = Color(0xFF1B6F7C);
  static const xuyenVietSky3 = Color(0xFF0A3440);
  static const xuyenVietSun = Color(0xFFFFD36B);
  static const xuyenVietSunGlow = Color(0x73FFC85A);
  static const xuyenVietLand = Color(0xFFE9C46A);
  static const xuyenVietRoute = Color(0xFFC0392B);
  static const xuyenVietStop = Color(0xFFFFFFFF);
  static const xuyenVietWave = Color(0x59FFFFFF);

  static const dongNamASky1 = Color(0xFF2A1B4A);
  static const dongNamASky2 = Color(0xFFC4506A);
  static const dongNamASky3 = Color(0xFFF2A65A);
  static const dongNamASky4 = Color(0xFF6B2F4A);
  static const dongNamASun = Color(0xFFFFD98A);
  static const dongNamASunGlow = Color(0x80FFC878);
  static const dongNamAInk = Color(0xFF2A0F26);
  static const dongNamARoute = Color(0x99FFF0D2);
  static const dongNamACapital = Color(0xFFFFF3D6);

  // Mặt sau Hành trình: nguyệt quế nhũ quanh biểu tượng chặng.
  static const marathonEmblemTop = Color(0xFF5A2C18);
  static const marathonEmblemBottom = Color(0xFF2A120A);
  static const montBlancEmblemTop = Color(0xFF2C4560);
  static const montBlancEmblemBottom = Color(0xFF101D2C);
  static const xuyenVietEmblemTop = Color(0xFF145057);
  static const xuyenVietEmblemBottom = Color(0xFF06222A);
  static const dongNamAEmblemTop = Color(0xFF3E2268);
  static const dongNamAEmblemBottom = Color(0xFF160C2A);
}
