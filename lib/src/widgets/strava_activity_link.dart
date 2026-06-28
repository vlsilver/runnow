import 'package:flutter/material.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

class StravaActivityLink extends StatelessWidget {
  const StravaActivityLink({required this.activityId, super.key});
  final String activityId;

  @override
  Widget build(BuildContext context) {
    if (!RegExp(r'^\d+$').hasMatch(activityId)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () => _open(context),
      child: const Text(
        'View on Strava',
        style: TextStyle(
          color: RunNowBrandColors.strava,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final url = Uri.https('www.strava.com', '/activities/$activityId');
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Không thể mở Strava.')));
  }
}
