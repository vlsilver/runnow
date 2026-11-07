import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_overview.dart';
import 'package:myrun/src/widgets/club_run_row.dart';

/// Trang "Buổi chạy": mọi buổi tập của club, mới trước, chia theo ngày.
class ClubRunsScreen extends ConsumerStatefulWidget {
  const ClubRunsScreen({super.key});

  @override
  ConsumerState<ClubRunsScreen> createState() => _ClubRunsScreenState();
}

class _ClubRunsScreenState extends ConsumerState<ClubRunsScreen> {
  static const _pageSize = 20;

  // Trang rỗng mà còn cursor (cả trang là buổi của người để riêng tư) thì đọc
  // tiếp ngay, nhưng không quá chừng này lần liền để khỏi gọi mãi.
  static const _emptyPagesInRow = 3;

  final _items = <ClubRunItem>[];
  String? _cursor;
  var _done = false;
  var _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _cursor = null;
      _done = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(runNowApiClientProvider);
      for (var i = 0; i < _emptyPagesInRow; i++) {
        final page = await fetchClubRuns(
          api,
          cursor: _cursor,
          limit: _pageSize,
        );
        if (!mounted) return;
        setState(() {
          _items.addAll(page.runs);
          _cursor = page.cursor;
          _done = page.cursor == null;
        });
        if (page.runs.isNotEmpty || _done) break;
      }
    } on Object catch (error) {
      debugPrint('Không tải được feed buổi chạy: $error');
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final now = DateTime.now();
    // Tổng mỗi ngày chỉ tính trên các buổi đã tải; ngày nằm vắt qua hai trang
    // thì tổng tăng thêm khi trang sau về.
    final days = <String, List<ClubRunItem>>{};
    for (final item in _items) {
      days
          .putIfAbsent(_dayLabel(item.activity.startedAt, now), () => [])
          .add(item);
    }
    for (final MapEntry(key: label, value: items) in days.entries) {
      rows.add(
        _DayHeader(
          label: label,
          total: clubRunsDayTotal(items.map((item) => item.activity)),
        ),
      );
      for (final item in items) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ClubRunPost(item: item),
          ),
        );
      }
    }
    final Widget tail;
    if (_error != null) {
      tail = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextButton(
          onPressed: _loadMore,
          child: const Text('Không tải được buổi chạy. Chạm để thử lại.'),
        ),
      );
    } else if (_loading) {
      tail = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_items.isEmpty) {
      tail = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Club chưa có buổi chạy nào.')),
      );
    } else if (!_done) {
      tail = Center(
        child: TextButton(onPressed: _loadMore, child: const Text('Xem thêm')),
      );
    } else {
      tail = const SizedBox(height: 24);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Buổi chạy')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [...rows, tail],
          ),
        ),
      ),
    );
  }
}

String _dayLabel(DateTime startedAt, DateTime now) {
  final label = sessionWhenLabel(startedAt, now);
  // Bỏ giờ ở cuối: "Hôm nay 04:10" thành "Hôm nay", "25/10 06:00" thành "25/10".
  return label.substring(0, label.lastIndexOf(' '));
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.total});

  final String label;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            total,
            style: TextStyle(
              color: context.runNowPalette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
