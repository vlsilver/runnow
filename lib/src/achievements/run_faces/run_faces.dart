import 'package:flutter/widgets.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/basic_faces.dart';
import 'package:myrun/src/achievements/run_faces/bib_faces.dart';
import 'package:myrun/src/achievements/run_faces/blocks_faces.dart';
import 'package:myrun/src/achievements/run_faces/blueprint_faces.dart';
import 'package:myrun/src/achievements/run_faces/cassette_faces.dart';
import 'package:myrun/src/achievements/run_faces/city_faces.dart';
import 'package:myrun/src/achievements/run_faces/face_edit.dart';
import 'package:myrun/src/achievements/run_faces/constellation_faces.dart';
import 'package:myrun/src/achievements/run_faces/finish_faces.dart';
import 'package:myrun/src/achievements/run_faces/flipboard_faces.dart';
import 'package:myrun/src/achievements/run_faces/iron_faces.dart';
import 'package:myrun/src/achievements/run_faces/medal_faces.dart';
import 'package:myrun/src/achievements/run_faces/paper_map_faces.dart';
import 'package:myrun/src/achievements/run_faces/pixel_faces.dart';
import 'package:myrun/src/achievements/run_faces/receipt_faces.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/achievements/run_faces/splits_faces.dart';
import 'package:myrun/src/achievements/run_faces/stopwatch_faces.dart';
import 'package:myrun/src/theme_tokens.dart';

export 'package:myrun/src/achievements/run_faces/default_art.dart'
    show paintRunBrand, runSetArt;
export 'package:myrun/src/achievements/run_faces/run_face_kit.dart'
    show RunFace;

typedef _T = RunFaceTokens;

/// Bộ có màu riêng thì tranh và con dấu cũng không theo bộ màu thẻ, để bộ nào
/// cũng ra đúng một vẻ.
Widget _ownColors(Widget face) =>
    RunCardSkinScope(skin: RunCardSkin.classic, child: face);

/// Mặt trước của [style]; null là giữ bố cục mặc định của thẻ.
Widget? runFrontFace(RunCardStyle style, RunFace f) {
  final t = style.text;
  return switch (style.set) {
    RunCardSet.current || RunCardSet.splits => null,
    RunCardSet.basic => BasicFront(f),
    RunCardSet.blueprint => _ownColors(blueprintFront(f, t)),
    RunCardSet.city => _ownColors(cityFront(f, t)),
    RunCardSet.cassette => _ownColors(cassetteFront(f, t)),
    RunCardSet.constellation => _ownColors(constellationFront(f, t)),
    RunCardSet.blocks => _ownColors(blocksFront(f, t)),
    RunCardSet.stopwatch => _ownColors(stopwatchFront(f, t)),
    RunCardSet.flipBoard => _ownColors(flipBoardFront(f, t)),
    RunCardSet.bib => _ownColors(bibFront(f, t)),
    RunCardSet.finish => _ownColors(finishFront(f, t)),
    RunCardSet.paperMap => _ownColors(paperMapFront(f, t)),
    RunCardSet.receipt => _ownColors(receiptFront(f, t)),
    RunCardSet.medal => _ownColors(medalFront(f, t)),
    RunCardSet.iron => _ownColors(ironFront(f, t)),
    RunCardSet.pixel => PixelFront(f),
  };
}

/// Mặt sau của [style]; null là mặt sau mặc định. Thẻ không có GPS thì bỏ qua
/// cờ bản đồ, vì mặc định đã chọn ở thẻ khác vẫn áp cho thẻ này.
Widget? runBackFace(RunCardStyle style, RunFace f) {
  final map = style.map && f.hasRoute;
  return switch (style.set) {
    RunCardSet.current => null,
    RunCardSet.basic => BasicBack(f, map: map),
    RunCardSet.splits => SplitsBack(f, map: map),
    RunCardSet.blueprint => _ownColors(blueprintBack(f, map: map)),
    RunCardSet.city => _ownColors(cityBack(f, map: map)),
    RunCardSet.cassette => _ownColors(cassetteBack(f, map: map)),
    RunCardSet.constellation => _ownColors(constellationBack(f, map: map)),
    RunCardSet.blocks => _ownColors(map ? blocksMapBack(f) : blocksBack(f)),
    RunCardSet.stopwatch => _ownColors(stopwatchBack(f, map: map)),
    RunCardSet.flipBoard => _ownColors(flipBoardBack(f, map: map)),
    RunCardSet.bib => _ownColors(bibBack(f, map: map)),
    RunCardSet.finish => _ownColors(finishBack(f, map: map)),
    RunCardSet.paperMap => _ownColors(paperMapBack(f, map: map)),
    RunCardSet.receipt => _ownColors(receiptBack(f, map: map)),
    RunCardSet.medal => _ownColors(medalBack(f, map: map)),
    RunCardSet.iron => _ownColors(ironBack(f, map: map)),
    RunCardSet.pixel => PixelBack(f, map: map),
  };
}

/// Màu đặc trưng của [set] cho màn chỉnh, theo thứ tự [PartTone.index] trỏ
/// tới; đổi thứ tự là đổi màu của thẻ đã lưu.
List<FaceTone> faceTones(RunCardSet set) => switch (set) {
  RunCardSet.current || RunCardSet.basic || RunCardSet.splits => const [
    (label: 'Trắng', color: _T.white),
    (label: 'Đen', color: _T.night),
    (label: 'Đồng', color: _T.bronze),
  ],
  RunCardSet.blueprint => const [
    (label: 'Trắng', color: _T.blueprintWhite),
    (label: 'Xanh nhạt', color: _T.blueprintInk),
    (label: 'Xanh đậm', color: _T.blueprintBlue),
  ],
  RunCardSet.city => const [
    (label: 'Vàng', color: _T.cityGold),
    (label: 'Kem', color: _T.cityInk),
    (label: 'Đen', color: _T.cityStreet),
  ],
  RunCardSet.cassette => const [
    (label: 'Kem', color: _T.cassettePaper),
    (label: 'Đỏ', color: _T.cassetteRed),
    (label: 'Vàng', color: _T.cassetteAmber),
  ],
  RunCardSet.constellation => const [
    (label: 'Vàng', color: _T.constellationGold),
    (label: 'Kem', color: _T.constellationBright),
    (label: 'Đen', color: _T.constellationNight),
  ],
  RunCardSet.blocks => const [
    (label: 'Kem', color: _T.blocksCream),
    (label: 'Đen', color: _T.blocksCoal),
    (label: 'Xanh', color: _T.blocksBlue),
  ],
  RunCardSet.stopwatch => const [
    (label: 'Trắng', color: _T.stopwatchWhite),
    (label: 'Bạc', color: _T.stopwatchSteel),
    (label: 'Cam', color: _T.stopwatchAlert),
  ],
  RunCardSet.flipBoard => const [
    (label: 'Kem', color: _T.flipboardInk),
    (label: 'Vàng', color: _T.flipboardAmber),
    (label: 'Đen', color: _T.flipboardHinge),
  ],
  RunCardSet.bib => const [
    (label: 'Kem', color: _T.bibPaper),
    (label: 'Đen', color: _T.bibCoal),
  ],
  RunCardSet.finish => const [
    (label: 'Trắng', color: _T.finishWhite),
    (label: 'Đen', color: _T.finishCoal),
    (label: 'Gạch', color: _T.brick),
  ],
  RunCardSet.paperMap => const [
    (label: 'Nâu', color: _T.paperInk),
    (label: 'Đỏ', color: _T.paperRed),
    (label: 'Kem', color: _T.paperSheet),
  ],
  RunCardSet.receipt => const [
    (label: 'Đen', color: _T.receiptCoal),
    (label: 'Kem', color: _T.receiptPaper),
    (label: 'Xám', color: _T.receiptGrey),
  ],
  RunCardSet.medal => const [
    (label: 'Trắng', color: _T.medalWhite),
    (label: 'Bạc', color: _T.medalLight),
    (label: 'Đen', color: _T.medalCoal),
  ],
  RunCardSet.iron => const [
    (label: 'Trắng', color: _T.ironPaper),
    (label: 'Đen', color: _T.ironCoal),
    (label: 'Đỏ', color: _T.ironRed),
  ],
  RunCardSet.pixel => const [
    (label: 'Trắng', color: _T.white),
    (label: 'Đen', color: _T.night),
  ],
};
