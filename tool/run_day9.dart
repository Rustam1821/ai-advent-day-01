// Manual live experiment. Uses isolated storage; never touches the app's chat.
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
  final prompts = [
    'Запомни факты: проект Orion, основной цвет зелёный, релиз в пятницу. '
        'Менеджер Ирина, бюджет 48000 рублей. Это обязательные ограничения. Ответь кратко.',
    for (final topic in [
      'навигация',
      'форма регистрации',
      'уведомления',
      'экран профиля',
      'настройки',
      'экран помощи',
      'проверка доступности',
      'план тестирования',
    ])
      'Обсудим раздел «$topic». Предложи два коротких пункта плана. '
          'Общие требования: интерфейс на русском языке, понятные подписи, '
          'удобные кнопки, минимум отвлекающих элементов. Ошибки объясняем простым '
          'языком и сохраняем введённые данные. Не используем анимацию, мешающую '
          'чтению. Обязательно учитываем небольшой экран телефона и увеличенный '
          'системный шрифт. Пользователь должен понимать результат каждого действия. '
          'Все действия должны иметь ясное название, а необратимые изменения — '
          'подтверждение. Для пустого списка нужно объяснение и следующий шаг. '
          'Не добавляй новые факты о проекте; отвечай не более 60 слов.',
    'Как называется проект, какой основной цвет, когда релиз, кто менеджер '
        'и какой бюджет? Перечисли только известные факты.',
  ];
  final directory = await Directory.systemTemp.createTemp('day9-');
  final report = <Map<String, dynamic>>[];
  try {
    for (final enabled in [false, true]) {
      final file = File('${directory.path}/$enabled.json');
      final storage = HistoryStorage(() async => file);
      final config = AgentConfig(
        compressionEnabled: enabled,
        temperature: 0,
        maxTokens: 250,
      );
      var agent = Agent(config, apiKey: key, storage: storage);
      for (var i = 0; i < prompts.length; i++) {
        final result = await agent.send(prompts[i]);
        if (result.error != null) throw StateError(result.error!);
        final state = await storage.loadState();
        final original = (state['messages'] as List)
            .cast<Map<String, String>>();
        final sent = agent.lastSentMessages;
        final offset = enabled ? agent.compressedMessageCount : 0;
        final actualRecent = sent.where((m) => m['role'] != 'system').toList();
        final expectedRecent = original.sublist(offset, original.length - 1);
        if (jsonEncode(actualRecent) != jsonEncode(expectedRecent)) {
          throw StateError('Sent history differs from verbatim recent window');
        }
        final record = <String, dynamic>{
          'compression': enabled,
          'turn': i + 1,
          'prompt': prompts[i],
          'input': result.input,
          'output': result.output,
          'total': result.total,
          'finish': result.finishReason,
          'answer': result.content,
          'compressed': agent.compressedMessageCount,
          'recent': agent.recentMessageCount,
          'summary': agent.summary,
          'summary_tokens': agent.summaryTokens,
          'compressions': agent.compressionCount,
          'chat_usage': agent.chatUsage.toJson(),
          'summary_usage': agent.summaryUsage.toJson(),
          'cumulative': agent.chatUsage.total + agent.summaryUsage.total,
          'sent_messages': sent,
        };
        report.add(record);
        stdout.writeln(
          jsonEncode(
            {...record}
              ..remove('sent_messages')
              ..remove('summary')
              ..remove('prompt'),
          ),
        );
        // Real restart after first and second possible compressions.
        if (i == 4 || i == 6) {
          final oldSummary = agent.summary;
          final oldCount = agent.compressedMessageCount;
          final oldUsage = agent.summaryUsage.total + agent.chatUsage.total;
          agent = Agent(config, apiKey: key, storage: storage);
          await agent.initialize();
          if (agent.summary != oldSummary ||
              agent.compressedMessageCount != oldCount ||
              agent.summaryUsage.total + agent.chatUsage.total != oldUsage ||
              agent.turns.length != i + 1) {
            throw StateError('Restore mismatch');
          }
        }
      }
    }
  } finally {
    await Directory('docs').create(recursive: true);
    await File('docs/day9-results.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await directory.delete(recursive: true);
  }
}
