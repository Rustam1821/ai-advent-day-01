// Manual real-API experiment, not a test suite. App storage is never touched.
import 'dart:convert';
import 'dart:io';

import 'package:ai_advent_day_01/agent.dart';
import 'package:ai_advent_day_01/history_storage.dart';

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
  final directory = await Directory.systemTemp.createTemp('day10-');
  final report = <Map<String, dynamic>>[];
  const prompts = [
    'Делаем приложение бронирования переговорных Orion на Flutter для iOS и Android. '
        'Бюджет 5000 EUR, срок 30 сентября. Обязательны offline mode, push-уведомления '
        'и вход по email и паролю. Запомни требования, ответь одним предложением.',
    'Я передумал: бюджет увеличиваем до 7000 EUR. Остальное без изменений. Подтверди кратко.',
    'Отменяю требование push-уведомлений: удали его из требований, ничего взамен. Подтверди кратко.',
    'Каталог должен фильтровать комнаты по вместимости. Это принятое требование. Ответь кратко.',
    'Как лучше подписать кнопку отправки формы? Предложи один вариант без повторения требований проекта.',
    'Предпочитаю короткие и понятные тексты ошибок, без технических кодов. Запомни.',
    'Приведи пример одного понятного текста ошибки для пустого поля. Только пример.',
    'Спасибо! Ответь «Пожалуйста».',
    'Предложи две нейтральные подписи для кнопки закрытия подсказки. Это варианты для обсуждения, не решения.',
    'Объясни разницу между placeholder и label в одном предложении. Не перечисляй требования проекта.',
    'Что означает disabled у кнопки? Одно предложение, без повторения требований проекта.',
    'Составь итоговое ТЗ с учётом всех моих действующих требований и ограничений. '
        'Укажи известные название, назначение, технологии, платформы, бюджет, срок, '
        'offline и авторизацию. Неизвестное пометь «неизвестно», не выдумывай. До 180 слов.',
  ];
  AgentConfig config(ContextStrategy strategy) => AgentConfig(
    strategy: strategy,
    temperature: 0,
    maxTokens: 600,
    systemPrompt:
        'Ты помощник по требованиям к приложению. Отвечай кратко по-русски. '
        'Учитывай только известные требования, не выдумывай отсутствующие факты.',
  );
  Future<void> send(Agent agent, String text, String stage) async {
    final result = await agent.send(text);
    final sent = agent.lastSentMessages;
    final strategy = agent.config.strategy!;
    final original = agent.visibleMessages;
    if (result.error != null) throw StateError(result.error!);
    final withoutReply = original.sublist(0, original.length - 1);
    final expected = strategy is Branching
        ? withoutReply
        : recent(withoutReply, 6);
    final actual = sent.where((m) => m['role'] != 'system').toList();
    if (jsonEncode(expected) != jsonEncode(actual)) {
      throw StateError('Context history mismatch');
    }
    if (agent.summary.isNotEmpty ||
        agent.summaryUsage.calls != 0 ||
        jsonEncode(sent).contains('DAY9_SENTINEL')) {
      throw StateError('Summary leakage');
    }
    if (strategy is SlidingWindow &&
        sent.where((m) => m['role'] == 'system').length != 1) {
      throw StateError('Extra memory in sliding');
    }
    final row = <String, dynamic>{
      'strategy': strategy.id,
      'stage': stage,
      'branch': agent.hasCheckpoint ? agent.activeBranch : null,
      'user': text,
      'answer': result.content,
      'finish': result.finishReason,
      'input': result.input,
      'output': result.output,
      'total': result.total,
      'chat_usage': agent.chatUsage.toJson(),
      'extraction_usage': agent.extractionUsage.toJson(),
      'cumulative': agent.chatUsage.total + agent.extractionUsage.total,
      'facts': agent.facts,
      'sent_messages': sent,
      if (strategy is StickyFacts)
        'extraction_messages': agent.lastExtractionMessages,
    };
    report.add(row);
    stdout.writeln(
      jsonEncode(
        Map.of(row)
          ..remove('sent_messages')
          ..remove('extraction_messages')
          ..remove('user'),
      ),
    );
  }

  try {
    for (final strategy in const <ContextStrategy>[
      SlidingWindow(),
      StickyFacts(),
      Branching(),
    ]) {
      final storage = HistoryStorage(
        () async => File('${directory.path}/${strategy.id}.json'),
      );
      // Verify stale Day 9 memory cannot enter any Day 10 strategy.
      await storage.saveState({
        'messages': [],
        'summary': 'DAY9_SENTINEL',
        'compressedCount': 0,
        'compressionEnabled': true,
      });
      var agent = Agent(config(strategy), apiKey: key, storage: storage);
      if (strategy is! Branching) {
        for (var i = 0; i < prompts.length; i++) {
          await send(agent, prompts[i], 'turn_${i + 1}');
          if (i == 6) {
            final old = jsonEncode(agent.facts);
            final oldUsage =
                agent.extractionUsage.total + agent.chatUsage.total;
            agent = Agent(config(strategy), apiKey: key, storage: storage);
            await agent.initialize();
            if (jsonEncode(agent.facts) != old ||
                agent.turns.length != 7 ||
                agent.chatUsage.total + agent.extractionUsage.total !=
                    oldUsage) {
              throw StateError('Restore mismatch');
            }
          }
        }
      } else {
        await send(agent, prompts.first, 'common');
        final error = await agent.createCheckpoint();
        if (error != null) throw StateError(error);
        await send(
          agent,
          'Для этой ветки выбираем Firebase как backend. Это окончательное решение.',
          'A_decision',
        );
        await send(
          agent,
          'На экране входа нужна кнопка показа пароля. Подтверди кратко.',
          'A_detail',
        );
        await agent.switchBranch('B');
        await send(
          agent,
          'Для этой ветки выбираем Supabase как backend. Это окончательное решение.',
          'B_decision',
        );
        await send(
          agent,
          'На экране входа нужна ссылка восстановления пароля. Подтверди кратко.',
          'B_detail',
        );
        agent = Agent(config(strategy), apiKey: key, storage: storage);
        await agent.initialize();
        if (!agent.hasCheckpoint || agent.activeBranch != 'B') {
          throw StateError('Branch restore failed');
        }
        const question =
            'Какой backend выбран и какое дополнительное требование к экрану входа принято?';
        await agent.switchBranch('A');
        await send(agent, question, 'A_final');
        if (jsonEncode(agent.lastSentMessages).contains('Supabase')) {
          throw StateError('B leaked into A');
        }
        await agent.switchBranch('B');
        await send(agent, question, 'B_final');
        if (jsonEncode(agent.lastSentMessages).contains('Firebase')) {
          throw StateError('A leaked into B');
        }
      }
    }
  } finally {
    await Directory('docs').create(recursive: true);
    await File('docs/day10-results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await directory.delete(recursive: true);
  }
}
