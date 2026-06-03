import 'package:intl/intl.dart';

String formatDistance(double meters) =>
    '${(meters / 1000).toStringAsFixed(2)} km';

String formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final remainingSeconds = duration.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  return hours > 0
      ? '$hours:$minutes:$remainingSeconds'
      : '$minutes:$remainingSeconds';
}

String formatPace(double? secondsPerKm) {
  if (secondsPerKm == null || !secondsPerKm.isFinite) return '--';
  final rounded = secondsPerKm.round();
  return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')} /km';
}

String formatDate(DateTime date) =>
    DateFormat('dd/MM/yyyy, HH:mm').format(date);
