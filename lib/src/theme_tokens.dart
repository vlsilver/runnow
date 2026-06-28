import 'package:flutter/material.dart';

/// Single source of truth for elemental palettes.
///
/// Keep values grouped by role so a palette can be reviewed as a complete
/// system instead of tuning isolated colors inside widgets.
abstract final class RunNowThemeTokens {
  static const waterMain = Color(0xff2c7c95);

  // Element ramps from Ngu Hanh Palette.html: light -> dark, main at index 2.
  static const woodRamp = <Color>[
    Color(0xff9fc59c),
    Color(0xff5fa068),
    Color(0xff2e8c45),
    Color(0xff1e6b32),
    Color(0xff114a21),
  ];
  static const fireRamp = <Color>[
    Color(0xffe8a18c),
    Color(0xffd26a4f),
    Color(0xffb83a24),
    Color(0xff902914),
    Color(0xff621809),
  ];
  static const earthRamp = <Color>[
    Color(0xffe4c57e),
    Color(0xffcfa13e),
    Color(0xffb5811f),
    Color(0xff8c6014),
    Color(0xff5c3d0b),
  ];
  static const metalRamp = <Color>[
    Color(0xffddcda6),
    Color(0xffc3a96f),
    Color(0xffa6883f),
    Color(0xff7e662a),
    Color(0xff54421a),
  ];
  static const waterRamp = <Color>[
    Color(0xff94becc),
    Color(0xff549bb0),
    waterMain,
    Color(0xff1c586c),
    Color(0xff0e3543),
  ];

  // Light materials belong to the selected element.
  static const woodLight = <Color>[
    Color(0xffe7f0e6),
    Color(0xfff6fbf5),
    Color(0xffcfe2cc),
    Color(0xff163a22),
  ];
  static const fireLight = <Color>[
    Color(0xfff7e9e4),
    Color(0xfffdf6f3),
    Color(0xffebd0c6),
    Color(0xff3e2018),
  ];
  static const earthLight = <Color>[
    Color(0xfff6eedb),
    Color(0xfffdf9ef),
    Color(0xffe8d7b5),
    Color(0xff3a2c12),
  ];
  static const metalLight = <Color>[
    Color(0xfff3eedf),
    Color(0xfffcf9f0),
    Color(0xffe2d6bb),
    Color(0xff332916),
  ];
  static const waterLight = <Color>[
    Color(0xffe2eef1),
    Color(0xfff2f9fb),
    Color(0xffc9e0e6),
    Color(0xff13313c),
  ];

  // Elemental dark materials from the same design source.
  static const woodDark = <Color>[
    Color(0xff0e2e18),
    Color(0xff143a20),
    Color(0xff26543a),
    Color(0xffcfe7d6),
  ];
  static const fireDark = <Color>[
    Color(0xff2c0f08),
    Color(0xff3c160d),
    Color(0xff5a2618),
    Color(0xfff4d9ce),
  ];
  static const earthDark = <Color>[
    Color(0xff281c07),
    Color(0xff37280b),
    Color(0xff503a1a),
    Color(0xfff0e3c7),
  ];
  static const metalDark = <Color>[
    Color(0xff201c0e),
    Color(0xff2e2914),
    Color(0xff473f26),
    Color(0xffece3c9),
  ];
  static const waterDark = <Color>[
    Color(0xff0c1418),
    Color(0xff121e23),
    Color(0xff233239),
    Color(0xffd6e6ec),
  ];

  // Selectable neutral dark materials: background, surface, border, text.
  static const darkSlate = <Color>[
    Color(0xff383a44),
    Color(0xff44464f),
    Color(0xff585b66),
    Color(0xfff1f2f5),
  ];
  static const darkDim = <Color>[
    Color(0xff474a54),
    Color(0xff52555f),
    Color(0xff666975),
    Color(0xfff4f5f7),
  ];
  static const darkCloud = <Color>[
    Color(0xff565963),
    Color(0xff62656f),
    Color(0xff777a85),
    Color(0xfff7f7f9),
  ];
  static const darkWarm = <Color>[
    Color(0xff454039),
    Color(0xff514b43),
    Color(0xff666057),
    Color(0xfff4f0ea),
  ];
  static const darkCool = <Color>[
    Color(0xff3a4450),
    Color(0xff45505d),
    Color(0xff5a6675),
    Color(0xffeff3f7),
  ];
}

/// Colors whose meaning must not change when the elemental palette changes.
abstract final class RunNowSemanticColors {
  static const danger = Color(0xffff5a6a);
  static const success = Color(0xff34d399);
  static const warning = Color(0xffffd166);
  static const inactive = Color(0xff667085);
  static const gpsGood = success;
  static const gpsFair = warning;
  static const gpsWeak = danger;
  static const gpsLocking = Color(0xff38a3ff);
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
