/// Trang admin: uid theo từng quyền và chat Telegram mà api đang dùng. Token
/// không có ở đây, backend không trả ra.
class AdminSettings {
  const AdminSettings({
    required this.roles,
    required this.chatId,
    required this.botUsername,
  });

  factory AdminSettings.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'] is Map ? json['roles'] as Map : const {};
    final telegram = json['telegram'] is Map
        ? json['telegram'] as Map
        : const {};
    return AdminSettings(
      roles: {
        for (final entry in roles.entries)
          '${entry.key}': [
            if (entry.value is List)
              for (final uid in entry.value as List) '$uid',
          ],
      },
      chatId: '${telegram['chatId'] ?? ''}',
      botUsername: '${telegram['botUsername'] ?? ''}',
    );
  }

  final Map<String, List<String>> roles;
  final String chatId;
  final String botUsername;

  List<String> uidsOf(String role) => roles[role] ?? const [];
}
