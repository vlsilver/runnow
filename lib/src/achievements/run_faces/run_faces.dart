import 'package:flutter/widgets.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/basic_faces.dart';
import 'package:myrun/src/achievements/run_faces/bib_faces.dart';
import 'package:myrun/src/achievements/run_faces/blocks_faces.dart';
import 'package:myrun/src/achievements/run_faces/blueprint_faces.dart';
import 'package:myrun/src/achievements/run_faces/cassette_faces.dart';
import 'package:myrun/src/achievements/run_faces/city_faces.dart';
import 'package:myrun/src/achievements/run_faces/constellation_faces.dart';
import 'package:myrun/src/achievements/run_faces/finish_faces.dart';
import 'package:myrun/src/achievements/run_faces/flipboard_faces.dart';
import 'package:myrun/src/achievements/run_faces/iron_faces.dart';
import 'package:myrun/src/achievements/run_faces/medal_faces.dart';
import 'package:myrun/src/achievements/run_faces/paper_map_faces.dart';
import 'package:myrun/src/achievements/run_faces/receipt_faces.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/achievements/run_faces/splits_faces.dart';
import 'package:myrun/src/achievements/run_faces/stopwatch_faces.dart';

export 'package:myrun/src/achievements/run_faces/default_art.dart'
    show paintRunBrand, runSetArt;
export 'package:myrun/src/achievements/run_faces/run_face_kit.dart'
    show RunFace;

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
  };
}
