import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/prc_brand_mark.dart';
import 'package:myrun/src/widgets/strava_activity_link.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedPostsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: posts.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Chưa có bài đăng. Mở một hoạt động và chọn “Đăng lên feed”.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _FeedPostCard(post: items[index]),
              ),
        error: (error, stack) =>
            Center(child: Text('Không thể tải feed: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final activity = post.activity;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.authorName, style: Theme.of(context).textTheme.titleMedium),
          Text(formatDate(post.createdAt)),
          const SizedBox(height: 12),
          Text(activity.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              Text(formatDistance(activity.distanceMeters)),
              Text(formatDuration(activity.movingTimeSeconds)),
              Text(formatPace(activity.paceSecondsPerKm)),
              if (activity.averageHeartRate != null)
                Text('${activity.averageHeartRate!.round()} bpm'),
            ],
          ),
          const SizedBox(height: 12),
          const PrcBrandMark(),
          StravaActivityLink(activityId: activity.id),
        ],
      ),
    );
  }
}
