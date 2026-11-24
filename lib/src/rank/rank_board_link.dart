import 'package:myrun/src/config.dart';

/// Khoá bảng đã chốt, như backend viết ra: week_2026-11-23_run.
final _boardId = RegExp(r'^(week|month)_\d{4}-\d{2}-\d{2}_(run|steps|bike)$');

/// Màn trong app cho link `/bxh/{boardId}`: tab Club mở đúng bảng kỳ trước;
/// null nếu không phải link bảng.
String? rankBoardLinkLocation(Uri link) {
  final web = Uri.parse(AppConfig.webBaseUrl);
  if (link.scheme != web.scheme || link.host != web.host) return null;
  final path = [...link.pathSegments];
  if (path.isNotEmpty && path.last.isEmpty) path.removeLast();
  if (path.length != 2 || path.first != 'bxh') return null;
  return rankBoardLocation(path.last);
}

/// Đường dẫn trong app tới bảng boardId; null nếu khoá sai dạng.
String? rankBoardLocation(String boardId) => _boardId.hasMatch(boardId)
    ? Uri(path: '/club', queryParameters: {'board': boardId}).toString()
    : null;
