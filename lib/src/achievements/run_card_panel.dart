import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_art_steps.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_stage.dart';
import 'package:myrun/src/achievements/run_card_style_sheet.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';

export 'package:myrun/src/achievements/run_card_stage.dart' show RunCardFrame;

typedef _T = RunNowAchievementTokens;
const _condensed = 'Barlow Condensed';

/// Backend coi khoá vẽ quá 3 phút là treo và cho khoá lại; app chờ thêm một
/// phút cho lệch đồng hồ rồi mới mời vẽ lại.
const _artStuckAfter = Duration(minutes: 4);

/// Các bước trên một thẻ, mỗi bước gọn một màn không phải cuộn: lật, xem kết
/// quả, rồi vẽ tranh nền.
class RunCardPanel extends ConsumerStatefulWidget {
  const RunCardPanel({
    super.key,
    required this.activity,
    required this.owner,
    required this.onDone,
  });

  final ActivitySummary activity;

  /// Tên in trên thẻ.
  final String owner;

  /// Xong thẻ này, đóng màn.
  final VoidCallback onDone;

  @override
  ConsumerState<RunCardPanel> createState() => _RunCardPanelState();
}

class _RunCardPanelState extends ConsumerState<RunCardPanel> {
  bool _rolling = false;
  bool _redrawing = false;

  /// Đang ở các bước vẽ tranh nền.
  bool _drawing = false;

  /// Vừa bấm lật trong phiên này: kết quả hiện ra thì chạy hiệu ứng lật mặt,
  /// mở lại thẻ cũ thì hiện thẳng. Bật trước khi gọi API vì doc thẻ có thể về
  /// trước response.
  bool _justRolled = false;

  String? _rollError;

  String get _id => widget.activity.id;

  /// Đã bấm lật mà kết quả chưa hiện thì không cho lật nữa.
  bool get _busy => _rolling || _justRolled;

  double get _km => (widget.activity.distanceMeters / 100).round() / 10;

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(runCardProvider(_id));
    final rolled = card.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Đóng',
                color: _T.hero,
                onPressed: widget.onDone,
                icon: const Icon(Icons.close_rounded),
              ),
              const Spacer(),
              if (rolled != null && !_drawing)
                IconButton(
                  tooltip: 'Khoe thẻ',
                  color: _T.hero,
                  onPressed: () => showRunCardShare(
                    context,
                    card: rolled,
                    data: runCardData(rolled, owner: widget.owner),
                  ),
                  icon: const Icon(Icons.ios_share),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: card.when(
              data: (card) =>
                  card == null ? _unrolled(context) : _rolled(context, card),
              loading: () => const Center(child: _StageSpinner()),
              error: (error, _) =>
                  Center(child: _Message('Không tải được thẻ: $error')),
            ),
          ),
        ),
      ],
    );
  }

  /// Thẻ ở giữa, co theo chỗ còn lại; chữ và nút dồn xuống đáy để nút chính
  /// luôn ở cùng một chỗ giữa các bước.
  Widget _step({
    required Widget card,
    Color? glow,
    List<Widget> details = const [],
    List<Widget> actions = const [],
  }) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (glow != null)
                Positioned.fill(
                  child: _RevealGlow(color: glow, animate: _justRolled),
                ),
              card,
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...details,
        if (details.isNotEmpty) const SizedBox(height: 14),
        ...actions,
      ],
    );
  }

  Widget _unrolled(BuildContext context) {
    final view = ref.watch(runCardViewProvider(_id));
    final title = widget.activity.name;
    final faceDown = RunCardFrame(
      child: RunCardFaceDown(km: _km, title: title),
    );
    return view.when(
      loading: () => _step(
        card: faceDown,
        actions: const [
          SizedBox(height: 54, child: Center(child: _StageSpinner())),
        ],
      ),
      error: (error, _) => _step(
        card: faceDown,
        details: [_Message('Không tải được tỉ lệ: $error')],
        actions: [
          FilledButton(
            style: stagePrimaryButton(context),
            onPressed: () => ref.invalidate(runCardViewProvider(_id)),
            child: const Text('Thử lại'),
          ),
        ],
      ),
      data: (view) {
        // Thẻ vừa có ở chỗ khác (máy khác lật) thì stream sẽ tự đổi.
        if (view.card != null) return _step(card: faceDown);
        if (view.reason case final reason?) {
          final failed = RunCardFrame(
            child: RunCardFaceDown(
              km: _km,
              title: title,
              failureReason: reason,
            ),
          );
          return _step(
            card: _justRolled
                ? CardFlipReveal(from: faceDown, to: failed)
                : failed,
            details: [_Message(runCardReasonText(reason))],
          );
        }
        return _step(
          card: Semantics(
            button: true,
            label: 'Lật thẻ buổi $title',
            child: GestureDetector(
              onTap: _busy ? null : _roll,
              child: faceDown,
            ),
          ),
          details: [
            if (_rollError case final error?) ...[
              _Message(error),
              const SizedBox(height: 10),
            ],
            _OddsStrip(odds: view.odds),
            if (view.chance < 100) ...[
              const SizedBox(height: 10),
              Text(
                '${_percent(view.chance)}% cơ hội ra thẻ · trượt là hết lượt',
                textAlign: TextAlign.center,
                style: stageHint,
              ),
            ],
          ],
          actions: [
            FilledButton.icon(
              style: stagePrimaryButton(context),
              onPressed: _busy ? null : _roll,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _T.shade,
                      ),
                    )
                  : const Icon(Icons.flip_rounded),
              label: Text(_busy ? 'Đang lật...' : 'Lật thẻ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _roll() async {
    setState(() {
      _rolling = true;
      _justRolled = true;
      _rollError = null;
    });
    try {
      await ref.read(runNowApiClientProvider).rollRunCard(_id);
      // Thẻ hiện khi stream doc báo về, thường ngay sau đó.
    } catch (error) {
      if (!mounted) return;
      // Trượt là kết quả, không phải lỗi: view tải lại sẽ báo trượt.
      if (error is RunNowApiException && error.code == 'card_missed') {
        ref.invalidate(runCardViewProvider(_id));
        return;
      }
      // Báo ngay trên màn chứ không dùng snackbar: snackbar che mất nút lật.
      setState(() {
        _justRolled = false;
        _rollError = 'Không lật được thẻ: $error';
      });
      ref.invalidate(runCardViewProvider(_id));
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  Widget _rolled(BuildContext context, RunCard card) {
    if (_drawing) {
      return RunCardArtSteps(
        card: card,
        photos: widget.activity.photos,
        owner: widget.owner,
        onClose: () => setState(() => _drawing = false),
      );
    }
    final km = card.km;
    final glow = runCardGlow(card.tier);
    final art = card.art;
    final drawLabel = runCardDrawLabel(card, fresh: 'Vẽ tranh nền');
    final drawing = art?.status == RunCardArtStatus.drawing && !_stuck(art!);
    // Model vẽ mất vài chục giây: giữ ảnh vừa chọn trên thẻ cho tới lúc có
    // tranh, thay vì quay về đường chạy như chưa làm gì.
    final data = runCardData(
      card,
      owner: widget.owner,
      previewArt: switch (art?.photoPath) {
        final path? when drawing => StoragePhoto(
          path: path,
          cacheWidth: 960,
          placeholder: RunDefaultArt(card: card),
        ),
        _ => null,
      },
    );
    final shown = Semantics(
      button: true,
      label: 'Xem thẻ 3D',
      child: GestureDetector(
        onTap: () => showRunCardViewer(context, card, data, onDraw: _openDraw),
        child: RunCardFrame(
          child: Stack(
            children: [
              AchievementCard(data: data),
              if (drawing) const Positioned.fill(child: _DrawingSheen()),
              if (_justRolled) const Positioned.fill(child: CardTapHint()),
            ],
          ),
        ),
      ),
    );
    return _step(
      glow: glow,
      card: _justRolled
          ? CardFlipReveal(
              from: RunCardFrame(
                child: RunCardFaceDown(km: km, title: card.snapshot.name),
              ),
              to: shown,
            )
          : shown,
      details: [
        Text(
          gameCardTiers[card.tier]!.label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _condensed,
            fontWeight: FontWeight.w800,
            fontSize: 30,
            height: 1,
            letterSpacing: 1.6,
            color: glow,
          ),
        ),
        ..._artStatus(card),
      ],
      actions: [
        // Giữ chiều cao hàng nút để thẻ không nhảy khi vẽ xong.
        SizedBox(
          height: 54,
          child: Row(
            children: [
              // Thẻ Ẩn luôn mặc đúng kiểu và màu hành của nó, không đổi được.
              if (card.secret == null) ...[
                RunCardStyleButton(
                  ring: stageLine,
                  onPressed: () =>
                      showRunCardStyleSheet(context, card: card, data: data),
                ),
                const SizedBox(width: 10),
              ],
              if (drawing) const Expanded(child: _DrawingLabel()),
              if (drawLabel case final label?)
                Expanded(
                  child: FilledButton.icon(
                    style: stagePrimaryButton(context),
                    onPressed: _openDraw,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(label),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Về sau bước vẽ thì thẻ hiện thẳng, không lật lại lần nữa.
  void _openDraw() {
    // Lần trước đã tải thì hiện bản đó ngay và tải lại ngầm.
    ref.invalidate(runCardStylesProvider);
    setState(() {
      _drawing = true;
      _justRolled = false;
    });
  }

  /// Dòng dưới thẻ khi tranh có chuyện: vẽ hỏng hay chờ quá lâu. Đang vẽ bình
  /// thường thì thẻ tự có ánh sáng lướt qua, không cần chữ.
  List<Widget> _artStatus(RunCard card) {
    final art = card.art;
    return switch (art?.status) {
      RunCardArtStatus.drawing when _stuck(art!) => [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Lâu quá chưa xong', style: stageHint),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _T.titleGold2),
              onPressed: _redrawing ? null : () => _redraw(art),
              child: const Text('Vẽ lại'),
            ),
          ],
        ),
      ],
      RunCardArtStatus.failed => [
        const SizedBox(height: 8),
        _Message(runCardArtFailText(art!.reason)),
      ],
      _ => const [],
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

/// Chữ to trên lá úp khi buổi này không tự có thẻ: trượt là lật thất bại, trùng
/// buổi thì thẻ thuộc buổi chính, còn lại là không có thẻ để lật.
String runCardFailureLabel(String reason) => switch (reason) {
  'card_missed' => 'LẬT THẤT BẠI',
  'card_duplicate' => 'ĐÃ MỞ Ở BUỔI CHÍNH',
  _ => 'KHÔNG CÓ THẺ',
};

/// Câu cho người dùng ứng với mã lý do backend trả khi không lật được.
String runCardReasonText(String reason) => switch (reason) {
  'card_missed' =>
    'Lần lật này không ra thẻ. Buổi ngắn chỉ có một phần cơ hội, chạy dài '
        'hơn để chắc có thẻ.',
  'card_duplicate' =>
    'Lần chạy này ghi ở hai nguồn nên thẻ nằm ở buổi chính. Mở buổi đó để '
        'lật và vẽ tranh.',
  _ => 'Chỉ buổi chạy bộ từ 500 m mới lật được thẻ.',
};

/// 20 thành "20", 12.5 thành "12,5".
String _percent(double p) => p == p.roundToDouble()
    ? p.toStringAsFixed(0)
    : p.toStringAsFixed(1).replaceAll('.', ',');

/// Nhãn nút vẽ: chưa vẽ hay vẽ hỏng mới có, đang vẽ hay vẽ xong thì null.
String? runCardDrawLabel(RunCard card, {String fresh = 'Vẽ nền'}) =>
    switch (card.art?.status) {
      null => fresh,
      RunCardArtStatus.failed => 'Vẽ lại',
      _ => null,
    };

/// Xem thẻ 3D, lật hai mặt, khoe từ đó. Có [onDraw] thì thẻ chưa có nền hiện
/// thêm nút vẽ.
void showRunCardViewer(
  BuildContext context,
  RunCard card,
  AchievementCardData data, {
  Widget? reaction,
  VoidCallback? onDraw,
}) {
  // Tranh có thể vẽ xong lúc đang xem nên thẻ đọc theo doc, không giữ bản lúc mở.
  AchievementCardData dataOf(RunCard? doc) =>
      doc == null ? data : runCardData(doc, owner: data.owner);
  Widget face(Offset pose, {bool back = false}) => Consumer(
    builder: (context, ref, _) => AchievementCard(
      data: dataOf(ref.watch(runCardProvider(card.id)).asData?.value),
      pose: pose,
      back: back,
    ),
  );
  showCardViewer(
    context,
    front: face,
    back: (pose) => face(pose, back: true),
    chips: [gameCardTiers[card.tier]!.label, '${runCardKm(card.km)} km'],
    cardSize: achievementCardSize,
    reaction: reaction,
    action: switch ((runCardDrawLabel(card), onDraw)) {
      (final label?, final onDraw?) => (
        label: label,
        icon: Icons.brush_outlined,
        onPressed: onDraw,
      ),
      _ => null,
    },
    // Thẻ Ẩn luôn mặc đúng kiểu và màu hành của nó, không đổi được.
    leading: card.secret != null
        ? null
        : Builder(
            builder: (origin) => RunCardStyleButton(
              ring: gameNightInk,
              onPressed: () {
                final doc = ProviderScope.containerOf(
                  origin,
                  listen: false,
                ).read(runCardProvider(card.id)).asData?.value;
                showRunCardStyleSheet(
                  origin,
                  card: doc ?? card,
                  data: dataOf(doc),
                );
              },
            ),
          ),
    // Mở màn khoe từ trong màn xem để nó nằm trên màn xem.
    onShare: (_, origin) {
      final doc = ProviderScope.containerOf(
        origin,
        listen: false,
      ).read(runCardProvider(card.id)).asData?.value;
      return showRunCardShare(origin, card: doc ?? card, data: dataOf(doc));
    },
  );
}

/// Câu cho người dùng ứng với lý do lần vẽ tranh hỏng.
String runCardArtFailText(String? reason) => switch (reason) {
  'budget' => 'Hôm nay 3i đã dùng hết hạn mức vẽ tranh. Mai thử lại nhé.',
  'blocked' => 'Model từ chối vẽ lần này. Thử phong cách khác hoặc bỏ ảnh gốc.',
  'photo_missing' => 'Không tìm thấy ảnh gốc. Chọn lại ảnh rồi vẽ.',
  'photo_invalid' => 'Ảnh này không dùng được. Chọn ảnh khác.',
  'style_photo_missing' => 'Không tìm thấy ảnh mẫu. Tải lại ảnh mẫu rồi vẽ.',
  'style_unavailable' => 'Phong cách này vừa bị tắt. Chọn phong cách khác.',
  _ => 'Vẽ tranh bị lỗi. Thử lại sau ít phút.',
};

/// Thẻ úp: chưa biết bậc nên khung than chì trơn, dấu hỏi ở giữa. Có
/// [failureReason] (mã lý do backend trả) thì buổi này không tự có thẻ: phủ tối
/// cả mặt, icon và chữ to ở giữa thay cho lời mời lật.
class RunCardFaceDown extends StatelessWidget {
  const RunCardFaceDown({
    required this.km,
    required this.title,
    this.failureReason,
    this.kind = 'BUỔI CHẠY',
    super.key,
  });

  /// Null thì bỏ dòng km, khi thẻ khoá mà không có số để in.
  final double? km;
  final String title;
  final String? failureReason;

  /// Loại thẻ in ở góc trên.
  final String kind;

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
          borderRadius: context.runNowPalette.radius(18),
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
            borderRadius: context.runNowPalette.radius(15),
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
                        Text(kind, style: label),
                        const Spacer(),
                        if (failureReason == null) ...[
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
                        if (km case final km?) ...[
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
                        ],
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
                  if (failureReason case final reason?)
                    _FailVeil(reason, skin: skin),
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
  const _FailVeil(this.reason, {required this.skin});

  final String reason;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: skin.failVeil,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            reason == 'card_duplicate'
                ? Icons.check_circle_rounded
                : Icons.heart_broken_rounded,
            size: 84,
            color: skin.failInk,
          ),
          const SizedBox(height: 12),
          Text(
            runCardFailureLabel(reason),
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

/// Bảng tỉ lệ ra từng bậc, bỏ các bậc 0%.
class RunCardOddsTable extends StatelessWidget {
  const RunCardOddsTable({super.key, required this.title, required this.odds});

  final String title;
  final List<RunCardOdd> odds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
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
                      shape: context.runNowPalette.round,
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, textAlign: TextAlign.center, style: stageHint),
    );
  }
}

class _StageSpinner extends StatelessWidget {
  const _StageSpinner();

  @override
  Widget build(BuildContext context) =>
      const CircularProgressIndicator(strokeWidth: 2, color: _T.titleGold2);
}

/// Vệt sáng lướt qua thẻ trong lúc đang làm tranh nền.
class _DrawingLabel extends StatelessWidget {
  const _DrawingLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: _T.titleGold2,
          ),
        ),
        SizedBox(width: 10),
        Text('Đang vẽ', style: TextStyle(color: _T.hero, fontSize: 15)),
      ],
    );
  }
}

class _DrawingSheen extends StatefulWidget {
  const _DrawingSheen();

  @override
  State<_DrawingSheen> createState() => _DrawingSheenState();
}

class _DrawingSheenState extends State<_DrawingSheen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: context.runNowPalette.radius(18),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final x = -2.0 + 4.0 * _controller.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(x - 0.7, -1),
                  end: Alignment(x + 0.7, 1),
                  colors: [
                    _T.hero.withValues(alpha: 0),
                    _T.hero.withValues(alpha: 0.32),
                    _T.hero.withValues(alpha: 0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Quầng màu của bậc thẻ loé lên sau lá vừa lật.
class _RevealGlow extends StatelessWidget {
  const _RevealGlow({required this.color, required this.animate});

  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : 1, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, t, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.75,
              colors: [
                color.withValues(alpha: 0.5 * t),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tỉ lệ từng bậc gói trong một dải màu và một hàng số, bỏ các bậc 0%.
class _OddsStrip extends StatelessWidget {
  const _OddsStrip({required this.odds});

  final List<RunCardOdd> odds;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final odd in odds)
        if (odd.percent > 0) odd,
    ];
    return Column(
      children: [
        ClipRRect(
          borderRadius: context.runNowPalette.radius(3),
          child: SizedBox(
            height: 6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final odd in shown)
                  Expanded(
                    flex: (odd.percent * 10).round().clamp(1, 1000),
                    child: ColoredBox(color: runCardGlow(odd.tier)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final odd in shown)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${odd.percent.toStringAsFixed(1).replaceAll('.', ',')}%',
                      style: TextStyle(
                        color: runCardGlow(odd.tier),
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gameCardTiers[odd.tier]!.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stageHint.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
