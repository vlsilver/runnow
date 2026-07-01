import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';

class RunContractAnalytics {
  RunContractAnalytics(this._analytics);

  final FirebaseAnalytics _analytics;

  Future<void> log(
    String name, {
    RunContract? contract,
    RunContractDraft? draft,
    Map<String, Object>? extra,
  }) {
    final parameters = <String, Object>{
      if (contract != null) ...{
        'metric': contract.metric.value,
        'period_type': contract.periodType.value,
        'visibility': contract.visibility.value,
        'ui_state': contractUiState(contract, DateTime.now()).name,
        'progress_bucket': _progressBucket(contract.progressPercent),
        'target_bucket': _targetBucket(contract.metric, contract.targetValue),
        'source_policy': 'strava_only',
      },
      if (draft != null) ...{
        'template_id': draft.template.value,
        'metric': draft.metric.value,
        'period_type': draft.period.value,
        'visibility': draft.visibility.value,
        'target_bucket': _targetBucket(draft.metric, draft.targetValue),
        'source_policy': 'strava_only',
      },
      ...?extra,
    };
    return _analytics.logEvent(name: name, parameters: parameters);
  }
}

String _progressBucket(double percent) {
  if (percent >= 100) return '100_plus';
  if (percent >= 70) return '70_99';
  if (percent >= 20) return '20_69';
  return '0_19';
}

String _targetBucket(RunContractMetric metric, double value) {
  if (metric != RunContractMetric.distance) {
    return value <= 3
        ? 'small'
        : value <= 7
        ? 'medium'
        : 'large';
  }
  return value <= 3
      ? '0_3k'
      : value <= 10
      ? '3_10k'
      : '10k_plus';
}
