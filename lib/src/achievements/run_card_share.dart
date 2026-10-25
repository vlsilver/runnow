import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:path_provider/path_provider.dart';

/// Khoe thẻ buổi chạy bằng ảnh mặt trước, ảnh mặt sau hoặc lá xoay 3D. Ba file
/// tạo một lần rồi giữ trong máy cho các lần khoe sau.
///
/// Lá xoay ghi thành video MP4 trên điện thoại: GIF chỉ có 256 màu mỗi khung
/// nên tranh nền và glow bị vằn, không bao giờ nét bằng ảnh. Web không có bộ
/// ghi video nên vẫn ghi GIF.

/// Đổi số này khi cách vẽ thẻ hay cách ghi đổi, để cache cũ không dùng nữa.
const _shareVersion = 4;

/// Một vòng lá xoay: đứng mặt trước, lật sang sau, đứng, lật về.
const _motionDuration = Duration(milliseconds: 3600);

const _videoFps = 30;
const _videoWidth = 1080;
const _videoBitRate = 5000000;

const _gifFrameCount = 36;

/// 360 px thì chữ và viền nhoè khi xem toàn màn; 540 px gần như không khác
/// ảnh gốc, file thẻ thật khoảng 2,5 MB.
const _gifWidth = 540;
const _stillPixelRatio = 3.0;

/// Chờ tranh nền và tile bản đồ mặt sau tải xong trước khi chụp. Mạng chậm
/// mà vẫn thiếu thì người dùng bấm Tạo lại.
const _warmUp = Duration(milliseconds: 1200);

/// Máy có bộ ghi video native (iOS, Android) thì lá xoay là MP4, còn lại GIF.
bool get _videoMotion =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Ba file khoe của một thẻ.
class RunCardShareFiles {
  const RunCardShareFiles({
    required this.front,
    required this.back,
    required this.motion,
    required this.motionType,
  });

  final Uint8List front;
  final Uint8List back;

  /// Lá xoay 3D, kiểu file là [motionType].
  final Uint8List motion;

  /// `video/mp4` hoặc `image/gif`.
  final String motionType;
}

/// Khoá cache: đổi khi những gì in trên thẻ đổi (bậc, tranh nền, tên chủ,
/// bộ màu thẻ).
String runCardShareKey(
  RunCard card,
  String owner, {
  required RunCardSkin skin,
}) {
  // FNV-1a 32 bit: ổn định giữa các lần mở app, khác String.hashCode.
  var hash = 0x811c9dc5;
  final printed =
      '${card.tier.name}|${card.artPath ?? ''}|$owner|${skin.id}|'
      '$_shareVersion';
  for (final unit in printed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}

/// Giữ ba file khoe của từng thẻ trong thư mục support của app; trên web chỉ
/// giữ trong bộ nhớ.
class RunCardShareStore {
  final _memory = <String, RunCardShareFiles>{};

  static String get _motionName => _videoMotion ? 'card.mp4' : 'card.gif';
  static List<String> get _names => ['front.png', 'back.png', _motionName];

  Future<Directory> _cardDir(String cardId) async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/run_card_share/$cardId');
  }

  Future<RunCardShareFiles?> load(String cardId, String key) async {
    if (_memory['$cardId/$key'] case final hit?) return hit;
    if (kIsWeb) return null;
    final dir = Directory('${(await _cardDir(cardId)).path}/$key');
    final files = [for (final n in _names) File('${dir.path}/$n')];
    for (final f in files) {
      if (!await f.exists()) return null;
    }
    final [front, back, motion] = await Future.wait([
      for (final f in files) f.readAsBytes(),
    ]);
    return _memory['$cardId/$key'] = RunCardShareFiles(
      front: front,
      back: back,
      motion: motion,
      motionType: _videoMotion ? 'video/mp4' : 'image/gif',
    );
  }

  /// Ghi ba file rồi xoá bản của khoá cũ. Mỗi file ghi ra tên tạm rồi đổi tên,
  /// nên app tắt giữa chừng không để lại file dở mà load tưởng là đủ.
  Future<void> save(String cardId, String key, RunCardShareFiles files) async {
    _memory['$cardId/$key'] = files;
    if (kIsWeb) return;
    final cardDir = await _cardDir(cardId);
    final dir = await Directory('${cardDir.path}/$key').create(recursive: true);
    final bytes = [files.front, files.back, files.motion];
    final names = _names;
    for (var i = 0; i < names.length; i++) {
      final tmp = File('${dir.path}/${names[i]}.tmp');
      await tmp.writeAsBytes(bytes[i], flush: true);
      await tmp.rename('${dir.path}/${names[i]}');
    }
    await for (final old in cardDir.list()) {
      if (old is Directory && old.path != dir.path) {
        await old.delete(recursive: true);
      }
    }
  }

  Future<void> clear(String cardId) async {
    _memory.removeWhere((k, _) => k.startsWith('$cardId/'));
    if (kIsWeb) return;
    final dir = await _cardDir(cardId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

final runCardShareStoreProvider = Provider((ref) => RunCardShareStore());

/// Khung ảnh RGBA cùng cỡ để ghép GIF; gửi sang isolate nên chỉ giữ dữ liệu.
class CardGifFrames {
  const CardGifFrames({
    required this.width,
    required this.height,
    required this.frameMs,
    required this.frames,
  });

  final int width;
  final int height;
  final int frameMs;
  final List<Uint8List> frames;
}

/// Ghép các khung thành GIF lặp mãi. Chạy lâu (lượng tử màu từng khung), nên
/// gọi qua compute.
Uint8List encodeCardGif(CardGifFrames f) {
  // Bỏ dither: với 36 khung thẻ thật ở 540 px, dither encode chậm gấp ba và
  // file nặng thêm khoảng 60% mà vẫn không hết vằn; neural giữ màu glow mượt
  // hơn octree.
  final encoder = img.GifEncoder(
    repeat: 0,
    quantizerType: img.QuantizerType.neural,
    dither: img.DitherKernel.none,
  );
  for (final frame in f.frames) {
    encoder.addFrame(
      img.Image.fromBytes(
        width: f.width,
        height: f.height,
        bytes: frame.buffer,
        bytesOffset: frame.offsetInBytes,
        numChannels: 4,
      ),
      duration: f.frameMs ~/ 10,
    );
  }
  return encoder.finish()!;
}

/// Bộ ghi MP4 H.264 bằng phần cứng của máy (AVAssetWriter trên iOS,
/// MediaCodec trên Android). Mỗi lần chỉ ghi một video.
class CardVideoWriter {
  static const _channel = MethodChannel('runnow/card_video');

  /// [width], [height] phải chia hết cho 16: một số bộ mã hoá Android từ
  /// chối cỡ khác.
  Future<void> start({
    required String path,
    required int width,
    required int height,
  }) => _channel.invokeMethod('start', {
    'path': path,
    'width': width,
    'height': height,
    'fps': _videoFps,
    'bitRate': _videoBitRate,
  });

  /// Một khung RGBA đúng cỡ đã start.
  Future<void> add(Uint8List rgba) => _channel.invokeMethod('frame', rgba);

  Future<void> finish() => _channel.invokeMethod('finish');

  Future<void> cancel() => _channel.invokeMethod('cancel');
}

/// Đặt khung RGBA [src] cỡ [sw]×[sh] vào giữa khung [w]×[h], phần thừa cắt,
/// phần thiếu tô [fill]. toImage làm tròn cỡ theo pixelRatio nên có thể lệch
/// một hai điểm so với cỡ video.
Uint8List fitRgbaFrame(
  Uint8List src,
  int sw,
  int sh,
  int w,
  int h,
  Color fill,
) {
  if (sw == w && sh == h) return src;
  final out = Uint8List(w * h * 4);
  final px = [
    (fill.r * 255).round(),
    (fill.g * 255).round(),
    (fill.b * 255).round(),
    255,
  ];
  for (var i = 0; i < out.length; i += 4) {
    out.setRange(i, i + 4, px);
  }
  final dx = (w - sw) ~/ 2;
  final dy = (h - sh) ~/ 2;
  final cols = math.min(sw, w);
  final sx = math.max(0, -dx);
  final ox = math.max(0, dx);
  for (var y = 0; y < h; y++) {
    final syRow = y - dy;
    if (syRow < 0 || syRow >= sh) continue;
    final from = (syRow * sw + sx) * 4;
    final to = (y * w + ox) * 4;
    out.setRange(to, to + cols * 4, src, from);
  }
  return out;
}

/// Góc lật và độ nghiêng của lá ở thời điểm [t] (0..1 trong một vòng): đứng
/// mặt trước, lật sang mặt sau, đứng, lật tiếp về mặt trước; lá đung đưa nhẹ
/// để ánh sáng chạy. t = 1 trùng t = 0 nên vòng lặp liền.
({double turn, Offset pose}) _motionPose(double t) {
  double flip(double from) =>
      Curves.easeInOutCubic.transform((t - from) * 3) * math.pi;
  final turn = switch (t) {
    < 1 / 6 => 0.0,
    < 1 / 2 => flip(1 / 6),
    < 2 / 3 => math.pi,
    _ => math.pi + flip(2 / 3),
  };
  final sway = t * 2 * math.pi;
  return (
    turn: turn,
    pose: Offset(math.sin(sway) * 0.35, math.cos(sway) * 0.15),
  );
}

enum _Choice { front, back, motion }

extension on _Choice {
  String get label => switch (this) {
    _Choice.front => 'Mặt trước',
    _Choice.back => 'Mặt sau',
    _Choice.motion => _videoMotion ? 'Video 3D' : 'GIF 3D',
  };
}

/// Màn khoe mở với bộ màu thẻ đang xem rồi tự giữ bộ màu riêng: đổi bộ màu
/// chung giữa chừng thì ba file vẫn khớp nhau và khớp khoá cache.
Future<void> showRunCardShare(
  BuildContext context, {
  required RunCard card,
  required AchievementCardData data,
}) {
  final skin = RunCardSkin.of(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: gameNightTheme(),
        child: RunCardShareScreen(card: card, data: data, skin: skin),
      ),
    ),
  );
}

class RunCardShareScreen extends ConsumerStatefulWidget {
  const RunCardShareScreen({
    super.key,
    required this.card,
    required this.data,
    required this.skin,
  });

  final RunCard card;
  final AchievementCardData data;

  /// Bộ màu lúc mở. Chọn màu khác trên màn khoe chỉ đổi file khoe lần này,
  /// không đổi bộ màu chung của máy.
  final RunCardSkin skin;

  @override
  ConsumerState<RunCardShareScreen> createState() => _RunCardShareScreenState();
}

class _RunCardShareScreenState extends ConsumerState<RunCardShareScreen> {
  final _stageKey = GlobalKey();
  RunCardShareFiles? _files;
  Object? _error;
  bool _recording = false;
  bool _sharing = false;
  int _step = 0;
  int _steps = 0;
  ({double turn, Offset pose}) _at = _motionPose(0);
  _Choice _choice = _Choice.motion;
  late RunCardSkin _skin = widget.skin;

  String get _key =>
      runCardShareKey(widget.card, widget.data.owner, skin: _skin);

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Bộ màu nào đã khoe với thẻ này trong phiên thì store còn giữ trong bộ
  /// nhớ, chọn lại là có ngay; bộ mới thì ghi lại ba file.
  void _pickSkin(RunCardSkinChoice pick) {
    final skin = RunCardSkin.forTheme(pick.$1, pick.$2);
    if (identical(skin, _skin)) return;
    setState(() => _skin = skin);
    _start();
  }

  Future<void> _start({bool fresh = false}) async {
    final store = ref.read(runCardShareStoreProvider);
    setState(() {
      _files = null;
      _error = null;
      _step = 0;
    });
    try {
      if (fresh) {
        await store.clear(widget.card.id);
      } else if (await store.load(widget.card.id, _key) case final hit?) {
        if (mounted) setState(() => _files = hit);
        return;
      }
      if (!mounted) return;
      setState(() => _recording = true);
      final files = await _record();
      await store.save(widget.card.id, _key, files);
      if (mounted) setState(() => _files = files);
    } catch (error, stack) {
      debugPrint('Tạo ảnh khoe thẻ lỗi: $error\n$stack');
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// Đặt lá ở [at] rồi chụp sân khấu ở khung kế tiếp.
  Future<ui.Image> _shot(
    ({double turn, Offset pose}) at,
    double pixelRatio,
  ) async {
    if (!mounted) throw StateError('Màn khoe đã đóng.');
    setState(() => _at = at);
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _stageKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  /// Chụp lá ở [t] thành khung RGBA rộng [width].
  Future<({Uint8List rgba, int width, int height})> _frame(
    double t,
    int width,
  ) async {
    final stageWidth = _stageKey.currentContext!.size!.width;
    final image = await _shot(_motionPose(t), width / stageWidth);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (
        rgba: data!.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  void _progress(int step, int steps) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _steps = steps;
    });
  }

  Future<RunCardShareFiles> _record() async {
    await Future<void>.delayed(_warmUp);
    Future<Uint8List> png(double turn) async {
      final image = await _shot((
        turn: turn,
        pose: Offset.zero,
      ), _stillPixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    final front = await png(0);
    final back = await png(math.pi);
    if (_videoMotion) {
      return RunCardShareFiles(
        front: front,
        back: back,
        motion: await _recordVideo(),
        motionType: 'video/mp4',
      );
    }
    return RunCardShareFiles(
      front: front,
      back: back,
      motion: await _recordGif(),
      motionType: 'image/gif',
    );
  }

  /// Ghi từng khung sang bộ mã hoá ngay khi chụp, không giữ cả video trong
  /// bộ nhớ: 108 khung 1080 px thô là khoảng 680 MB.
  Future<Uint8List> _recordVideo() async {
    final size = _stageKey.currentContext!.size!;
    final height = (_videoWidth * size.height / size.width / 16).round() * 16;
    final frames = _motionDuration.inMilliseconds * _videoFps ~/ 1000;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/run-card-${widget.card.id}.mp4';
    final writer = CardVideoWriter();
    await writer.start(path: path, width: _videoWidth, height: height);
    try {
      for (var i = 0; i < frames; i++) {
        _progress(i + 1, frames);
        final f = await _frame(i / frames, _videoWidth);
        await writer.add(
          fitRgbaFrame(
            f.rgba,
            f.width,
            f.height,
            _videoWidth,
            height,
            RunNowGameTokens.nightBackground,
          ),
        );
      }
      if (mounted) setState(() => _step = frames + 1);
      await writer.finish();
    } catch (_) {
      await writer.cancel().catchError(
        (Object e) => debugPrint('Huỷ ghi video lỗi: $e'),
      );
      rethrow;
    }
    final file = File(path);
    try {
      return await file.readAsBytes();
    } finally {
      await file.delete();
    }
  }

  Future<Uint8List> _recordGif() async {
    final frames = <Uint8List>[];
    var width = 0;
    var height = 0;
    for (var i = 0; i < _gifFrameCount; i++) {
      _progress(i + 1, _gifFrameCount);
      final f = await _frame(i / _gifFrameCount, _gifWidth);
      (width, height) = (f.width, f.height);
      frames.add(f.rgba);
    }
    if (mounted) setState(() => _step = _gifFrameCount + 1);
    return compute(
      encodeCardGif,
      CardGifFrames(
        width: width,
        height: height,
        frameMs: _motionDuration.inMilliseconds ~/ _gifFrameCount,
        frames: frames,
      ),
    );
  }

  Future<void> _share(BuildContext origin) async {
    final files = _files!;
    setState(() => _sharing = true);
    try {
      final (bytes, type) = switch (_choice) {
        _Choice.front => (files.front, 'image/png'),
        _Choice.back => (files.back, 'image/png'),
        _Choice.motion => (files.motion, files.motionType),
      };
      final ext = switch (type) {
        'video/mp4' => 'mp4',
        'image/gif' => 'gif',
        _ => 'png',
      };
      await shareRunCardFile(
        bytes: bytes,
        mimeType: type,
        fileName: '3i-${widget.card.id}-${_choice.name}.$ext',
        shareOriginContext: origin,
        card: widget.card,
      );
    } catch (error) {
      debugPrint('Khoe thẻ lỗi: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa khoe được thẻ, thử lại sau.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return RunCardSkinScope(skin: _skin, child: _screen(files));
  }

  Widget _screen(RunCardShareFiles? files) {
    return Scaffold(
      backgroundColor: RunNowGameTokens.nightBackground,
      appBar: AppBar(
        title: const Text('Khoe thẻ'),
        actions: [
          if (files != null)
            IconButton(
              tooltip: 'Tạo lại',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _start(fresh: true),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: files != null
                      ? _preview(files)
                      : _error != null
                      ? _failed()
                      : _recordingStage(),
                ),
              ),
              if (files != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final choice in _Choice.values) ...[
                      if (choice != _Choice.front) const SizedBox(width: 10),
                      Expanded(
                        child: _ChoiceTile(
                          label: choice.label,
                          // Tile lá xoay dùng ảnh mặt trước kèm dấu phát.
                          bytes: choice == _Choice.back
                              ? files.back
                              : files.front,
                          motion: choice == _Choice.motion,
                          selected: choice == _choice,
                          onTap: () => setState(() => _choice = choice),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Đang ghi thì ẩn: hai lượt ghi cùng chụp một sân khấu.
                _SkinPicker(skin: _skin, onPick: _pickSkin),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Builder(
                  builder: (origin) => FilledButton.icon(
                    onPressed: files == null || _sharing
                        ? null
                        : () => _share(origin),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(
                      files == null
                          ? 'Đang tạo...'
                          : _sharing
                          ? 'Đang mở chia sẻ...'
                          : 'Khoe ${_choice.label.toLowerCase()}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ảnh tĩnh thì hiện đúng file sẽ gửi. Lá xoay thì cho lá xoay ngay trên
  /// màn theo đúng nhịp đã ghi, khỏi cần trình phát video.
  Widget _preview(RunCardShareFiles files) => switch (_choice) {
    _Choice.front => Image.memory(files.front, gaplessPlayback: true),
    _Choice.back => Image.memory(files.back, gaplessPlayback: true),
    _Choice.motion => _SpinningCard(data: widget.data),
  };

  Widget _failed() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Chưa tạo được ảnh khoe: $_error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: gameNightMuted),
      ),
      TextButton(onPressed: _start, child: const Text('Thử lại')),
    ],
  );

  Widget _recordingStage() {
    final done = _steps > 0 && _step > _steps;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _CardStage(boundaryKey: _stageKey, data: widget.data, at: _at),
        ),
        const SizedBox(height: 16),
        Text(
          !_recording
              ? 'Đang mở...'
              : _step == 0
              ? 'Đang chuẩn bị thẻ...'
              : done
              ? (_videoMotion ? 'Đang lưu video...' : 'Đang ghép GIF...')
              : 'Đang ghi khung $_step/$_steps',
          style: const TextStyle(color: gameNightMuted),
        ),
      ],
    );
  }
}

/// Lá đặt ở [at] trên nền tối, cỡ theo chỗ trống. Mặt sau là một element duy
/// nhất: lá quay mặt trước thì nó nằm ngoài màn, lá lật thì nó chuyển lên lá
/// mà giữ nguyên state. Dựng mới lúc lật thì bản đồ phải tải tile và mờ dần
/// từ đầu, khung chụp ngay sau đó mất bản đồ.
class _CardStage extends StatefulWidget {
  const _CardStage({this.boundaryKey, required this.data, required this.at});

  final GlobalKey? boundaryKey;
  final AchievementCardData data;
  final ({double turn, Offset pose}) at;

  @override
  State<_CardStage> createState() => _CardStageState();
}

class _CardStageState extends State<_CardStage> {
  final _backKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = achievementCardSize;
        // Lá cộng viền 8% mỗi bên.
        final width = math.min(
          constraints.maxWidth / 1.16,
          constraints.maxHeight / (base.height / base.width + 0.16),
        );
        Widget back(Offset pose) => KeyedSubtree(
          key: _backKey,
          child: AchievementCard(data: widget.data, pose: pose, back: true),
        );
        final at = widget.at;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tiltFlipShowsBack(pose: at.pose, turn: at.turn))
              Offstage(
                child: GameCardScaled(
                  width: width,
                  size: base,
                  child: back(Offset.zero),
                ),
              ),
            RepaintBoundary(
              key: widget.boundaryKey,
              child: ColoredBox(
                color: RunNowGameTokens.nightBackground,
                child: Padding(
                  padding: EdgeInsets.all(width * 0.08),
                  child: tiltFlipFace(
                    front: (pose) =>
                        AchievementCard(data: widget.data, pose: pose),
                    back: back,
                    width: width,
                    cardSize: base,
                    pose: at.pose,
                    turn: at.turn,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lá xoay lặp mãi theo đúng nhịp của video hay GIF đã ghi.
class _SpinningCard extends StatefulWidget {
  const _SpinningCard({required this.data});

  final AchievementCardData data;

  @override
  State<_SpinningCard> createState() => _SpinningCardState();
}

class _SpinningCardState extends State<_SpinningCard>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: _motionDuration,
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, _) =>
        _CardStage(data: widget.data, at: _motionPose(_clock.value)),
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.bytes,
    required this.motion,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Uint8List bytes;
  final bool motion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(bytes, gaplessPlayback: true),
                    if (motion)
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 32,
                        color: gameNightInk,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? gameNightInk : gameNightMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nền sáng/tối và năm hành, chọn ngay trên màn khoe.
class _SkinPicker extends StatelessWidget {
  const _SkinPicker({required this.skin, required this.onPick});

  final RunCardSkin skin;
  final ValueChanged<RunCardSkinChoice> onPick;

  @override
  Widget build(BuildContext context) {
    // Bộ màu cũ (không theo theme nào) thì chưa ô nào được chọn.
    final RunCardSkinChoice? pick =
        [
              for (final a in RunNowAppearance.values)
                for (final e in RunNowElement.values) (a, e),
            ]
            .where((c) => identical(RunCardSkin.forTheme(c.$1, c.$2), skin))
            .firstOrNull;
    final appearance = pick?.$1 ?? RunNowAppearance.dark;
    final element = pick?.$2 ?? RunNowElement.metal;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 6,
      children: [
        for (final a in RunNowAppearance.values)
          _SkinDot(
            tooltip: 'Nền ${a.label.toLowerCase()}',
            icon: a == RunNowAppearance.light
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            color: gameNightInk,
            selected: pick?.$1 == a,
            onTap: () => onPick((a, element)),
          ),
        const SizedBox(width: 8),
        for (final e in RunNowElement.values)
          _SkinDot(
            tooltip: e.label,
            icon: e.icon,
            color: e.ramp[2],
            selected: pick?.$2 == e,
            onTap: () => onPick((appearance, e)),
          ),
      ],
    );
  }
}

class _SkinDot extends StatelessWidget {
  const _SkinDot({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        side: BorderSide(
          color: selected ? accent : Colors.white.withValues(alpha: 0.12),
          width: selected ? 2 : 1,
        ),
      ),
      icon: Icon(icon, color: color, size: 20),
    );
  }
}
