import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:myrun/src/auth.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/sync.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return FirestoreStravaActivityRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FirestoreFeedRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final trainingGoalRepositoryProvider = Provider<TrainingGoalRepository>((ref) {
  return FirestoreTrainingGoalRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final firebaseUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();
        if (data == null) return null;
        final lastSyncedAt = data['lastSyncedAt'];
        return UserProfile.fromMap({
          ...data,
          if (lastSyncedAt is Timestamp) 'lastSyncedAt': lastSyncedAt.toDate(),
        });
      });
});

final stravaAuthProvider = ChangeNotifierProvider<StravaAuthController>(
  (ref) => StravaAuthController(FirebaseAuth.instance),
);

final activitiesProvider = StreamProvider<List<ActivitySummary>>(
  (ref) => ref.watch(activityRepositoryProvider).watchActivities(),
);

final activityDetailProvider = FutureProvider.family<ActivityDetail, String>((
  ref,
  activityId,
) {
  return ref.watch(activityRepositoryProvider).getDetail(activityId);
});

final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(ref.watch(activityRepositoryProvider)),
);

final feedPostsProvider = StreamProvider<List<FeedPost>>(
  (ref) => ref.watch(feedRepositoryProvider).watchPosts(),
);

final trainingGoalsProvider = StreamProvider<TrainingGoals>(
  (ref) => ref.watch(trainingGoalRepositoryProvider).watchGoals(),
);
