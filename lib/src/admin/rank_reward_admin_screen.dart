import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card_art.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/rank/rank_reward_widgets.dart';
import 'package:myrun/src/rank/reward_photo.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Backend trao thẻ cho top 10 (rank_card.go), quà chỉ treo trong dải đó.
const _maxRank = 10;

/// Kỳ cách kỳ đang chạy [offset] kỳ: âm là kỳ đã qua (đánh dấu đã trao), dương
/// là kỳ sau (treo quà trước).
PastRankingPeriod _periodOf(int offset, ClubRankingRange range, DateTime now) {
  var period = currentRankingPeriod(now, range);
  // start, end là 00:00 ngày VN ghi ở dạng UTC; dời về giữa ngày VN liền kề
  // rồi tính lại kỳ chứa ngày đó.
  for (var i = 0; i < offset; i++) {
    period = currentRankingPeriod(
      period.end.add(const Duration(hours: 5)),
      range,
    );
  }
  for (var i = 0; i > offset; i--) {
    period = currentRankingPeriod(
      period.start.subtract(const Duration(hours: 19)),
      range,
    );
  }
  return period;
}

/// Treo quà xa nhất là hai kỳ tới.
const _maxAhead = 2;

/// Treo quà cho một bảng BXH chung. Kỳ chưa bắt đầu sửa tự do, đang chạy chỉ
/// thêm, đã hết thì chỉ đánh dấu đã trao; backend giữ các luật này.
class RankRewardAdminScreen extends ConsumerStatefulWidget {
  const RankRewardAdminScreen({required this.admins, super.key});

  /// uid → tên của các admin, để chọn người trao.
  final Map<String, String> admins;

  @override
  ConsumerState<RankRewardAdminScreen> createState() =>
      _RankRewardAdminScreenState();
}

class _RankRewardAdminScreenState extends ConsumerState<RankRewardAdminScreen> {
  var _offset = 0;
  var _range = ClubRankingRange.currentWeek;
  var _sport = ClubRankingSport.run;
  RankRewardView? _view;
  List<RankRewardItem> _items = const [];
  String? _giver;
  Object? _error;
  bool _busy = false;

  late String _boardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  RunNowApiClient get _api => ref.read(runNowApiClientProvider);

  /// Bảng chốt lúc 12:00 giờ VN ngày sau kỳ; end là 00:00 ngày đó ghi dạng
  /// UTC nên 12:00 VN là end + 5 giờ.
  bool get _boardClosed => DateTime.now().isAfter(
    _periodOf(
      _offset,
      _range,
      DateTime.now(),
    ).end.add(const Duration(hours: 5)),
  );

  Future<void> _load() async {
    _boardId = rankBoardId(_periodOf(_offset, _range, DateTime.now()), _sport);
    final board = _boardId;
    setState(() {
      _view = null;
      _error = null;
    });
    try {
      final view = await _api.getRankRewards(board);
      if (!mounted || board != _boardId) return;
      _show(view);
    } catch (error) {
      if (mounted && board == _boardId) setState(() => _error = error);
    }
  }

  void _show(RankRewardView view) => setState(() {
    _view = view;
    _items = view.items;
    _giver = view.giverUid.isNotEmpty
        ? view.giverUid
        : widget.admins.keys.firstOrNull;
  });

  Future<void> _call(Future<RankRewardView> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _show(await action());
    } catch (error) {
      _toast(
        error is RunNowApiException ? error.message : 'Không lưu được: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _call(
    () => _api.setRankRewards(_boardId, giverUid: _giver ?? '', items: _items),
  );

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _edit(int? index) async {
    final view = _view!;
    final old = index == null ? null : _items[index];
    // Đang chạy thì món đã lưu chỉ đổi được biểu tượng, ảnh và thêm suất.
    final locked =
        old != null &&
        old.id.isNotEmpty &&
        view.state == RankRewardState.running;
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemEditor(
        boardId: _boardId,
        sport: _sport,
        others: [
          for (var i = 0; i < _items.length; i++)
            if (i != index) _items[i],
        ],
        item:
            old ??
            RankRewardItem(
              id: '',
              fromRank: 1,
              toRank: 1,
              name: '',
              icon: 'other',
            ),
        locked: locked,
        removable: !locked,
      ),
    );
    if (result == null) return;
    final items = [..._items];
    if (result.removed) {
      items.removeAt(index!);
    } else if (index == null) {
      items.add(result.item!);
    } else {
      items[index] = result.item!;
    }
    // Quà theo hạng theo thứ tự hạng, món bốc thăm sau và giữ thứ tự đã nhập:
    // backend bốc lần lượt, món sau không bốc lại người món trước đã trúng.
    final ranked = items.where((it) => !it.isDraw).toList()
      ..sort((a, b) => a.fromRank.compareTo(b.fromRank));
    setState(() => _items = [...ranked, ...items.where((it) => it.isDraw)]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final view = _view;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Quà BXH'),
        backgroundColor: palette.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Kỳ trước',
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  _offset--;
                  _load();
                },
              ),
              Expanded(
                child: Text(
                  pastRankingPeriodLabel(
                    _periodOf(_offset, _range, DateTime.now()),
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Kỳ sau',
                icon: const Icon(Icons.chevron_right),
                onPressed: _offset >= _maxAhead
                    ? null
                    : () {
                        _offset++;
                        _load();
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ClubRankingRange>(
                  segments: const [
                    ButtonSegment(
                      value: ClubRankingRange.currentWeek,
                      label: Text('Tuần'),
                    ),
                    ButtonSegment(
                      value: ClubRankingRange.currentMonth,
                      label: Text('Tháng'),
                    ),
                  ],
                  selected: {_range},
                  onSelectionChanged: (v) {
                    _range = v.first;
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<ClubRankingSport>(
                value: _sport,
                items: [
                  for (final s in ClubRankingSport.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(rankSportNames[s] ?? s.name),
                    ),
                ],
                onChanged: (s) {
                  if (s == null) return;
                  _sport = s;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            view == null ? '' : _stateLabel(view.state),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            TextButton(
              onPressed: _load,
              child: Text('Không tải được: $_error. Chạm để thử lại.'),
            )
          else if (view == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            for (var i = 0; i < _items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: RankRewardThumb(
                  icon: _items[i].icon,
                  photos: _items[i].photos,
                  size: 44,
                ),
                title: Text(
                  '${rankRewardRule(_items[i], _sport)} · ${_items[i].name}',
                ),
                subtitle: Text('${_items[i].photos.length} ảnh'),
                trailing: view.state == RankRewardState.closed
                    ? null
                    : const Icon(Icons.edit_outlined),
                onTap: view.state == RankRewardState.closed
                    ? null
                    : () => _edit(i),
              ),
            if (view.state != RankRewardState.closed) ...[
              TextButton.icon(
                onPressed: _items.length >= 10 ? null : () => _edit(null),
                icon: const Icon(Icons.add),
                label: const Text('Thêm món'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.admins.containsKey(_giver) ? _giver : null,
                decoration: const InputDecoration(labelText: 'Người trao'),
                items: [
                  for (final e in widget.admins.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (uid) => setState(() => _giver = uid),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Lưu quà'),
              ),
            ],
            if (view.state == RankRewardState.closed) ...[
              const SizedBox(height: 16),
              Text(
                view.winners.isNotEmpty
                    ? 'Người trúng'
                    : _boardClosed
                    ? 'Không ai trúng quà kỳ này.'
                    : 'Chưa có người trúng. Bảng chốt lúc 12:00 sau khi hết kỳ.',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final w in view.winners)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: w.givenAt != null,
                  title: Text('#${w.rank} ${w.displayName}'),
                  subtitle: Text(
                    w.receivedAt != null ? '${w.name} · đã nhận' : w.name,
                  ),
                  // Đã bấm nhận, hay trao quá 14 ngày (app người nhận đã hiện
                  // Đã nhận), thì backend không cho bỏ đánh dấu.
                  onChanged: _busy || w.receivedBy(DateTime.now())
                      ? null
                      : (given) => _call(
                          () => _api.setRankRewardGiven(
                            _boardId,
                            w.uid,
                            given: given ?? false,
                          ),
                        ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

String _stateLabel(RankRewardState state) => switch (state) {
  RankRewardState.upcoming => 'chưa bắt đầu',
  RankRewardState.running => 'đang chạy, chỉ thêm được',
  RankRewardState.closed => 'đã chốt',
};

class _EditResult {
  const _EditResult.saved(RankRewardItem this.item) : removed = false;
  const _EditResult.removed() : item = null, removed = true;

  final RankRewardItem? item;
  final bool removed;
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.boardId,
    required this.sport,
    required this.others,
    required this.item,
    required this.locked,
    required this.removable,
  });

  final String boardId;

  /// Mốc bốc thăm nhập theo km, riêng bảng Bước chân nhập theo bước.
  final ClubRankingSport sport;

  /// Các món khác của bảng, để chặn chồng hạng ngay trong sheet: backend chỉ
  /// báo chung "Quà không hợp lệ", còn đóng sheet rồi mới báo thì mất món vừa
  /// nhập.
  final List<RankRewardItem> others;
  final RankRewardItem item;

  /// Món đã lưu của kỳ đang chạy: không đổi tên, hạng, kiểu, mốc; suất chỉ
  /// thêm.
  final bool locked;
  final bool removable;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _minScore = TextEditingController(
    text: widget.item.isDraw ? _scoreText(widget.item.minScore) : '',
  );
  late final _slots = TextEditingController(
    text: widget.item.isDraw ? '${widget.item.slots}' : '',
  );
  late var _item = widget.item;
  bool _uploading = false;

  bool get _steps => widget.sport == ClubRankingSport.steps;

  String _scoreText(double score) => _steps || score % 1000 == 0
      ? '${(_steps ? score : score / 1000).round()}'
      : '${score / 1000}';

  /// Mốc sẽ gửi đi, đơn vị backend (mét hay bước); sai thì null. Món đã
  /// khoá giữ đúng mốc đã lưu: backend so mốc bằng !=, tính lại từ chữ trong ô
  /// mà lệch phần lẻ là cả lần lưu bị từ chối.
  double? get _parsedScore {
    if (widget.locked) return widget.item.minScore;
    final v = double.tryParse(_minScore.text.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) return null;
    final score = _steps ? v.roundToDouble() : (v * 1000).roundToDouble();
    // Số quá lớn nhân 1000 thành Infinity, gửi đi thì jsonEncode ném lỗi.
    return score > 0 && score.isFinite ? score : null;
  }

  void _setKind(String kind) => setState(() {
    if (kind == rankRewardDrawKind) {
      // Giữ số đã gõ nếu admin đổi qua đổi lại.
      if (_minScore.text.isEmpty) _minScore.text = _steps ? '70000' : '15';
      if (_slots.text.isEmpty) _slots.text = '1';
      _item = _item.copyWith(kind: kind, fromRank: 0, toRank: 0);
    } else {
      _item = _item.copyWith(kind: '', fromRank: 1, toRank: 1);
    }
  });

  @override
  void dispose() {
    _name.dispose();
    _minScore.dispose();
    _slots.dispose();
    super.dispose();
  }

  /// Lỗi của phần hạng hay phần bốc thăm, chặn nút Xong; null là hợp lệ.
  String? _ruleError() {
    if (!_item.isDraw) {
      final clash = widget.others
          .where(
            (o) =>
                !o.isDraw &&
                o.fromRank <= _item.toRank &&
                _item.fromRank <= o.toRank,
          )
          .firstOrNull;
      return clash == null
          ? null
          : 'Trùng hạng với ${clash.ranks} ${clash.name}.';
    }
    if (_parsedScore == null) return 'Nhập mốc lớn hơn 0.';
    final slots = int.tryParse(_slots.text.trim());
    if (slots == null || slots < 1) return 'Nhập số suất từ 1.';
    if (widget.locked && slots < widget.item.slots) {
      return 'Kỳ đang chạy chỉ thêm suất, không bớt dưới ${widget.item.slots}.';
    }
    final total = widget.others
        .where((o) => o.isDraw)
        .fold(slots, (sum, o) => sum + o.slots);
    if (total > rankRewardMaxDrawSlots) {
      return 'Tổng suất bốc thăm tối đa $rankRewardMaxDrawSlots.';
    }
    return null;
  }

  RankRewardItem _result(String name) => _item.isDraw
      ? _item.copyWith(
          name: name,
          minScore: _parsedScore!,
          slots: int.parse(_slots.text.trim()),
        )
      : _item.copyWith(name: name);

  Future<void> _addPhoto() async {
    setState(() => _uploading = true);
    try {
      final bytes = await pickRewardPhoto();
      if (bytes == null) return;
      final path = 'rankRewards/${widget.boardId}/${rewardPhotoName()}';
      await FirebaseStorage.instance
          .ref(path)
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      if (mounted) {
        setState(() => _item = _item.copyWith(photos: [..._item.photos, path]));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không tải ảnh lên: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final locked = widget.locked;
    final name = _name.text.trim();
    final ruleError = _ruleError();
    final valid =
        name.isNotEmpty &&
        name.runes.length <= rankRewardNameMaxRunes &&
        _item.fromRank <= _item.toRank &&
        ruleError == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !locked,
              maxLength: rankRewardNameMaxRunes,
              decoration: const InputDecoration(labelText: 'Tên quà'),
              onChanged: (_) => setState(() {}),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('Theo hạng')),
                ButtonSegment(
                  value: rankRewardDrawKind,
                  label: Text('Bốc thăm'),
                ),
              ],
              selected: {_item.kind},
              onSelectionChanged: locked ? null : (v) => _setKind(v.first),
            ),
            const SizedBox(height: 8),
            if (_item.isDraw)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minScore,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _steps ? 'Đạt từ (bước)' : 'Đạt từ (km)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _slots,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Số suất'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Text('Hạng'),
                  const SizedBox(width: 12),
                  _RankPicker(
                    value: _item.fromRank,
                    enabled: !locked,
                    onChanged: (v) => setState(
                      () => _item = _item.copyWith(
                        fromRank: v,
                        toRank: max(v, _item.toRank),
                      ),
                    ),
                  ),
                  const Text('  tới  '),
                  _RankPicker(
                    value: _item.toRank,
                    enabled: !locked,
                    min: _item.fromRank,
                    onChanged: (v) =>
                        setState(() => _item = _item.copyWith(toRank: v)),
                  ),
                ],
              ),
            if (ruleError != null)
              Text(
                ruleError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in rankRewardIcons.entries)
                  ChoiceChip(
                    label: Icon(e.value, size: 20),
                    selected: _item.icon == e.key,
                    onSelected: (_) =>
                        setState(() => _item = _item.copyWith(icon: e.key)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in _item.photos)
                  Stack(
                    children: [
                      RankRewardThumb(icon: _item.icon, photos: [path]),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _item = _item.copyWith(
                              photos: [
                                for (final p in _item.photos)
                                  if (p != path) p,
                              ],
                            ),
                          ),
                          child: Icon(Icons.cancel, color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                if (_item.photos.length < rankRewardMaxPhotos)
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _uploading ? null : _addPhoto,
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: _uploading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: valid && !_uploading
                  ? () => Navigator.of(
                      context,
                    ).pop(_EditResult.saved(_result(name)))
                  : null,
              child: const Text('Xong'),
            ),
            if (widget.removable)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _EditResult.removed()),
                child: const Text('Bỏ món này'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankPicker extends StatelessWidget {
  const _RankPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.min = 1,
  });

  final int value;
  final bool enabled;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: value,
      items: [
        for (var r = min; r <= _maxRank; r++)
          DropdownMenuItem(value: r, child: Text('#$r')),
      ],
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }
}
