import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/club_card_widgets.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/providers.dart';

/// Trang "Thẻ của club": thẻ mọi người đang khoe, chia ba tab.
class ClubCardsScreen extends ConsumerWidget {
  const ClubCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(clubCardsProvider);
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final Widget body;
    if (cards.error case final error?) {
      debugPrint('Không tải được thẻ của club: $error');
      body = Center(
        child: TextButton(
          onPressed: () => ref.invalidate(clubCardsProvider),
          child: const Text('Không tải được thẻ. Chạm để thử lại.'),
        ),
      );
    } else if (cards.value case final all?) {
      body = TabBarView(
        children: [
          _Grid(items: all, empty: 'Chưa ai khoe thẻ.'),
          _Grid(
            items: rareFirst(all),
            empty: 'Chưa có thẻ hiếm nào được khoe.',
          ),
          _Grid(
            items: [
              for (final item in all)
                if (item.ownerUid == myUid) item,
            ],
            empty:
                'Bạn chưa có thẻ nào trên club. Thẻ tự lên club khi hồ sơ '
                'của bạn để công khai.',
          ),
        ],
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thẻ của club'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mới'),
              Tab(text: 'Hiếm+'),
              Tab(text: 'Của bạn'),
            ],
          ),
        ),
        body: body,
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items, required this.empty});

  final List<ClubCard> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        // Đúng tỉ lệ thẻ 300x420: chủ thẻ và nút tim nằm trên mặt thẻ.
        childAspectRatio: 300 / 420,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => ClubCardTile(item: items[i]),
    );
  }
}
