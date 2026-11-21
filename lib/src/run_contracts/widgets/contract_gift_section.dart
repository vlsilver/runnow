import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_reward_widgets.dart';
import 'package:myrun/src/run_contracts/contract_gift.dart';
import 'package:myrun/src/run_contracts/contract_gift_editor.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:url_launcher/url_launcher.dart';

/// Khối Quà ở màn chi tiết kèo: món treo, vé hay hạng của mình lúc kèo còn
/// chạy; người trúng, bốc thăm, trao và nhận sau khi job chốt kèo.
class ContractGiftSection extends ConsumerStatefulWidget {
  const ContractGiftSection({
    required this.contract,
    required this.gift,
    required this.uid,
    required this.names,
    super.key,
  });

  final RunContract contract;
  final ContractGift? gift;
  final String? uid;

  /// Tên hiển thị theo uid, gồm cả mình.
  final Map<String, String> names;

  @override
  ConsumerState<ContractGiftSection> createState() =>
      _ContractGiftSectionState();
}

class _ContractGiftSectionState extends ConsumerState<ContractGiftSection> {
  bool _busy = false;

  RunContract get _contract => widget.contract;
  bool get _owner => widget.uid == _contract.creatorUid;

  /// Chủ kèo còn sửa được quà: kèo chưa đóng và chưa hết kỳ chạy, như backend
  /// (errContractGiftLocked).
  bool get _editable {
    if (!_owner || !_contract.isActive) return false;
    final lifecycle = contractLifecycle(_contract, DateTime.now());
    return lifecycle == RunContractLifecycle.scheduled ||
        lifecycle == RunContractLifecycle.running;
  }

  String _name(String uid) => widget.names[uid] ?? '3i member';

  /// Hoàn tác trên snackbar có thể bấm sau khi đã rời màn: vẫn gọi API, chỉ
  /// bỏ phần cập nhật giao diện.
  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _busy = true);
    try {
      await action();
    } on RunNowApiException catch (error) {
      _toast(error.message);
    } catch (error) {
      _toast('Không gửi được: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _edit() async {
    final gift = widget.gift;
    final othersJoined = _contract.participants.keys.any(
      (uid) => uid != _contract.creatorUid,
    );
    final draft = await showContractGiftEditor(
      context,
      initial: gift == null ? null : ContractGiftDraft.of(gift),
      lockedIds: othersJoined && gift != null
          ? {for (final it in gift.items) it.id}
          : const {},
    );
    if (draft == null || !mounted) return;
    await _run(
      () => saveContractGifts(
        ref.read(runNowApiClientProvider),
        contractId: _contract.id,
        creatorUid: _contract.creatorUid,
        draft: draft,
      ),
    );
  }

  Future<void> _markGiven(ContractGiftWinner winner) async {
    final api = ref.read(runNowApiClientProvider);
    var done = false;
    await _run(() async {
      await api.setContractGiftGiven(_contract.id, winner.uid, given: true);
      done = true;
    });
    if (!done) return;
    _toast(
      'Đã trao cho ${_name(winner.uid)}',
      action: SnackBarAction(
        label: 'Hoàn tác',
        onPressed: () => unawaited(
          _run(
            () => api.setContractGiftGiven(
              _contract.id,
              winner.uid,
              given: false,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markReceived() => _run(
    () => ref
        .read(runNowApiClientProvider)
        .markContractGiftReceived(_contract.id),
  );

  Future<void> _message(String giverName) async {
    String? username;
    await _run(() async {
      username = await ref
          .read(runNowApiClientProvider)
          .getContractGiftContact(_contract.id);
    });
    // Lỗi thì _run đã báo; đừng đè bằng câu chưa liên kết.
    final tg = username;
    if (tg == null || !mounted) return;
    if (tg.isEmpty) {
      _toast('$giverName chưa liên kết Telegram.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse('https://t.me/$tg'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _toast('Không mở được Telegram.');
  }

  @override
  Widget build(BuildContext context) {
    final gift = widget.gift;
    if (gift == null || gift.items.isEmpty) {
      if (!_editable ||
          !contractGiftAllowed(_contract.visibility, _contract.metric)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _edit,
          icon: const Icon(Icons.card_giftcard),
          label: const Text('Treo quà'),
        ),
      );
    }
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassPanel(
        borderRadius: 0,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.card_giftcard, color: palette.accentDeep),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quà · ${gift.kind.label} · ${gift.slots} suất',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_editable)
                  TextButton(
                    onPressed: _busy ? null : _edit,
                    child: const Text('Sửa'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, item) in gift.items.indexed)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: RankRewardThumb(
                      icon: item.icon,
                      photos: item.photos,
                      size: 22,
                    ),
                    label: Text('${item.name} ×${item.slots}'),
                    onPressed: () => _showItem(context, gift, i),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (gift.resolved)
              ..._resolved(context, gift)
            else
              ..._open(context, gift),
          ],
        ),
      ),
    );
  }

  /// Kèo còn chạy: vé hay hạng của mình, và bao nhiêu người đang đạt.
  List<Widget> _open(BuildContext context, ContractGift gift) {
    final palette = context.runNowPalette;
    final qualified = contractGiftQualified(_contract);
    final n = qualified.length;
    final me = _contract.participantFor(widget.uid);
    final draw = gift.kind == ContractGiftKind.draw;
    String? mine;
    if (!_owner && me != null) {
      final rank = qualified.indexWhere((p) => p.uid == me.uid);
      if (rank < 0) {
        final goal = draw ? 'để có vé' : 'để vào bảng quà';
        // Chạy dài tính buổi dài nhất, không cộng dồn, nên không có "còn bao nhiêu".
        if (_contract.metric == RunContractMetric.longestRun) {
          mine =
              'Cần 1 buổi ≥ ${contractValueLabel(_contract.metric, _contract.targetValue)} $goal';
        } else {
          final left = (_contract.targetValue - me.progressValue).clamp(
            0.0,
            double.infinity,
          );
          mine = 'Còn ${contractValueLabel(_contract.metric, left)} $goal';
        }
      } else if (draw) {
        mine =
            'Bạn có vé bốc thăm · cơ hội ${n < gift.slots ? n : gift.slots}/$n';
      } else {
        mine = 'Bạn đang hạng ${rank + 1} trong số người đạt';
      }
    }
    return [
      if (mine != null)
        Text(mine, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(
        draw
            ? '$n vé · ${gift.slots} suất'
            : '$n người đạt · ${gift.slots} suất',
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
    ];
  }

  /// Sau khi chốt: người trúng, suất dư, kết quả của mình.
  List<Widget> _resolved(BuildContext context, ContractGift gift) {
    final palette = context.runNowPalette;
    if (gift.entrants.isEmpty) {
      return [
        Text(
          'Không ai về đích, quà không trao.',
          style: TextStyle(color: palette.textMuted),
        ),
      ];
    }
    final now = DateTime.now();
    final mine = widget.uid == null ? null : gift.winnerFor(widget.uid!);
    final entered = widget.uid != null && gift.entrants.contains(widget.uid);
    final left = gift.slots - gift.winners.length;
    final drew =
        gift.kind == ContractGiftKind.draw && gift.entrants.length > gift.slots;
    return [
      if (mine != null)
        _MyWin(
          gift: gift,
          winner: mine,
          busy: _busy,
          onMessage: () => _message(gift.giverName),
          onReceived: _markReceived,
        )
      else if (entered)
        Text(
          gift.kind == ContractGiftKind.draw
              ? 'Lần này chưa trúng · ${gift.entrants.length} vé, ${gift.slots} suất'
              : 'Lần này chưa có quà · ${gift.entrants.length} người đạt, ${gift.slots} suất',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      if (drew)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showContractGiftDraw(context, gift, _name),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Xem bốc thăm'),
          ),
        ),
      for (final w in gift.winners)
        _WinnerRow(
          title: _name(w.uid),
          item: gift.item(w.itemId)?.name ?? '',
          rank: w.rank,
          status: w.receivedBy(now)
              ? 'Đã nhận'
              : w.givenAt != null
              ? 'Đã trao'
              : null,
          onGive: _owner && w.givenAt == null && !_busy
              ? () => _markGiven(w)
              : null,
        ),
      if (left > 0)
        Text(
          'Dư $left suất',
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
    ];
  }
}

/// "3.2 km", "2 buổi": cùng đơn vị với thẻ tiến độ của kèo. Làm tròn lên
/// (km tới 0.1) để phần còn thiếu không hiện "0 km" khi chưa đạt.
String contractValueLabel(RunContractMetric metric, double value) =>
    switch (metric) {
      RunContractMetric.distance || RunContractMetric.longestRun => () {
        // Trừ epsilon để 3.2 (lưu là 3.2000000000000002) không thành 3.3.
        final km = (value * 10 - 1e-9).ceil() / 10;
        return '${km.toStringAsFixed(km % 1 == 0 ? 0 : 1)} km';
      }(),
      RunContractMetric.activityCount => '${value.ceil()} buổi',
      RunContractMetric.activeDays => '${value.ceil()} ngày',
      RunContractMetric.routeCompletion => '${value.ceil()} lần',
    };

class _WinnerRow extends StatelessWidget {
  const _WinnerRow({
    required this.title,
    required this.item,
    required this.rank,
    required this.status,
    required this.onGive,
  });

  final String title;
  final String item;
  final int? rank;
  final String? status;
  final VoidCallback? onGive;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' · $item',
                    style: TextStyle(color: palette.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                status!,
                style: TextStyle(color: palette.success, fontSize: 13),
              ),
            )
          else if (onGive != null)
            TextButton(onPressed: onGive, child: const Text('Đã trao'))
          else
            const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Mình trúng: món gì, nhắn người trao, báo đã nhận.
class _MyWin extends StatelessWidget {
  const _MyWin({
    required this.gift,
    required this.winner,
    required this.busy,
    required this.onMessage,
    required this.onReceived,
  });

  final ContractGift gift;
  final ContractGiftWinner winner;
  final bool busy;
  final VoidCallback onMessage;
  final VoidCallback onReceived;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final item = gift.item(winner.itemId);
    final received = winner.receivedBy(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.wash(palette.accent, 0.12),
        borderRadius: palette.radius(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankRewardThumb(
                icon: item?.icon ?? 'other',
                photos: item?.photos ?? const [],
                size: 44,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bạn trúng ${item?.name ?? 'quà'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      received
                          ? 'Đã nhận'
                          : winner.givenAt != null
                          ? '${gift.giverName} đã trao'
                          : '${gift.giverName} trao',
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!received) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onMessage,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      'Nhắn ${gift.giverName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onReceived,
                    child: const Text('Tôi đã nhận quà'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Xem một món: ảnh, tên, số suất, thứ tự bốc hay hạng nhận, người trao.
Future<void> _showItem(BuildContext context, ContractGift gift, int index) {
  final item = gift.items[index];
  final first = gift.items.take(index).fold(0, (sum, it) => sum + it.slots) + 1;
  final last = first + item.slots - 1;
  final order = gift.kind == ContractGiftKind.rank
      ? (first == last ? 'Hạng $first' : 'Hạng $first–$last')
      : 'Bốc thứ ${index + 1}';
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          Text(
            '${item.slots} suất · $order · ${gift.giverName} trao',
            style: TextStyle(color: context.runNowPalette.textMuted),
          ),
          const SizedBox(height: 12),
          RankRewardPhotos(icon: item.icon, photos: item.photos),
        ],
      ),
    ),
  );
}

/// Diễn lại lượt bốc: mỗi suất quay tên người có vé rồi dừng ở người trúng.
/// Kết quả đã có từ backend; sheet chỉ cho xem lại cho vui.
Future<void> showContractGiftDraw(
  BuildContext context,
  ContractGift gift,
  String Function(String uid) name,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DrawSheet(gift: gift, name: name),
  );
}

class _DrawSheet extends StatefulWidget {
  const _DrawSheet({required this.gift, required this.name});

  final ContractGift gift;
  final String Function(String uid) name;

  @override
  State<_DrawSheet> createState() => _DrawSheetState();
}

class _DrawSheetState extends State<_DrawSheet> {
  /// Số suất đã lộ; suất ở chỉ số [_shown] đang quay.
  var _shown = 0;
  var _tick = 0;
  Timer? _timer;

  List<ContractGiftWinner> get _winners => widget.gift.winners;

  @override
  void initState() {
    super.initState();
    _spin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _spin() {
    _timer?.cancel();
    if (_shown >= _winners.length) return;
    var left = 14;
    _timer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      if (!mounted) return;
      setState(() {
        _tick++;
        if (--left <= 0) {
          timer.cancel();
          _shown++;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final gift = widget.gift;
    final entrants = gift.entrants;
    final spinning = _timer?.isActive ?? false;
    final done = _shown >= _winners.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bốc thăm', style: Theme.of(context).textTheme.titleLarge),
          Text(
            '${entrants.length} vé · ${gift.slots} suất',
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          for (final (i, w) in _winners.indexed)
            if (i <= _shown && i < _winners.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(gift.item(w.itemId)?.name ?? '')),
                    Text(
                      i < _shown
                          ? widget.name(w.uid)
                          : widget.name(entrants[_tick % entrants.length]),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: i < _shown ? palette.accentDeep : palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          if (done)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Xong'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _timer?.cancel();
                      setState(() => _shown = _winners.length);
                    },
                    child: const Text('Bỏ qua'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: spinning ? null : _spin,
                    child: const Text('Bốc tiếp'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
