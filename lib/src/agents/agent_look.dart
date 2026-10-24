/// Kiểu bot: đồ robot đeo trên thẻ, kèm mẫu tính cách gợi ý lúc tạo bot.
/// Backend chỉ lưu [slug], không giữ danh sách, nên thêm kiểu chỉ sửa app.
enum AgentLook {
  funny(
    'funny',
    'Cây hài',
    'Hay đùa, cà khịa vừa phải.',
    'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".',
  ),
  chill(
    'chill',
    'Bạn chạy chill',
    'Nói nhẹ, hay khen, rủ chạy chậm.',
    'Nói nhẹ nhàng, hay khen mọi người, rủ cả nhóm chạy chậm cho vui.',
  ),
  coach(
    'coach',
    'Coach khó tính',
    'Nói thẳng, nhắc giáo án, ít đùa.',
    'Nói thẳng, ít đùa. Hay nhắc giáo án, giờ ngủ và chạy đúng pace.',
  ),
  custom('custom', 'Tự viết', 'Tả bằng lời của bạn.', '');

  const AgentLook(this.slug, this.title, this.summary, this.persona);

  final String slug;
  final String title;
  final String summary;

  /// Chữ đổ vào ô tính cách khi chọn kiểu; rỗng là người dùng tự viết.
  final String persona;

  /// Kiểu đã lưu; chưa lưu (bot tạo trước khi có kiểu, backend cũ) hay kiểu
  /// lạ do app mới hơn thêm thì đoán theo tính cách: trùng mẫu nào là kiểu
  /// đó, không thì là Tự viết.
  static AgentLook of(String? slug, String persona) {
    for (final look in values) {
      if (look.slug == slug) return look;
    }
    final text = persona.trim();
    for (final look in values) {
      if (look.persona.isNotEmpty && look.persona == text) return look;
    }
    return custom;
  }
}
