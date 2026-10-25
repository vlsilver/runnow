import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:path_provider/path_provider.dart';

/// Khoe thẻ buổi chạy bằng ảnh mặt trước, ảnh mặt sau hoặc GIF lá xoay 3D.
/// Ba file tạo một lần rồi giữ trong máy cho các lần khoe sau.

/// Đổi số này khi cách vẽ thẻ hay cách ghi GIF đổi, để cache cũ không dùng nữa.
const _shareVersion = 2;

const _gifFrameCount = 36;
const _gifFrameMs = 80;
const _gifWidthPx = 360.0;
const _stillPixelRatio = 3.0;

/// Chờ tranh nền và tile bản đồ mặt sau tải xong trước khi chụp. Mạng chậm
/// mà vẫn thiếu thì người dùng bấm Tạo lại.
const _warmUp = Duration(milliseconds: 1200);

/// Ba file khoe của một thẻ.
class RunCardShareFiles {
  const RunCardShareFiles({
    required this.front,
    required this.back,
    required this.gif,
  });

  final Uint8List front;
  final Uint8List back;
  final Uint8List gif;
}

/// Khoá cache: đổi khi những gì in trên thẻ đổi (bậc, tranh nền, tên chủ).
String runCardShareKey(RunCard card, String owner) {
  // FNV-1a 32 bit: ổn định giữa các lần mở app, khác String.hashCode.
  var hash = 0x811c9dc5;
  for (final unit
      in '${card.tier.name}|${card.artPath ?? ''}|$owner|$_shareVersion'
          .codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}

/// Giữ ba file khoe của từng thẻ trong thư mục support của app; trên web chỉ
/// giữ trong bộ nhớ.
class RunCardShareStore {
  final _memory = <String, RunCardShareFiles>{};

  static const _names = ['front.png', 'back.png', 'card.gif'];

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
    final [front, back, gif] = await Future.wait([
      for (final f in files) f.readAsBytes(),
    ]);
    return _memory['$cardId/$key'] = RunCardShareFiles(
      front: front,
      back: back,
      gif: gif,
    );
  }

  /// Ghi ba file rồi xoá bản của khoá cũ. Mỗi file ghi ra tên tạm rồi đổi tên,
  /// nên app tắt giữa chừng không để lại file dở mà load tưởng là đủ.
  Future<void> save(String cardId, String key, RunCardShareFiles files) async {
    _memory['$cardId/$key'] = files;
    if (kIsWeb) return;
    final cardDir = await _cardDir(cardId);
    final dir = await Directory('${cardDir.path}/$key').create(recursive: true);
    final bytes = [files.front, files.back, files.gif];
    for (var i = 0; i < _names.length; i++) {
      final tmp = File('${dir.path}/${_names[i]}.tmp');
      await tmp.writeAsBytes(bytes[i], flush: true);
      await tmp.rename('${dir.path}/${_names[i]}');
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
  // Bỏ dither: 36 khung cỡ thật encode nhanh gần gấp đôi và file nhẹ hơn
  // khoảng một phần ba; neural giữ màu glow mượt hơn octree.
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

/// Góc lật và độ nghiêng của khung thứ [i]: đứng mặt trước, lật sang mặt
/// sau, đứng, lật tiếp về mặt trước; lá đung đưa nhẹ để ánh sáng chạy.
({double turn, Offset pose}) _gifPose(int i) {
  const hold = 6;
  const flip = 12;
  final t = i / _gifFrameCount;
  double eased(int from) =>
      Curves.easeInOutCubic.transform((i - from) / flip) * math.pi;
  final turn = switch (i) {
    < hold => 0.0,
    < hold + flip => eased(hold),
    < 2 * hold + flip => math.pi,
    _ => math.pi + eased(2 * hold + flip),
  };
  final sway = t * 2 * math.pi;
  return (
    turn: turn,
    pose: Offset(math.sin(sway) * 0.35, math.cos(sway) * 0.15),
  );
}

enum _Choice { front, back, gif }

extension on _Choice {
  String get label => switch (this) {
    _Choice.front => 'Mặt trước',
    _Choice.back => 'Mặt sau',
    _Choice.gif => 'GIF 3D',
  };
}

Future<void> showRunCardShare(
  BuildContext context, {
  required RunCard card,
  required AchievementCardData data,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: gameNightTheme(),
        child: RunCardShareScreen(card: card, data: data),
      ),
    ),
  );
}

class RunCardShareScreen extends ConsumerStatefulWidget {
  const RunCardShareScreen({super.key, required this.card, required this.data});

  final RunCard card;
  final AchievementCardData data;

  @override
  ConsumerState<RunCardShareScreen> createState() => _RunCardShareScreenState();
}

class _RunCardShareScreenState extends ConsumerState<RunCardShareScreen> {
  final _stageKey = GlobalKey();
  final _backKey = GlobalKey();
  RunCardShareFiles? _files;
  Object? _error;
  bool _recording = false;
  bool _sharing = false;
  int _step = 0;
  double _turn = 0;
  Offset _pose = Offset.zero;
  _Choice _choice = _Choice.gif;

  String get _key => runCardShareKey(widget.card, widget.data.owner);

  @override
  void initState() {
    super.initState();
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

  /// Đặt lá theo [turn], [pose] rồi chụp sân khấu ở khung kế tiếp.
  Future<ui.Image> _shot(double turn, Offset pose, double pixelRatio) async {
    if (!mounted) throw StateError('Màn khoe đã đóng.');
    setState(() {
      _turn = turn;
      _pose = pose;
    });
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _stageKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  Future<RunCardShareFiles> _record() async {
    await Future<void>.delayed(_warmUp);
    if (!mounted) throw StateError('Màn khoe đã đóng.');
    Future<Uint8List> png(double turn) async {
      final image = await _shot(turn, Offset.zero, _stillPixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final front = await png(0);
    final back = await png(math.pi);
    final stageWidth = _stageKey.currentContext!.size!.width;
    final frames = <Uint8List>[];
    var width = 0;
    var height = 0;
    for (var i = 0; i < _gifFrameCount; i++) {
      if (!mounted) throw StateError('Màn khoe đã đóng.');
      setState(() => _step = i + 1);
      final p = _gifPose(i);
      final image = await _shot(p.turn, p.pose, _gifWidthPx / stageWidth);
      width = image.width;
      height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      frames.add(data!.buffer.asUint8List());
    }
    if (mounted) setState(() => _step = _gifFrameCount + 1);
    final gif = await compute(
      encodeCardGif,
      CardGifFrames(
        width: width,
        height: height,
        frameMs: _gifFrameMs,
        frames: frames,
      ),
    );
    return RunCardShareFiles(front: front, back: back, gif: gif);
  }

  Uint8List _bytes(RunCardShareFiles files, _Choice choice) => switch (choice) {
    _Choice.front => files.front,
    _Choice.back => files.back,
    _Choice.gif => files.gif,
  };

  Future<void> _share(BuildContext origin) async {
    final files = _files!;
    setState(() => _sharing = true);
    try {
      final gif = _choice == _Choice.gif;
      await shareRunCardFile(
        bytes: _bytes(files, _choice),
        mimeType: gif ? 'image/gif' : 'image/png',
        fileName: '3i-${widget.card.id}-${_choice.name}.${gif ? 'gif' : 'png'}',
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
                      ? Image.memory(
                          _bytes(files, _choice),
                          key: ValueKey(_choice),
                          gaplessPlayback: true,
                        )
                      : _error != null
                      ? _failed()
                      : _stage(),
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
                          bytes: _bytes(files, choice),
                          selected: choice == _choice,
                          onTap: () => setState(() => _choice = choice),
                        ),
                      ),
                    ],
                  ],
                ),
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

  /// Lá đang được ghi. Mặt sau là một element duy nhất mang [_backKey]: lá
  /// quay mặt trước thì nó nằm ngoài màn, lá lật thì nó chuyển lên sân khấu
  /// mà giữ nguyên state. Dựng mới lúc lật thì bản đồ phải tải tile và mờ dần
  /// từ đầu, khung chụp ngay sau đó mất bản đồ.
  Widget _stage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = achievementCardSize;
        final width = math.min(
          constraints.maxWidth * 0.8,
          (constraints.maxHeight - 60) * base.width / base.height * 0.8,
        );
        Widget back(Offset pose) => KeyedSubtree(
          key: _backKey,
          child: AchievementCard(data: widget.data, pose: pose, back: true),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tiltFlipShowsBack(pose: _pose, turn: _turn))
              Offstage(
                child: GameCardScaled(
                  width: width,
                  size: base,
                  child: back(Offset.zero),
                ),
              ),
            RepaintBoundary(
              key: _stageKey,
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
                    pose: _pose,
                    turn: _turn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              !_recording
                  ? 'Đang mở...'
                  : _step == 0
                  ? 'Đang chuẩn bị thẻ...'
                  : _step > _gifFrameCount
                  ? 'Đang ghép GIF...'
                  : 'Đang ghi khung $_step/$_gifFrameCount',
              style: const TextStyle(color: gameNightMuted),
            ),
          ],
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.bytes,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Uint8List bytes;
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
                child: Image.memory(bytes, gaplessPlayback: true),
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
