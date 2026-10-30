import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/club_share_switch.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';

/// Vẽ một mặt lá theo độ nghiêng [pose] (-1..1 mỗi chiều).
typedef CardFaceBuilder = Widget Function(Offset pose);

/// Mở thẻ Ma Sói của người xem toàn màn hình. Chỉ thẻ đã sở hữu (phe thắng,
/// ván đã xong) mới có nút khoe. [secret] là khi vai còn bí mật (ván chạy, người
/// xem còn sống): rời app là đóng thẻ.
Future<void> showGameCardViewer(
  BuildContext context, {
  required GamePlayerCard card,
  required AchievementCardData data,
  required bool secret,
  required List<String> chips,
}) {
  return showCardViewer(
    context,
    front: (pose) => AchievementCard(data: data, pose: pose),
    back: (pose) => AchievementCard(data: data, pose: pose, back: true),
    chips: chips,
    cardSize: achievementCardSize,
    hideWhenInactive: secret,
    // Mở màn khoe từ trong màn xem để nó nằm trên màn xem.
    onShare: card.owned
        ? (_, origin) => showCardShare(
            origin,
            subject: gameCardShareSubject(card, owner: data.owner),
            data: data,
          )
        : null,
    locked: _LockedNote(
      secret
          ? 'Ván còn đang chơi, khoe thẻ lúc này là lộ vai.'
          : card.ended
          ? 'Chỉ người phe thắng mới giữ và khoe được thẻ ván này.'
          : 'Thẻ chỉ khoe được khi ván kết thúc và phe bạn thắng.',
    ),
    // Backend chỉ có thẻ khi ván kết thúc và mình phe thắng; ván thử không
    // lên club.
    footer: card.owned && card.ended && !card.testMode
        ? ClubShareSwitch.kept(
            kind: 'game',
            id: card.gameId,
            offHint: 'Club sẽ thấy cả vai của bạn trong ván này.',
          )
        : null,
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
  Widget? footer,
  bool startBack = false,
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
          footer: footer,
          startBack: startBack,
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
    this.footer,
    this.startBack = false,
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

  /// Nằm dưới nút khoe, vd công tắc khoe với club.
  final Widget? footer;

  /// Mở lá đang úp để người xem tự chạm lật.
  final bool startBack;

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
                          startBack: widget.startBack,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.onShare != null
                        ? _shareButton()
                        : widget.locked ?? const SizedBox.shrink(),
                    ?widget.footer,
                  ],
                ),
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
    this.startBack = false,
  });

  final CardFaceBuilder front;
  final CardFaceBuilder back;

  /// Bề ngang lá trên màn; cao theo tỉ lệ [cardSize].
  final double width;

  /// Kích thước gốc của lá, giữ đúng tỉ lệ khi phóng to.
  final Size cardSize;

  /// Gắn vào mặt trước để chụp ảnh khoe.
  final GlobalKey? captureKey;

  /// Lá bắt đầu ở mặt sau.
  final bool startBack;

  @override
  State<TiltFlipCard> createState() => TiltFlipCardState();
}

class TiltFlipCardState extends State<TiltFlipCard>
    with TickerProviderStateMixin {
  /// Lật: 0 là mặt trước, 1 là mặt sau.
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.startBack ? 1 : 0,
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

/// Lá ở [pose], [turn] đang quay mặt sau ra ngoài thì [tiltFlipFace] dựng mặt
/// sau, còn không thì dựng mặt trước.
bool tiltFlipShowsBack({required Offset pose, required double turn}) =>
    math.cos(pose.dx * gameCardMaxTilt + turn) < 0;

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
  final showBack = tiltFlipShowsBack(pose: pose, turn: turn);
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
  const _LockedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: gameNightGoldDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
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

/// Lật từ [from] sang [to] quanh trục dọc trong 0,7 giây.
class CardFlipReveal extends StatelessWidget {
  const CardFlipReveal({super.key, required this.from, required this.to});

  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // Nửa đầu mặt úp quay đi, nửa sau mặt thẻ quay về.
        final angle = math.pi * (1 - t);
        final faceDown = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(faceDown ? math.pi - angle : angle),
          child: faceDown ? from : to,
        );
      },
    );
  }
}
