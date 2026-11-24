import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/share.dart';
import 'package:share_plus/share_plus.dart';

/// Link mở màn kèo trên web 3i.
Uri contractLink(String contractId) => Uri.parse(
  '${AppConfig.webBaseUrl}/contracts/${Uri.encodeComponent(contractId)}',
);

/// Câu gửi kèm ảnh kèo: tên kèo, kèm tiến độ của người khoe nếu họ có trong
/// kèo. Kèo riêng tư thì không kèm link, vì người nhận mở ra cũng không xem được.
String contractShareCaption(RunContract contract, String? uid) {
  final mine = contract.participantFor(uid);
  final line = mine == null
      ? contract.title
      : '${contract.title}: ${runContractValueOverTarget(contract.metric, mine.progressValue, contract.targetValue)}';
  return contract.visibility == RunContractVisibility.private
      ? line
      : '$line\n${contractLink(contract.id)}';
}

/// Mở sheet xem trước ảnh kèo rồi mới khoe: ảnh chụp đúng cái đang thấy, và
/// avatar có thời gian tải xong. Web không gửi được file nên chỉ gửi chữ.
Future<void> showContractShare(
  BuildContext context, {
  required RunContract contract,
  required String? currentUid,
  required String ownerName,
  required String? ownerAvatarUrl,
  required List<String?> participantAvatarUrls,
}) async {
  final caption = contractShareCaption(contract, currentUid);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-keo.png',
    label: 'Khoe kèo',
    card: RunContractPoster(
      contract: contract,
      currentUid: currentUid,
      ownerName: ownerName,
      ownerAvatarUrl: ownerAvatarUrl,
      participantAvatarUrls: participantAvatarUrls,
    ),
  );
}
