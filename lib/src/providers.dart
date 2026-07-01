import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:myrun/src/auth.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_analytics.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/strava_client.dart';
import 'package:myrun/src/sync.dart';
import 'package:myrun/src/tracking_draft_store.dart';
import 'package:myrun/src/tracking_location_provider.dart';
import 'package:myrun/src/theme_controller.dart';

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

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return FirestoreMemberRepository(
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

final liveTrackingRepositoryProvider = Provider<LiveTrackingRepository>((ref) {
  return FirestoreLiveTrackingRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final runContractRepositoryProvider = Provider<RunContractRepository>((ref) {
  return FirestoreRunContractRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final runContractAnalyticsProvider = Provider<RunContractAnalytics>((ref) {
  return RunContractAnalytics(FirebaseAnalytics.instance);
});

enum ClubRecapRange { currentWeek, currentMonth }

enum ClubRankingMetric {
  distance,
  time,
  consistency,
  pace,
  longestRun,
  activityCount,
}

enum ClubRankingRange { rollingSevenDays, currentWeek, currentMonth }

/// Khoảng thời gian của tab "Tổng kết" club. Được hoist ra provider để filter
/// có thể render gộp chung trong navigation bar (xem [app.dart]).
final clubRecapRangeProvider = StateProvider<ClubRecapRange>(
  (ref) => ClubRecapRange.currentWeek,
);

/// Bộ lọc của tab "Xếp hạng" club, cũng hoist ra để gộp vào navigation bar.
final clubRankingMetricProvider = StateProvider<ClubRankingMetric>(
  (ref) => ClubRankingMetric.distance,
);
final clubRankingRangeProvider = StateProvider<ClubRankingRange>(
  (ref) => ClubRankingRange.currentWeek,
);

/// Index tab con của club (0 = Xếp hạng, 1 = Tổng kết...),
/// hoặc -1 khi không ở màn hình club. Nav bar dựa vào đây để hiện đúng filter.
final clubActiveSubTabProvider = StateProvider<int>((ref) => -1);

final trackingDraftStoreProvider = Provider<TrackingDraftStore>(
  (ref) => const TrackingDraftStore(),
);

final trackingLocationProvider = Provider<TrackingLocationProvider>(
  (ref) => const GeolocatorTrackingLocationProvider(),
);

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
  (ref) =>
      StravaAuthController(FirebaseAuth.instance, FirebaseFirestore.instance),
);

final stravaConnectionProvider = Provider<bool>((ref) {
  ref.watch(stravaAuthProvider);
  ref.watch(firebaseUserProvider);
  if (StravaClient.instance.isSignedIn) return true;
  // Web có thể vừa reload sau OAuth callback nên local token chưa kịp restore;
  // Firestore profile là trạng thái kết nối bền hơn cho UI.
  if (kIsWeb) {
    return ref
        .watch(userProfileProvider)
        .maybeWhen(
          data: (profile) => profile?.stravaConnected ?? false,
          orElse: () => false,
        );
  }
  return false;
});

final googleAuthProvider = ChangeNotifierProvider<GoogleAuthController>(
  (ref) =>
      GoogleAuthController(FirebaseAuth.instance, FirebaseFirestore.instance),
);

final themeControllerProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => ThemeController(),
);

final activitiesProvider = StreamProvider<List<ActivitySummary>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(activityRepositoryProvider).watchActivities();
});

final trackedTrialActivitiesProvider = StreamProvider<List<ActivitySummary>>((
  ref,
) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(activityRepositoryProvider).watchTrackedTrialActivities();
});

final activityDetailProvider = FutureProvider.family<ActivityDetail, String>((
  ref,
  activityId,
) {
  return ref.watch(activityRepositoryProvider).getDetail(activityId);
});

final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(ref.watch(activityRepositoryProvider)),
);

final runContractControllerProvider = Provider<RunContractController>((ref) {
  return RunContractController(
    ref.watch(runContractRepositoryProvider),
    ref.watch(activityRepositoryProvider),
    ref.watch(syncControllerProvider),
  );
});

/// Các kèo đang chạy mà user tham gia (tạo hoặc join), tối đa
/// [maxActiveRunContracts].
final myActiveContractsProvider = StreamProvider<List<RunContract>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(runContractRepositoryProvider).watchMyActiveContracts();
});

final clubRunContractsProvider = StreamProvider<List<RunContract>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(runContractRepositoryProvider).watchClubContracts();
});

final runContractProvider = StreamProvider.family<RunContract?, String>((
  ref,
  contractId,
) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(runContractRepositoryProvider).watchContract(contractId);
});

final feedPostsProvider = StreamProvider<List<FeedPost>>(
  (ref) => ref.watch(feedRepositoryProvider).watchPosts(),
);

final membersProvider = StreamProvider<List<MemberProfile>>(
  (ref) => ref.watch(memberRepositoryProvider).watchMembers(),
);

final leaderboardEntriesProvider = StreamProvider<List<LeaderboardEntry>>(
  (ref) => ref.watch(memberRepositoryProvider).watchLeaderboardEntries(),
);

final clubLiveSessionsProvider = StreamProvider<List<LiveTrackingSession>>(
  (ref) => ref.watch(liveTrackingRepositoryProvider).watchClubLiveSessions(),
);

final memberProfileProvider = StreamProvider.family<MemberProfile?, String>((
  ref,
  uid,
) {
  return ref.watch(memberRepositoryProvider).watchMember(uid);
});

final memberActivitiesProvider =
    StreamProvider.family<List<ActivitySummary>, String>((ref, uid) {
      return ref.watch(memberRepositoryProvider).watchMemberActivities(uid);
    });

final memberActivityDetailProvider =
    FutureProvider.family<ActivityDetail, ({String uid, String activityId})>((
      ref,
      request,
    ) {
      return ref
          .watch(memberRepositoryProvider)
          .getMemberActivityDetail(request.uid, request.activityId);
    });

final clubActivityLogProvider = StreamProvider<List<ClubActivityLogItem>>((
  ref,
) {
  final repository = ref.watch(memberRepositoryProvider);
  final membersState = ref.watch(membersProvider);
  return membersState.when(
    data: (members) {
      final publicMembers = members.where((member) => member.isPublic).toList();
      if (publicMembers.isEmpty) {
        return Stream.value(const <ClubActivityLogItem>[]);
      }
      final controller = StreamController<List<ClubActivityLogItem>>();
      final latestByUid = <String, List<ActivitySummary>>{};
      final subscriptions = <StreamSubscription<List<ActivitySummary>>>[];

      void emit() {
        final items = <ClubActivityLogItem>[];
        for (final member in publicMembers) {
          final activities =
              latestByUid[member.uid] ?? const <ActivitySummary>[];
          for (final activity in activities) {
            items.add(ClubActivityLogItem(member: member, activity: activity));
          }
        }
        items.sort(
          (left, right) =>
              right.activity.startedAt.compareTo(left.activity.startedAt),
        );
        if (!controller.isClosed) {
          controller.add(items);
        }
      }

      for (final member in publicMembers) {
        subscriptions.add(
          repository.watchMemberActivities(member.uid).listen((activities) {
            latestByUid[member.uid] = activities;
            emit();
          }, onError: controller.addError),
        );
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
      return controller.stream;
    },
    loading: () => Stream.value(const <ClubActivityLogItem>[]),
    error: (error, stack) => Stream.error(error, stack),
  );
});

final trainingGoalsProvider = StreamProvider<TrainingGoals>(
  (ref) => ref.watch(trainingGoalRepositoryProvider).watchGoals(),
);

class ClubActivityLogItem {
  const ClubActivityLogItem({required this.member, required this.activity});

  final MemberProfile member;
  final ActivitySummary activity;
}
