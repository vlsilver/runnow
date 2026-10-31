import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:share_plus/share_plus.dart';

/// Link mời mở trang phòng trên web 3i (hosting rewrite về app web), nên ai
/// có link cũng vào được kể cả chưa cài app.
Uri runRoomInviteLink(String roomId) =>
    Uri.parse('${AppConfig.webBaseUrl}/rooms/$roomId');

Future<void> shareRunRoom(BuildContext context, RunRoom room) {
  final box = context.findRenderObject() as RenderBox?;
  final lines = [
    'Vào phòng chạy "${room.title}" của ${room.hostName} trên 3i:',
    runRoomInviteLink(room.id).toString(),
    if (room.privacy == RunRoomPrivacy.password)
      'Phòng có mật khẩu, hỏi chủ phòng nhé.',
  ];
  return SharePlus.instance.share(
    ShareParams(
      text: lines.join('\n'),
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Vào phòng: hỏi mật khẩu nếu cần, báo kết quả bằng snackbar. Trả true khi
/// backend nhận (đã vào hoặc đã xin vào).
Future<bool> joinRunRoom(
  BuildContext context,
  WidgetRef ref,
  RunRoom room,
) async {
  String? password;
  if (room.privacy == RunRoomPrivacy.password) {
    password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null || !context.mounted) return false;
  }
  try {
    final state = await ref
        .read(runNowApiClientProvider)
        .joinRunRoom(room.id, password: password);
    if (context.mounted && state == 'requested') {
      _snack(context, 'Đã xin vào phòng, chờ chủ phòng duyệt.');
    }
    return true;
  } catch (error) {
    if (context.mounted) _snack(context, runRoomErrorText(error));
    return false;
  }
}

/// Chạy một thao tác phòng (duyệt, mời ra, rời, kết thúc), lỗi thì báo.
Future<bool> runRoomAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) _snack(context, runRoomErrorText(error));
    return false;
  }
}

/// Backend đã viết sẵn câu cho người dùng ở `message`; khoá vì sai mật khẩu
/// thì nói thêm còn bao lâu.
String runRoomErrorText(Object error) {
  if (error is! RunNowApiException) return 'Lỗi mạng, thử lại sau nhé.';
  if (error.code == 'room_locked') {
    final seconds = (error.body['retryAfterSeconds'] as num?)?.toInt() ?? 0;
    final minutes = (seconds / 60).ceil();
    return minutes >= 60
        ? 'Sai mật khẩu nhiều lần. Thử lại sau ${(minutes / 60).ceil()} giờ.'
        : 'Sai mật khẩu nhiều lần. Thử lại sau $minutes phút.';
  }
  return error.message;
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mật khẩu phòng'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        maxLength: 24,
        decoration: const InputDecoration(hintText: 'Chủ phòng đã gửi bạn'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Vào phòng')),
      ],
    );
  }
}
