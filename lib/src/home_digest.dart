import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';

/// Bài điểm tin buổi sáng 3i viết, backend ghi `homeDigests/{YYYY-MM-DD}`
/// (giờ VN).
class HomeDigest {
  const HomeDigest({
    required this.day,
    required this.title,
    required this.body,
  });

  factory HomeDigest.fromMap(Map<String, dynamic> map) => HomeDigest(
    day: map['day'] as String? ?? '',
    title: map['title'] as String? ?? '',
    body: map['body'] as String? ?? '',
  );

  final String day;
  final String title;
  final String body;

  /// Bài còn đáng hiện: của hôm nay hoặc hôm qua theo giờ VN. Bài cũ hơn
  /// nghĩa là job sáng nay chưa chạy hay đang tắt, thì thôi không hiện tin cũ.
  bool freshAt(DateTime now) {
    final vn = now.toUtc().add(const Duration(hours: 7));
    final today = DateFormat('yyyy-MM-dd').format(vn);
    final yesterday = DateFormat(
      'yyyy-MM-dd',
    ).format(vn.subtract(const Duration(days: 1)));
    return day == today || day == yesterday;
  }
}

/// Nguồn đọc điểm tin; test thay bằng Firestore giả.
final homeDigestFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Bài mới nhất. `day` là chuỗi ngày nên xếp chữ cũng là xếp theo ngày.
final homeDigestProvider = StreamProvider.autoDispose<HomeDigest?>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref
      .watch(homeDigestFirestoreProvider)
      .collection('homeDigests')
      .orderBy('day', descending: true)
      .limit(1)
      .snapshots()
      .map(
        (snap) => snap.docs.isEmpty
            ? null
            : HomeDigest.fromMap(snap.docs.single.data()),
      );
});

/// Thẻ "3i điểm tin" ở đầu Trang chủ. Chưa có bài hôm nay hay hôm qua thì ẩn.
class HomeDigestCard extends ConsumerWidget {
  const HomeDigestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(homeDigestProvider);
    return digest.when(
      data: (post) {
        if (post == null || !post.freshAt(DateTime.now())) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: _DigestPanel(post: post),
        );
      },
      // Điểm tin chỉ là phần thêm: lỗi thì báo một dòng, Trang chủ vẫn dùng
      // được.
      error: (error, _) {
        debugPrint('home digest: $error');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref.invalidate(homeDigestProvider),
              child: const Text('Không tải được điểm tin. Chạm để thử lại.'),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
    );
  }
}

class _DigestPanel extends StatelessWidget {
  const _DigestPanel({required this.post});

  final HomeDigest post;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [palette.accent.withValues(alpha: 0.18), palette.glassStart],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_rounded, size: 18, color: palette.accent),
              const SizedBox(width: 6),
              Text(
                '3I ĐIỂM TIN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            post.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            post.body,
            style: TextStyle(
              height: 1.4,
              color: onSurface.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
