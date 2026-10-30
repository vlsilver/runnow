import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_art_sheet.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowAchievementTokens;
const _condensed = 'Barlow Condensed';

/// Backend coi khoá vẽ quá 3 phút là treo và cho khoá lại; app chờ thêm một
/// phút cho lệch đồng hồ rồi mới mời vẽ lại.
const _artStuckAfter = Duration(minutes: 4);

/// Thẻ của một buổi chạy của chính mình: chưa lật thì úp thẻ kèm tỉ lệ và nút
/// lật; lật rồi thì hiện thẻ, chọn mặt để khoe.
class RunCardPanel extends ConsumerStatefulWidget {
  const RunCardPanel({super.key, required this.activity, required this.owner});

  final ActivitySummary activity;

  /// Tên in trên thẻ.
  final String owner;

  @override
  ConsumerState<RunCardPanel> createState() => _RunCardPanelState();
}

class _RunCardPanelState extends ConsumerState<RunCardPanel> {
  bool _rolling = false;
  bool _redrawing = false;

  /// Thẻ vừa lật trong phiên này thì chạy hiệu ứng lật mặt; mở lại thẻ cũ thì
  /// hiện thẳng.
  bool _justRolled = false;

  String get _id => widget.activity.id;

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(runCardProvider(_id));
    return card.when(
      data: (card) =>
          card == null ? _unrolled(context) : _rolled(context, card),
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _Message('Không tải được thẻ: $error'),
    );
  }

  Widget _unrolled(BuildContext context) {
    final view = ref.watch(runCardViewProvider(_id));
    final km = (widget.activity.distanceMeters / 100).round() / 10;
    final faceDown = _CardFrame(
      child: RunCardFaceDown(km: km, title: widget.activity.name),
    );
    return view.when(
      loading: () => Column(
        children: [
          faceDown,
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
        ],
      ),
      error: (error, _) => Column(
        children: [
          faceDown,
          _Message('Không tải được tỉ lệ: $error'),
          TextButton(
            onPressed: () => ref.invalidate(runCardViewProvider(_id)),
            child: const Text('Thử lại'),
          ),
        ],
      ),
      data: (view) {
        // Thẻ vừa có ở chỗ khác (máy khác lật) thì stream sẽ tự đổi.
        if (view.card != null) return faceDown;
        if (view.reason case final reason?) {
          return Column(
            children: [
              _CardFrame(
                child: RunCardFaceDown(
                  km: km,
                  title: widget.activity.name,
                  failure: runCardFailureLabel(reason),
                ),
              ),
              _Message(runCardReasonText(reason)),
            ],
          );
        }
        return Column(
          children: [
            faceDown,
            const SizedBox(height: 16),
            _OddsTable(km: km, odds: view.odds),
            const SizedBox(height: 8),
            if (view.chance < 100)
              _Message(
                'Buổi này có ${_percent(view.chance)}% cơ hội ra thẻ. Trượt '
                'thì buổi này không lật lại được.',
              )
            else
              const _Message(
                'Mỗi buổi chạy chỉ lật một lần, không lật lại được.',
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _rolling ? null : _roll,
              icon: _rolling
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flip_rounded),
              label: Text(_rolling ? 'Đang lật...' : 'Lật thẻ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _roll() async {
    setState(() => _rolling = true);
    try {
      await ref.read(runNowApiClientProvider).rollRunCard(_id);
      // Thẻ hiện khi stream doc báo về, thường ngay sau đó.
      if (mounted) setState(() => _justRolled = true);
    } catch (error) {
      if (!mounted) return;
      // Trượt là kết quả, không phải lỗi: view tải lại sẽ báo trượt.
      if (error is RunNowApiException && error.code == 'card_missed') {
        ref.invalidate(runCardViewProvider(_id));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không lật được thẻ: $error')));
      ref.invalidate(runCardViewProvider(_id));
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  Widget _rolled(BuildContext context, RunCard card) {
    final data = runCardData(card, owner: widget.owner);
    final km = card.km;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final shown = Semantics(
      button: true,
      label: 'Xem thẻ 3D',
      child: GestureDetector(
        onTap: () => showRunCardViewer(context, card, data),
        child: _CardFrame(child: AchievementCard(data: data)),
      ),
    );
    return Column(
      children: [
        if (_justRolled)
          CardFlipReveal(
            from: _CardFrame(
              child: RunCardFaceDown(km: km, title: card.snapshot.name),
            ),
            to: shown,
          )
        else
          shown,
        const SizedBox(height: 10),
        Text(
          '${gameCardTiers[card.tier]!.label} · ${runCardKm(km)} km · '
          'chạm thẻ để xem 3D',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          'Đã lưu vào Bộ thẻ trong Hồ sơ.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        ..._artStatus(card, muted),
        // Nút vẽ và nút khoe chung một hàng cho đỡ tốn chỗ; đang vẽ hay vẽ
        // xong thì chỉ còn nút khoe.
        Row(
          children: [
            if (_drawButton(card) case final draw?) ...[
              Expanded(child: draw),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    showRunCardShare(context, card: card, data: data),
                icon: const Icon(Icons.ios_share),
                label: const Text('Khoe thẻ'),
              ),
            ),
            // Thẻ Ẩn luôn mặc màu hành của nó, bộ màu chọn ở đây không đổi
            // được thẻ này.
            if (card.secret == null) ...[
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Bộ màu thẻ',
                onPressed: () => showRunCardSkinSheet(context, sample: data),
                icon: const Icon(Icons.palette_outlined),
              ),
            ],
          ],
        ),
        if (card.art == null) ...[
          const SizedBox(height: 6),
          Text(
            'Chọn một phong cách. Vẽ xong thì cố định.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// Nút mở sheet chọn phong cách: chưa vẽ hay vẽ hỏng mới có.
  Widget? _drawButton(RunCard card) {
    void choose() => showRunCardArtSheet(
      context,
      card: card,
      photos: widget.activity.photos,
    );
    return switch (card.art?.status) {
      null => OutlinedButton.icon(
        onPressed: choose,
        icon: const Icon(Icons.brush_outlined),
        label: const Text('Vẽ tranh nền'),
      ),
      RunCardArtStatus.failed => FilledButton.tonalIcon(
        onPressed: choose,
        icon: const Icon(Icons.brush_outlined),
        label: const Text('Vẽ lại'),
      ),
      _ => null,
    };
  }

  /// Trạng thái tranh nền dưới thẻ: đang vẽ hay vẽ hỏng. Chưa vẽ thì chỉ có
  /// nút, vẽ xong thì không còn gì để báo.
  List<Widget> _artStatus(RunCard card, Color muted) {
    final hint = TextStyle(color: muted, fontSize: 12);
    final art = card.art;
    return switch (art?.status) {
      null || RunCardArtStatus.done => const [],
      RunCardArtStatus.drawing => [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Flexible(child: Text('Đang vẽ tranh nền')),
          ],
        ),
        const SizedBox(height: 4),
        if (_stuck(art!)) ...[
          Text('Lâu quá chưa xong, có thể lần vẽ bị kẹt.', style: hint),
          TextButton(
            onPressed: _redrawing ? null : () => _redraw(art),
            child: const Text('Vẽ lại'),
          ),
        ] else
          Text(
            'Thoát ra cũng được, vẽ xong thẻ tự cập nhật.',
            textAlign: TextAlign.center,
            style: hint,
          ),
        const SizedBox(height: 14),
      ],
      RunCardArtStatus.failed => [
        _Message(runCardArtFailText(art!.reason)),
        const SizedBox(height: 10),
      ],
    };
  }

  bool _stuck(RunCardArt art) => switch (art.requestedAt) {
    final at? => DateTime.now().difference(at) > _artStuckAfter,
    null => false,
  };

  /// Gửi lại đúng lựa chọn cũ; backend thấy khoá đã treo thì khoá lại và đẩy
  /// task mới.
  Future<void> _redraw(RunCardArt art) async {
    setState(() => _redrawing = true);
    try {
      await ref
          .read(runNowApiClientProvider)
          .requestRunCardArt(
            _id,
            style: art.style,
            photoPath: art.photoPath,
            // Gửi lại đúng lựa chọn cũ, khác note là backend coi như đổi ý.
            note: art.note,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không vẽ lại được: $error')));
    } finally {
      if (mounted) setState(() => _redrawing = false);
    }
  }
}

/// Chữ to trên lá úp khi buổi không ra thẻ: trượt là lật thất bại, còn lại
/// (trùng buổi, không phải chạy bộ) là không có thẻ để lật.
String runCardFailureLabel(String reason) =>
    reason == 'card_missed' ? 'LẬT THẤT BẠI' : 'KHÔNG CÓ THẺ';

/// Câu cho người dùng ứng với mã lý do backend trả khi không lật được.
String runCardReasonText(String reason) => switch (reason) {
  'card_missed' =>
    'Lần lật này không ra thẻ. Buổi ngắn chỉ có một phần cơ hội, chạy dài '
        'hơn để chắc có thẻ.',
  'card_duplicate' =>
    'Buổi này trùng một buổi khác đã có thẻ (cùng lần chạy ghi ở hai nguồn), '
        'nên không lật thêm được.',
  _ => 'Chỉ buổi chạy bộ từ 500 m mới lật được thẻ.',
};

/// 20 thành "20", 12.5 thành "12,5".
String _percent(double p) => p == p.roundToDouble()
    ? p.toStringAsFixed(0)
    : p.toStringAsFixed(1).replaceAll('.', ',');

/// Xem thẻ 3D, lật hai mặt, khoe từ đó.
void showRunCardViewer(
  BuildContext context,
  RunCard card,
  AchievementCardData data,
) => showCardViewer(
  context,
  front: (pose) => AchievementCard(data: data, pose: pose),
  back: (pose) => AchievementCard(data: data, pose: pose, back: true),
  chips: [gameCardTiers[card.tier]!.label, '${runCardKm(card.km)} km'],
  cardSize: achievementCardSize,
  // Mở màn khoe từ trong màn xem để nó nằm trên màn xem.
  onShare: (_, origin) => showRunCardShare(origin, card: card, data: data),
);

/// Câu cho người dùng ứng với lý do lần vẽ tranh hỏng.
String runCardArtFailText(String? reason) => switch (reason) {
  'budget' => 'Hôm nay 3i đã dùng hết hạn mức vẽ tranh. Mai thử lại nhé.',
  'blocked' => 'Model từ chối vẽ lần này. Thử phong cách khác hoặc bỏ ảnh gốc.',
  'photo_missing' => 'Không tìm thấy ảnh gốc. Chọn lại ảnh rồi vẽ.',
  'style_unavailable' => 'Phong cách này vừa bị tắt. Chọn phong cách khác.',
  _ => 'Vẽ tranh bị lỗi. Thử lại sau ít phút.',
};

/// Thẻ vẽ ở kích thước gốc rồi thu theo bề ngang chỗ đặt, tối đa 300.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GameCardScaled(
        width: math.min(achievementCardSize.width, constraints.maxWidth),
        size: achievementCardSize,
        child: child,
      ),
    );
  }
}

/// Thẻ úp: chưa biết bậc nên khung than chì trơn, dấu hỏi ở giữa. Có
/// [failure] thì buổi này không ra thẻ: phủ tối cả mặt, icon và [failure]
/// to ở giữa thay cho lời mời lật.
class RunCardFaceDown extends StatelessWidget {
  const RunCardFaceDown({
    required this.km,
    required this.title,
    this.failure,
    super.key,
  });

  final double km;
  final String title;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final mark = skin.accent(GameCardTier.common);
    final label = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.8,
      color: mark,
    );
    return SizedBox.fromSize(
      size: achievementCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_T.graphite1, _T.graphite2, _T.graphite3, _T.graphite4],
            stops: [0, 0.38, 0.66, 1],
          ),
          boxShadow: const [
            BoxShadow(color: _T.drop, blurRadius: 44, offset: Offset(0, 22)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.9,
                  colors: [skin.backTop, skin.backBottom],
                  stops: const [0, 0.72],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BUỔI CHẠY', style: label),
                        const Spacer(),
                        if (failure == null) ...[
                          Center(
                            child: Text(
                              '?',
                              style: TextStyle(
                                fontFamily: _condensed,
                                fontWeight: FontWeight.w800,
                                fontSize: 120,
                                height: 1,
                                color: mark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text('LẬT ĐỂ XEM ĐỘ HIẾM', style: label),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${runCardKm(km)} KM',
                          style: TextStyle(
                            fontFamily: _condensed,
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            height: 1,
                            color: skin.hero,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: skin.hero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (failure case final failure?)
                    _FailVeil(failure, skin: skin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Màn tối phủ cả mặt lá úp khi buổi chạy không ra thẻ, icon và chữ to ở
/// giữa để nhìn là biết, không phải đọc dòng nhỏ bên dưới.
class _FailVeil extends StatelessWidget {
  const _FailVeil(this.text, {required this.skin});

  final String text;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: skin.failVeil,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.heart_broken_rounded, size: 84, color: skin.failInk),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _condensed,
              fontWeight: FontWeight.w800,
              fontSize: 40,
              height: 1,
              letterSpacing: 1.2,
              color: skin.failInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bảng tỉ lệ ra từng bậc cho buổi [km], bỏ các bậc 0%.
class _OddsTable extends StatelessWidget {
  const _OddsTable({required this.km, required this.odds});

  final double km;
  final List<RunCardOdd> odds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'TỈ LỆ CHO BUỔI ${runCardKm(km)} KM',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        for (final odd in odds)
          if (odd.percent > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: runCardGlow(odd.tier),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(gameCardTiers[odd.tier]!.label)),
                  Text(
                    '${odd.percent.toStringAsFixed(1).replaceAll('.', ',')}%',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
