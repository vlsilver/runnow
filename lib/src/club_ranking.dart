import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/steps_format.dart';

/// Ba bảng xếp hạng của Club. Chạy/Đi bộ đọc tổng km chạy + đi bộ backend tính
/// sẵn (stepLeaderboardEntries.*TotalDistance), Bước chân đọc số bước, Đạp xe
/// đọc leaderboardEntries.ride.
enum ClubRankingSport { run, steps, bike }

enum ClubRankingRange { currentWeek, currentMonth }

class ClubRankedMember {
  const ClubRankedMember({
    required this.rank,
    required this.entry,
    required this.score,
  });

  final int rank;
  final LeaderboardEntry entry;

  /// Mét với Chạy/Đi bộ và Đạp xe, số bước với Bước chân.
  final double score;
}

double clubRankingScore(
  LeaderboardEntry entry,
  ClubRankingSport sport,
  ClubRankingRange range,
) {
  final stats = switch (range) {
    ClubRankingRange.currentWeek => entry.currentWeek,
    ClubRankingRange.currentMonth => entry.currentMonth,
  };
  return switch (sport) {
    ClubRankingSport.steps => stats.steps.toDouble(),
    ClubRankingSport.run || ClubRankingSport.bike => stats.distanceMeters,
  };
}

/// Chỉ người public có số trong kỳ mới có hạng: 0 km hay 0 bước thì không có
/// gì để xếp. Bằng số thì chung hạng, người sau nhảy hạng (1, 1, 3).
List<ClubRankedMember> rankClubMembers(
  List<LeaderboardEntry> entries,
  ClubRankingSport sport,
  ClubRankingRange range,
) {
  final scored =
      [
        for (final entry in entries)
          if (entry.isPublic)
            (entry: entry, score: clubRankingScore(entry, sport, range)),
      ].where((item) => item.score > 0).toList()..sort((left, right) {
        final byScore = right.score.compareTo(left.score);
        if (byScore != 0) return byScore;
        return left.entry.displayName.compareTo(right.entry.displayName);
      });
  final ranked = <ClubRankedMember>[];
  for (var i = 0; i < scored.length; i++) {
    final tied = i > 0 && scored[i].score == scored[i - 1].score;
    ranked.add(
      ClubRankedMember(
        rank: tied ? ranked[i - 1].rank : i + 1,
        entry: scored[i].entry,
        score: scored[i].score,
      ),
    );
  }
  return ranked;
}

String clubRankingValueLabel(double score, ClubRankingSport sport) {
  return switch (sport) {
    ClubRankingSport.steps => '${stepThousands(score.round())} bước',
    ClubRankingSport.run || ClubRankingSport.bike => formatDistance(score),
  };
}

/// Câu dưới tên mình: cách người gần nhất có số cao hơn bao xa, hoặc khi đang
/// dẫn đầu thì hơn người kế bao nhiêu. Dẫn đầu một mình thì không có gì để nói.
String? clubRankingGapLabel(
  List<ClubRankedMember> ranked,
  int index,
  ClubRankingSport sport,
) {
  final me = ranked[index];
  for (var i = index - 1; i >= 0; i--) {
    if (ranked[i].score > me.score) {
      final gap = clubRankingValueLabel(ranked[i].score - me.score, sport);
      return 'Còn $gap nữa lên hạng ${ranked[i].rank}';
    }
  }
  for (var i = index + 1; i < ranked.length; i++) {
    if (ranked[i].score < me.score) {
      final gap = clubRankingValueLabel(me.score - ranked[i].score, sport);
      return 'Hơn hạng ${ranked[i].rank} tới $gap';
    }
  }
  return null;
}

const _vietnamOffset = Duration(hours: 7);

/// Kỳ tính theo giờ Việt Nam như backend (PeriodsAt trong
/// derived_data_service.go): tuần hết lúc 00:00 thứ Hai, tháng hết lúc 00:00
/// ngày 1, bất kể máy đang ở múi giờ nào.
DateTime clubRankingPeriodEnd(DateTime now, ClubRankingRange range) {
  final vn = now.toUtc().add(_vietnamOffset);
  final endOnVietnamClock = switch (range) {
    ClubRankingRange.currentWeek => DateTime.utc(
      vn.year,
      vn.month,
      vn.day + 8 - vn.weekday,
    ),
    ClubRankingRange.currentMonth => DateTime.utc(vn.year, vn.month + 1),
  };
  return endOnVietnamClock.subtract(_vietnamOffset);
}

String clubRankingTimeLeftLabel(DateTime now, ClubRankingRange range) {
  final left = clubRankingPeriodEnd(now, range).difference(now.toUtc());
  final days = left.inDays;
  final hours = left.inHours % 24;
  if (days > 0) {
    return hours > 0 ? 'Còn $days ngày $hours giờ' : 'Còn $days ngày';
  }
  if (hours > 0) return 'Còn $hours giờ';
  return 'Còn ${left.inMinutes < 1 ? 1 : left.inMinutes} phút';
}
