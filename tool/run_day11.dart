// Manual live demonstration, not a test suite. Uses only temporary JSON files.
// dart run tool/run_day11.dart — makes real DeepSeek API requests.
import 'dart:convert';
import 'dart:io';

import 'package:ai_advent_day_01/agent.dart';
import 'package:ai_advent_day_01/json_file_storage.dart';

Future<void> main() async {
  final env = <String, String>{};
  for (final line in File('.env').readAsLinesSync()) {
    final split = line.indexOf('=');
    if (split < 1 || line.trimLeft().startsWith('#')) continue;
    env[line.substring(0, split).trim()] = line
        .substring(split + 1)
        .trim()
        .replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  }
  final key = env['DEEPSEEK_API_KEY'] ?? '';
  if (key.isEmpty) throw StateError('DEEPSEEK_API_KEY missing');

  final directory = await Directory.systemTemp.createTemp('day11-');
  final workingFile = File('${directory.path}/working.json');
  final longFile = File('${directory.path}/long-term.json');
  Agent createAgent() => Agent(
    const AgentConfig(
      strategy: SlidingWindow(),
      temperature: 0,
      systemPrompt:
          'Ты полезный помощник. Отвечай кратко, по-русски. '
          'Используй только переданные сведения о пользователе и задаче. '
          'Не угадывай отсутствующие факты: пиши «неизвестно».',
    ),
    apiKey: key,
    memory: AgentMemory(
      working: WorkingMemory(JsonFileStorage(() async => workingFile)),
      longTerm: LongTermMemory(JsonFileStorage(() async => longFile)),
    ),
  );
  var agent = createAgent();
  final report = <Map<String, dynamic>>[];
  Map<String, dynamic> snapshot() => {
    'short': agent.memory!.shortTerm.messages,
    'working': agent.memory!.working.values,
    'long_term': agent.memory!.longTerm.values,
    'warning': agent.memory!.warning,
  };
  void record(String stage, {ApiResult? result, String? error}) {
    final row = <String, dynamic>{
      'stage': stage,
      ...snapshot(),
      'operation_error': ?error,
      if (result != null) ...{
        'answer': result.content,
        'error': result.error,
        'model': result.actualModel,
        'input': result.input,
        'output': result.output,
        'total': result.total,
        'sent_messages': agent.lastSentMessages,
        'summary_calls': agent.summaryUsage.calls,
        'extraction_calls': agent.extractionUsage.calls,
      },
    };
    report.add(row);
    stdout.writeln(jsonEncode(Map.of(row)..remove('sent_messages')));
  }

  const question =
      'Как зовут тестового пользователя, какой backend выбран '
      'для текущей задачи и какой framework я предпочитаю для мобильных проектов? '
      'Ответь тремя короткими пунктами; если сведений нет — «неизвестно».';
  Future<void> ask(String stage) async =>
      record(stage, result: await agent.send(question));
  Future<void> save(MemoryLayer layer, String field, String value) async {
    final error = await agent.saveMemory(layer, key: field, value: value);
    if (error != null) record('save_error', error: error);
  }

  try {
    await agent.initialize();
    record('first_launch');
    await save(
      MemoryLayer.shortTerm,
      '',
      'Для этого примера тестового пользователя зовут Bob.',
    );
    await save(MemoryLayer.working, 'backend', 'Firebase');
    await save(MemoryLayer.longTerm, 'preferred_framework', 'Flutter');
    record('three_layers_before_api');
    await ask('all_three');
    await agent.clearMemory(MemoryLayer.shortTerm);
    record('session_cleared');
    await ask('new_session');
    await agent.resetTask();
    record('new_task');
    await ask('after_task_reset');
    agent = createAgent();
    await agent.initialize();
    record('restored_agent');
    await ask('restored_request');

    // Demonstrate independent per-layer operations, including echoed chat data.
    await save(MemoryLayer.working, 'backend', 'Firebase');
    record('before_working_only_clear');
    await agent.clearMemory(MemoryLayer.working);
    record('working_only_cleared');
    await save(MemoryLayer.working, 'backend', 'Firebase');
    await agent.clearMemory(MemoryLayer.longTerm);
    record('long_only_cleared');
    await save(MemoryLayer.longTerm, 'preferred_framework', 'Flutter');

    await agent.clearMemory(MemoryLayer.shortTerm);
    await save(
      MemoryLayer.shortTerm,
      '',
      'Для этого примера тестового пользователя зовут Bob.',
    );
    for (var i = 0; i < 6; i++) {
      await save(
        MemoryLayer.shortTerm,
        '',
        'Нейтральная заметка номер $i: продолжаем обсуждение.',
      );
    }
    record('short_window_evicted_name');
    await ask('working_and_long_outlive_window');

    // One malformed file must not poison the other layer.
    await workingFile.writeAsString('{broken');
    agent = createAgent();
    await agent.initialize();
    record('corrupt_working_long_intact');
    await agent.resetTask();
    await longFile.writeAsString('{broken');
    await save(MemoryLayer.working, 'backend', 'Firebase');
    agent = createAgent();
    await agent.initialize();
    record('corrupt_long_working_intact');
  } finally {
    await File('docs/day11-results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await directory.delete(recursive: true);
  }
}
