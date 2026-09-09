// Manual live demo, not an automated test. Makes real paid DeepSeek requests.
// Run from the project root: dart run tool/run_day8.dart
// Uses a temporary conversation; never changes the app's stored chat.
import 'dart:convert';
import 'dart:io';

import 'package:ai_advent_day_01/agent.dart';
import 'package:ai_advent_day_01/history_storage.dart';

Future<void> main() async {
  final env = <String, String>{};
  for (final line in File('.env').readAsLinesSync()) {
    final split = line.indexOf('=');
    if (split < 1 || line.trimLeft().startsWith('#')) continue;
    var value = line.substring(split + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    env[line.substring(0, split).trim()] = value;
  }
  final deepSeekKey = env['DEEPSEEK_API_KEY'] ?? '';

  final directory = await Directory.systemTemp.createTemp('day8-demo-');
  final storage = HistoryStorage(
    () async => File('${directory.path}/conversation.json'),
  );
  var agent = Agent(const AgentConfig(), apiKey: deepSeekKey, storage: storage);
  Future<void> send(String scenario, String text) async {
    final result = await agent.send(text);
    stdout.writeln(
      jsonEncode({
        'scenario': scenario,
        'model': agent.config.model.id,
        'current_message_estimate': agent.lastCall?.estimatedMessageTokens,
        'context_api': result.input,
        'response_api': result.output,
        'total_api': result.total,
        'elapsed_ms': result.elapsed?.inMilliseconds,
        'error': result.error,
        'content': result.content,
        'turns': agent.turns.length,
      }),
    );
  }

  try {
    await send(
      'short_1',
      'Remember: the code word is cobalt815. Reply briefly.',
    );
    await send('short_2', 'What is the code word?');
    await agent.prepareDemoHistory(overflow: false);
    await send('long_1', 'What is the code word?');
    await agent.prepareDemoHistory(overflow: false);
    await send('long_2', 'What is the code word?');
    agent = Agent(const AgentConfig(), apiKey: deepSeekKey, storage: storage);
    await agent.initialize();
    await send('restored_long', 'What is the code word?');
    await agent.prepareDemoHistory(overflow: true);
    await send('overflow', 'Reply OK.');
    stdout.writeln(
      jsonEncode({
        'clear_error': await agent.clearConversation(),
        'turns_after_clear': agent.turns.length,
      }),
    );
    await send('after_clear', 'Reply OK.');
  } finally {
    await directory.delete(recursive: true);
  }
}
