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
}

/// Third-party brand colors are fixed by the provider, not by RunNow themes.
abstract final class RunNowBrandColors {
  static const strava = Color(0xfffc5200);
}
