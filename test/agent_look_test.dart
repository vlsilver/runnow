import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/agents/agent_look.dart';

void main() {
  test('a saved look wins over the persona text', () {
    expect(
      AgentLook.of('coach', 'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".'),
      AgentLook.coach,
    );
  });

  test('no saved look: a preset persona gives its look, else custom', () {
    // Bot tạo trước khi có kiểu, hoặc backend cũ không trả look.
    expect(
      AgentLook.of('', 'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".'),
      AgentLook.funny,
    );
    expect(AgentLook.of(null, 'Mê trail.'), AgentLook.custom);
    expect(AgentLook.of(null, ''), AgentLook.custom);
  });

  test('a look a newer app added falls back like an unsaved one', () {
    expect(AgentLook.of('pirate', 'Mê trail.'), AgentLook.custom);
  });
}
