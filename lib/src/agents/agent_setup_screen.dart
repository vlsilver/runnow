import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/agents/agent_bot_card.dart';
import 'package:myrun/src/agents/agent_consent_screen.dart';
import 'package:myrun/src/agents/agent_look.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Câu gợi ý thêm nhanh vào tính cách: (chữ trên chip, câu thêm vào, chữ
/// nhận ra câu đã có). Chip đã có thì hiện dấu tích, bỏ đi bằng cách sửa ô.
const _voiceChips = [
  ('xưng tui', 'Xưng "tui".', 'xưng "tui"'),
  ('nói ngắn', 'Nói ngắn.', 'nói ngắn'),
  ('hay khen', 'Hay khen mọi người.', 'khen'),
  ('mê trail', 'Mê chạy trail.', 'trail'),
  ('nhắc ngủ sớm', 'Hay nhắc ngủ sớm.', 'ngủ sớm'),
  ('dùng emoji', 'Hay dùng emoji.', 'emoji'),
];

const _personaMax = 1500;

/// Tạo bot, hoặc sửa tên, kiểu và tính cách khi bot đã có. Thẻ bot nằm trên
/// đầu trang và đổi theo từng chữ người dùng gõ.
class AgentSetupScreen extends ConsumerStatefulWidget {
  const AgentSetupScreen({super.key});

  @override
  ConsumerState<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends ConsumerState<AgentSetupScreen> {
  final _name = TextEditingController();
  late final _persona = _QuoteHighlightController();
  final _personaFocus = FocusNode();

  /// Kiểu đang chọn; null khi tạo bot mà chưa chọn kiểu nào.
  AgentLook? _look;

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
    if (profile.created) _look = AgentLook.of(profile.look, profile.persona);
  }

  /// Chọn kiểu thì đổ mẫu tính cách của kiểu đó, trừ khi ô đang là chữ người
  /// dùng tự viết: đổi kiểu chỉ để đổi đồ trên thẻ thì không mất chữ.
  void _pickLook(AgentLook look) {
    final text = _persona.text.trim();
    final ownText =
        text.isNotEmpty && AgentLook.values.every((l) => l.persona != text);
    setState(() => _look = look);
    if (look == AgentLook.custom) {
      if (!ownText) _persona.clear();
      _personaFocus.requestFocus();
      return;
    }
    if (!ownText) _persona.text = look.persona;
  }

  void _addVoice(String sentence) {
    final text = _persona.text.trimRight();
    final joined = text.isEmpty
        ? sentence
        : RegExp(r'[.!?…]$').hasMatch(text)
        ? '$text $sentence'
        : '$text. $sentence';
    if (joined.length > _personaMax) return;
    _persona.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
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
      // Backend cũ từ chối field lạ: chỉ gửi kiểu khi GET me đã có key look.
      final look = me?.agent?.look == null ? null : _look?.slug;
      await withAgentConsent(
        context,
        ref,
        () => ref
            .read(runNowApiClientProvider)
            .saveAgentProfile(
              name: name,
              persona: _persona.text.trim(),
              look: look,
            ),
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

  AgentBotCardData _cardData(AgentMe? me, bool created) {
    final persona = _persona.text.trim();
    final profile = AgentProfile(
      name: _name.text.trim(),
      persona: persona,
      created: created,
      createdAt: me?.agent?.createdAt,
      look: (_look ?? AgentLook.of(null, persona)).slug,
    );
    if (me != null) return AgentBotCardData.fromMe(me, profile);
    return AgentBotCardData(
      name: profile.name,
      persona: persona,
      look: AgentLook.of(profile.look, persona),
      tier: AgentCardTier.common,
      memoryCount: 0,
      memoryLimit: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final me = ref.watch(agentMeProvider).value;
    final created = me?.agent?.created ?? false;
    final persona = _persona.text.toLowerCase();
    final named = _name.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(created ? 'Sửa bot' : 'Tạo bot')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                // Không có lề ngang chung: hàng ô kiểu bot cuộn tới mép màn,
                // các khối còn lại tự lùi vào 16.
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                children: [
                  _Inset(
                    children: [
                      _CardPreview(data: _cardData(me, created)),
                      const SizedBox(height: 10),
                      Text(
                        'Gõ tới đâu, thẻ đổi tới đó · chạm thẻ để lật',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (!created) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Rèn thẻ bot của bạn',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Bot nói chuyện thay bạn trong phòng bot và nhớ những gì '
                          'bạn kể. Chạy càng nhiều, thẻ càng lên bậc.',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const _FieldLabel('Tên bot'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        maxLength: 40,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Vd: Bò Sữa',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Kiểu bot'),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final look in AgentLook.values) ...[
                            if (look != AgentLook.values.first)
                              const SizedBox(width: 10),
                            _LookTile(
                              look: look,
                              selected: _look == look,
                              onTap: () => _pickLook(look),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _Inset(
                    children: [
                      const SizedBox(height: 18),
                      const _FieldLabel('Bot nói thế nào'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _persona,
                        focusNode: _personaFocus,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: _personaMax,
                        decoration: const InputDecoration(
                          hintText:
                              'Vd: Nói ngắn, hay đùa, xưng "tui", mê chạy trail.',
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _QuoteHighlightController.highlight,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Câu đầu lên thẻ làm lời thoại',
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, sentence, match) in _voiceChips)
                            _VoiceChip(
                              label: label,
                              on: persona.contains(match),
                              onTap: () => _addVoice(sentence),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _ForgeButton(
                label: !named
                    ? 'Đặt tên để rèn thẻ'
                    : created
                    ? 'Lưu thẻ'
                    : 'Rèn thẻ bot',
                onPressed: _busy || !named ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ô tính cách tô sáng câu đầu, đúng câu thẻ lấy làm lời thoại. Đang gõ dở
/// (bộ gõ tiếng Việt giữ vùng composing) thì vẽ như ô thường để giữ gạch chân.
class _QuoteHighlightController extends TextEditingController {
  static const highlight = RunNowBotCardTokens.quoteHighlight;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final start = text.length - text.trimLeft().length;
    if (text.trim().isEmpty || (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final end = start + agentQuoteEnd(text.substring(start));
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, start)),
        TextSpan(
          text: text.substring(start, end),
          style: const TextStyle(backgroundColor: highlight),
        ),
        TextSpan(text: text.substring(end)),
      ],
    );
  }
}

/// Thẻ bot thật trên đầu trang, quầng sáng màu hành phía sau.
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.data});

  final AgentBotCardData data;

  @override
  Widget build(BuildContext context) {
    final accent = context.runNowPalette.accent;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.62,
                colors: [
                  accent.withValues(alpha: 0.26),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AgentBotCardView(data: data, width: 220),
        ),
      ],
    );
  }
}

/// Một khối nội dung lùi vào 16 hai bên.
class _Inset extends StatelessWidget {
  const _Inset({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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

/// Ô chọn kiểu bot: robot đeo đồ của kiểu, tên và một dòng tả. Ô đang chọn
/// nhô lên, viền màu hành và có dấu tích.
class _LookTile extends StatelessWidget {
  const _LookTile({
    required this.look,
    required this.selected,
    required this.onTap,
  });

  final AgentLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return AnimatedSlide(
      offset: Offset(0, selected ? -0.04 : 0),
      duration: const Duration(milliseconds: 180),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? palette.tint : palette.glassStart,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected
                ? BorderSide(color: palette.accent, width: 2)
                : BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 108,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                    child: Column(
                      children: [
                        AgentMascot(look: look, width: 62),
                        const SizedBox(height: 4),
                        Text(
                          look.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          look.summary,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: palette.glassStart,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Semantics(
      button: !on,
      selected: on,
      child: Material(
        color: on ? palette.tint : palette.glassStart,
        shape: StadiumBorder(
          side: BorderSide(color: on ? palette.accent : palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: on ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? Icons.check_rounded : Icons.add_rounded,
                  size: 15,
                  color: on ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: on ? palette.accent : null,
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

/// Nút lưu to, màu hành chuyển sắc và có ánh sao; tắt thì phẳng xám.
class _ForgeButton extends StatelessWidget {
  const _ForgeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final on = onPressed != null;
    return Semantics(
      button: true,
      enabled: on,
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        color: on ? null : palette.glassStart,
        child: Ink(
          decoration: on
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(palette.accent, Colors.white, 0.15)!,
                      palette.accent,
                      palette.accentDeep,
                    ],
                  ),
                )
              : null,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (on) ...[
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: on ? Colors.white : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
