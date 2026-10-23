import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/agents/agent_consent_screen.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Một mẫu tính cách để người mới khỏi phải viết từ đầu. [persona] là chữ đổ
/// vào ô tính cách, người dùng sửa tiếp được.
class _PersonaPreset {
  const _PersonaPreset(this.title, this.summary, this.persona);

  final String title;
  final String summary;
  final String persona;
}

const _presets = [
  _PersonaPreset(
    'Cây hài',
    'Hay đùa, cà khịa vừa phải.',
    'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".',
  ),
  _PersonaPreset(
    'Bạn chạy chill',
    'Nói nhẹ, hay khen, rủ chạy chậm.',
    'Nói nhẹ nhàng, hay khen mọi người, rủ cả nhóm chạy chậm cho vui.',
  ),
  _PersonaPreset(
    'Coach khó tính',
    'Nói thẳng, nhắc giáo án, ít đùa.',
    'Nói thẳng, ít đùa. Hay nhắc giáo án, giờ ngủ và chạy đúng pace.',
  ),
];

/// Tạo bot, hoặc sửa tên và tính cách khi bot đã có.
class AgentSetupScreen extends ConsumerStatefulWidget {
  const AgentSetupScreen({super.key});

  @override
  ConsumerState<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends ConsumerState<AgentSetupScreen> {
  final _name = TextEditingController();
  final _persona = TextEditingController();
  final _personaFocus = FocusNode();

  /// Đã đổ hồ sơ vào ô nhập chưa; hồ sơ đọc lại thì không ghi đè chữ đang gõ.
  bool _filled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Đổ hồ sơ trước khi gắn listener, nên lần đổ đầu không gọi setState.
    ref.listenManual(agentMeProvider, (_, next) {
      final agent = next.value?.agent;
      if (agent != null) _fill(agent);
    }, fireImmediately: true);
    _name.addListener(_onChanged);
    _persona.addListener(_onChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _persona.dispose();
    _personaFocus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _fill(AgentProfile profile) {
    if (_filled) return;
    _filled = true;
    _name.text = profile.name;
    _persona.text = profile.persona;
  }

  void _pickPreset(_PersonaPreset? preset) {
    if (preset == null) {
      _persona.clear();
      _personaFocus.requestFocus();
      return;
    }
    _persona.text = preset.persona;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final me = ref.read(agentMeProvider).value;
      final name = _name.text.trim();
      // Backend đòi đồng ý AI trước khi lưu bot: hỏi luôn ở đây thay vì chờ
      // lỗi. Hồ sơ đọc từ trước mà backend vừa đòi thì withAgentConsent hỏi.
      if (me != null && me.consentRequired) {
        final created = me.agent?.created ?? false;
        final agreed = await openAgentConsent(
          context,
          version: me.consentVersion,
          botName: name,
          title: created ? 'Sửa bot' : 'Tạo bot',
          action: created ? 'Đồng ý và lưu' : 'Đồng ý và tạo bot',
        );
        if (!agreed || !mounted) return;
      }
      await withAgentConsent(
        context,
        ref,
        () => ref
            .read(runNowApiClientProvider)
            .saveAgentProfile(name: name, persona: _persona.text.trim()),
      );
      ref.invalidate(agentMeProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RunNowApiException
                  ? error.message
                  : 'Không lưu được, thử lại sau.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final created = ref.watch(agentMeProvider).value?.agent?.created ?? false;
    final persona = _persona.text.trim();
    return Scaffold(
      appBar: AppBar(title: Text(created ? 'Sửa bot' : 'Tạo bot')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  if (!created) ...[
                    const Text(
                      'Bot của bạn là ai?',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bot nói chuyện thay bạn trong phòng bot, và nhớ những '
                      'gì bạn kể.',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  const _FieldLabel('Tên bot'),
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Vd: Bò Sữa'),
                  ),
                  const SizedBox(height: 8),
                  const _FieldLabel('Tính cách'),
                  const SizedBox(height: 8),
                  _PresetGrid(
                    children: [
                      for (final p in _presets)
                        _PresetCard(
                          title: p.title,
                          summary: p.summary,
                          selected: persona == p.persona,
                          onTap: () => _pickPreset(p),
                        ),
                      _PresetCard(
                        title: 'Tự viết',
                        summary: 'Tả bằng lời của bạn.',
                        selected:
                            persona.isNotEmpty &&
                            _presets.every((p) => p.persona != persona),
                        dashed: true,
                        onTap: () => _pickPreset(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _FieldLabel('Sửa lại cho giống bạn'),
                  TextField(
                    controller: _persona,
                    focusNode: _personaFocus,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 1500,
                    decoration: const InputDecoration(
                      hintText:
                          'Vd: Nói ngắn, hay đùa, xưng "tui", mê chạy trail.',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                onPressed: _busy || _name.text.trim().isEmpty ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(created ? 'Lưu' : 'Tạo bot'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.runNowPalette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// Lưới hai cột mà mỗi hàng cao theo thẻ cao nhất, để chữ to hay màn hẹp
/// không làm tràn thẻ như lưới tỉ lệ cố định.
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.title,
    required this.summary,
    required this.selected,
    required this.onTap,
    this.dashed = false,
  });

  final String title;
  final String summary;
  final bool selected;
  final bool dashed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    // Flutter không có viền nét đứt sẵn; ô "Tự viết" dùng nền trong và viền
    // mảnh để khác ba mẫu kia.
    final side = selected
        ? BorderSide(color: palette.accent, width: 2)
        : dashed
        ? BorderSide(color: palette.border, width: 1.5)
        : const BorderSide(color: Colors.transparent, width: 2);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? palette.tint
            : dashed
            ? Colors.transparent
            : palette.glassStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
