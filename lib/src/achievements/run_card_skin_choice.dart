import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/theme.dart';

/// Bộ màu thẻ máy này chọn riêng: nền sáng hay tối và hành.
typedef RunCardSkinChoice = (RunNowAppearance, RunNowElement);

/// Bộ màu thẻ đang dùng: [choice] nếu có, không thì theo theme app.
RunCardSkin resolveRunCardSkin({
  required RunNowAppearance appAppearance,
  required RunNowElement appElement,
  required RunCardSkinChoice? choice,
}) =>
    RunCardSkin.forTheme(choice?.$1 ?? appAppearance, choice?.$2 ?? appElement);

/// Giữ lựa chọn bộ màu thẻ của máy này. Chưa chọn (null) thì thẻ theo theme
/// app. Lựa chọn cũng được gửi lên backend theo từng thẻ, để người khác xem
/// thẻ của mình thấy đúng bộ màu mình chọn.
class RunCardSkinController extends ChangeNotifier {
  RunCardSkinController({
    FlutterSecureStorage? storage,
    bool loadFromStorage = true,
    this.onChoice,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    if (loadFromStorage) _load();
  }

  static const _key = 'runnow_card_skin';

  final FlutterSecureStorage _storage;

  /// Gọi khi người dùng đổi bộ màu, để gửi lên backend cho mọi thẻ của mình.
  final void Function(RunCardSkinChoice? choice)? onChoice;

  RunCardSkinChoice? _choice;

  /// Người dùng đã chọn trong phiên này thì giá trị đọc muộn từ máy không
  /// được đè lên.
  bool _chosen = false;

  RunCardSkinChoice? get choice => _choice;

  Future<void> setChoice(RunCardSkinChoice? choice) async {
    _chosen = true;
    if (_choice == choice) return;
    _choice = choice;
    notifyListeners();
    onChoice?.call(choice);
    if (choice == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: runCardSkinChoiceId(choice));
    }
  }

  Future<void> _load() async {
    final loaded = parseRunCardSkinChoice(await _storage.read(key: _key));
    if (_chosen || loaded == _choice) return;
    _choice = loaded;
    notifyListeners();
  }
}

/// Dạng lưu của [choice], cả trong máy lẫn trên backend: "dark.fire".
String runCardSkinChoiceId(RunCardSkinChoice choice) =>
    '${choice.$1.name}.${choice.$2.name}';

/// Đọc giá trị đã lưu dạng "dark.fire"; sai dạng thì coi như chưa chọn.
RunCardSkinChoice? parseRunCardSkinChoice(String? raw) {
  final parts = raw?.split('.');
  if (parts == null || parts.length != 2) return null;
  final appearance = RunNowAppearance.values.asNameMap()[parts[0]];
  final element = RunNowElement.values.asNameMap()[parts[1]];
  if (appearance == null || element == null) return null;
  return (appearance, element);
}
