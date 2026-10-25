import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/share.dart';

/// Vẽ một mặt lá theo độ nghiêng [pose] (-1..1 mỗi chiều).
typedef CardFaceBuilder = Widget Function(Offset pose);

/// Điểm sáng (0..1 mỗi chiều) chạy ngược hướng nghiêng như ánh đèn trên mặt
/// thẻ thật.
Offset gameCardHoloAt(Offset pose) =>
    Offset(0.5 + pose.dx * 0.45, 0.35 + pose.dy * 0.35);

/// Mở lá bài Ma Sói toàn màn hình. Khi [canShare] là false (ván còn chạy,
/// người xem còn sống) thì khoá nút khoe, vì khoe lúc này là lộ vai.
Future<void> showGameCardViewer(
  BuildContext context, {
  required GameCardData card,
  required bool canShare,
  required List<String> chips,
}) {
  return showCardViewer(
    context,
    front: (pose) => card.front(holo: gameCardHoloAt(pose)),
    back: (pose) {
      final holo = gameCardHoloAt(pose);
      return GameCardBack(holo: Offset(1 - holo.dx, holo.dy));
    },
    chips: chips,
    hideWhenInactive: !canShare,
    onShare: canShare
        ? (cardKey, origin) => shareGameCard(
            cardKey: cardKey,
            shareOriginContext: origin,
            player: card.player,
          )
        : null,
    locked: const _LockedNote(),
  );
}

/// Mở một lá bài toàn màn hình: kéo để nghiêng, chạm để lật.
Future<void> showCardViewer(
  BuildContext context, {
  required CardFaceBuilder front,
  required CardFaceBuilder back,
  required List<String> chips,
  Size cardSize = gameCardSize,
  bool hideWhenInactive = false,
  Future<void> Function(GlobalKey cardKey, BuildContext origin)? onShare,
  Widget? locked,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => Theme(
        data: gameNightTheme(),
        child: GameCardViewer(
          front: front,
          back: back,
          chips: chips,
          cardSize: cardSize,
          hideWhenInactive: hideWhenInactive,
          onShare: onShare,
          locked: locked,
        ),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class GameCardViewer extends StatefulWidget {
  const GameCardViewer({
    super.key,
    required this.front,
    required this.back,
    required this.chips,
    this.cardSize = gameCardSize,
    this.hideWhenInactive = false,
    this.onShare,
    this.locked,
  });

  final CardFaceBuilder front;
  final CardFaceBuilder back;
  final List<String> chips;

  /// Kích thước gốc của lá, giữ đúng tỉ lệ khi phóng to.
  final Size cardSize;

  /// Lá còn bí mật: rời app là đóng lá, để ảnh app switcher không lộ.
  final bool hideWhenInactive;

  /// Null thì không có nút khoe; khi đó hiện [locked] nếu có.
  final Future<void> Function(GlobalKey cardKey, BuildContext origin)? onShare;
  final Widget? locked;

  @override
  State<GameCardViewer> createState() => _GameCardViewerState();
}

class _GameCardViewerState extends State<GameCardViewer>
    with WidgetsBindingObserver {
  final _captureKey = GlobalKey();
  final _card = GlobalKey<TiltFlipCardState>();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Lá còn bí mật thì rời app là đóng lá, như màn ván úp lá lại, để ảnh
  /// app switcher không lộ vai. Lá không bí mật thì giữ nguyên, vì bảng chia
  /// sẻ của iOS cũng làm app inactive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.hideWhenInactive || state == AppLifecycleState.resumed) return;
    // inactive rồi paused tới liền nhau; chỉ đóng một lần, kẻo đóng luôn màn ván.
    if (_closed || !mounted) return;
    // iOS chụp ảnh app switcher ngay lúc inactive, khi route còn đang mờ dần,
    // nên giấu lá ngay trong frame này rồi mới đóng.
    setState(() => _closed = true);
    Navigator.of(context).maybePop();
  }

  bool _closed = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _share(BuildContext buttonContext) async {
    setState(() => _sharing = true);
    try {
      // Mặt trước phải đang vẽ thì mới chụp được.
      await _card.currentState?.showFront();
      if (!buttonContext.mounted) return;
      await widget.onShare!(_captureKey, buttonContext);
    } catch (error) {
      debugPrint('Khoe thẻ lỗi: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa tạo được ảnh thẻ, thử lại sau.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cardWidth = math.min(media.size.width - 64, 340.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.6),
      body: GameNightBackdrop(
        glow: RunNowGameTokens.wolfGlow,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close_rounded),
                  color: gameNightInk,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final chip in widget.chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        chip,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: RunNowGameTokens.nightInkSoft,
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _closed
                      ? const SizedBox.shrink()
                      : TiltFlipCard(
                          key: _card,
                          front: widget.front,
                          back: widget.back,
                          width: cardWidth,
                          cardSize: widget.cardSize,
                          captureKey: _captureKey,
                        ),
                ),
              ),
              const Text(
                'Kéo để xoay · chạm để lật',
                style: TextStyle(fontSize: 13, color: gameNightMuted),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: widget.onShare != null
                    ? _shareButton()
                    : widget.locked ?? const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareButton() {
    return Builder(
      builder: (buttonContext) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _sharing ? null : () => _share(buttonContext),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(_sharing ? 'Đang tạo ảnh…' : 'Khoe thẻ'),
        ),
      ),
    );
  }
}

/// Một lá 3D: tự đung đưa nhẹ cho thấy ánh sáng chạy, kéo để nghiêng, chạm để
/// lật.
class TiltFlipCard extends StatefulWidget {
  const TiltFlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.width,
    this.cardSize = gameCardSize,
    this.captureKey,
  });

  final CardFaceBuilder front;
  final CardFaceBuilder back;

  /// Bề ngang lá trên màn; cao theo tỉ lệ [cardSize].
  final double width;

  /// Kích thước gốc của lá, giữ đúng tỉ lệ khi phóng to.
  final Size cardSize;

  /// Gắn vào mặt trước để chụp ảnh khoe.
  final GlobalKey? captureKey;

  @override
  State<TiltFlipCard> createState() => TiltFlipCardState();
}

class TiltFlipCardState extends State<TiltFlipCard>
    with TickerProviderStateMixin {
  /// Lật: 0 là mặt trước, 1 là mặt sau.
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  /// Thả tay thì lá trôi về giữa.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: 1,
  );

  /// Lá tự đung đưa nhẹ khi không ai chạm, để thấy ánh sáng chạy.
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  bool _dragging = false;

  @override
  void dispose() {
    _flip.dispose();
    _settle.dispose();
    _sway.dispose();
    super.dispose();
  }

  /// Lật về mặt trước, xong khi lá đã nằm yên.
  Future<void> showFront() async {
    if (_flip.value > 0) await _flip.reverse();
  }

  /// [local] là vị trí ngón tay trong lá, quy về -1..1 mỗi chiều.
  void _onDrag(Offset local, Size size) {
    _settle.stop();
    setState(() {
      _dragging = true;
      _drag = Offset(
        (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _onRelease() {
    _from = _drag;
    _dragging = false;
    _settle.forward(from: 0);
  }

  void _toggleFlip() {
    if (_flip.value < 0.5) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  /// Độ lệch hiện tại (-1..1): theo tay, đang trôi về, hay đung đưa.
  Offset _pose() {
    if (_dragging) return _drag;
    final settle = Curves.easeOutCubic.transform(_settle.value);
    final sway = _sway.value * 2 * math.pi;
    final idle = Offset(math.sin(sway) * 0.45, math.cos(sway) * 0.2);
    return Offset.lerp(_from, idle, settle)!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flip, _settle, _sway]),
      builder: (context, _) => _buildCard(),
    );
  }

  Widget _buildCard() {
    final base = widget.cardSize;
    final size = Size(widget.width, widget.width * base.height / base.width);
    return GestureDetector(
      onTap: _toggleFlip,
      onPanStart: (d) => _onDrag(d.localPosition, size),
      onPanUpdate: (d) => _onDrag(d.localPosition, size),
      onPanEnd: (_) => _onRelease(),
      onPanCancel: _onRelease,
      child: tiltFlipFace(
        front: widget.front,
        back: widget.back,
        width: widget.width,
        cardSize: base,
        pose: _pose(),
        turn: Curves.easeInOutCubic.transform(_flip.value) * math.pi,
        captureKey: widget.captureKey,
      ),
    );
  }
}

/// Lá đặt theo độ nghiêng [pose] (-1..1 mỗi chiều) và góc lật [turn] (radian
/// quanh trục dọc: 0 là mặt trước, π là mặt sau). [captureKey] gắn vào mặt
/// trước để chụp ảnh khoe.
Widget tiltFlipFace({
  required CardFaceBuilder front,
  required CardFaceBuilder back,
  required double width,
  required Size cardSize,
  required Offset pose,
  required double turn,
  GlobalKey? captureKey,
}) {
  final ry = pose.dx * gameCardMaxTilt + turn;
  final rx = -pose.dy * gameCardMaxTilt;
  final showBack = math.cos(ry) < 0;
  return Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateX(rx)
      ..rotateY(ry),
    child: showBack
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: GameCardScaled(
              width: width,
              size: cardSize,
              child: back(pose),
            ),
          )
        : RepaintBoundary(
            key: captureKey,
            child: GameCardScaled(
              width: width,
              size: cardSize,
              child: front(pose),
            ),
          ),
  );
}

class _LockedNote extends StatelessWidget {
  const _LockedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: gameNightGoldDeep),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ván còn đang chơi, khoe thẻ lúc này là lộ vai. Nút Khoe mở khi '
              'ván kết thúc hoặc khi bạn bị loại.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: RunNowGameTokens.nightInkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
