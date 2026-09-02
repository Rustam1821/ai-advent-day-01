import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
const _endpoint = 'https://api.deepseek.com/chat/completions';
const _model = 'deepseek-v4-flash';
const _task = '''
Четырём людям нужно перейти мост ночью. У них один фонарь, без него идти нельзя. Мост выдерживает максимум двоих. Скорости людей: 1, 2, 7 и 10 минут на переход. Когда идут двое, они движутся со скоростью более медленного. Какое минимальное время нужно всем четверым, чтобы перейти мост? Укажи последовательность переходов и обоснуй минимальность.
''';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Advent — Day 3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const PromptingExperimentPage(),
    );
  }
}

class PromptingExperimentPage extends StatefulWidget {
  const PromptingExperimentPage({super.key});

  @override
  State<PromptingExperimentPage> createState() =>
      _PromptingExperimentPageState();
}

class _PromptingExperimentPageState extends State<PromptingExperimentPage> {
  _ApiResult? _direct;
  _ApiResult? _stepByStep;
  _ApiResult? _selfPrompting;
  _ApiResult? _experts;
  String? _generatedPrompt;
  String? _error;
  bool _isLoading = false;

  Future<void> _runExperiment() async {
    if (_isLoading) return;
    if (_apiKey.isEmpty) {
      setState(() {
        _error =
            'API key не найден. Запустите приложение с '
            '--dart-define-from-file=.env';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _direct = null;
      _stepByStep = null;
      _selfPrompting = null;
      _experts = null;
      _generatedPrompt = null;
      _error = null;
    });

    try {
      await Future.wait([
        _ask([
          {
            'role': 'system',
            'content': 'Отвечай по-русски и кратко, не более 250 слов.',
          },
          {'role': 'user', 'content': _task},
        ]).then((result) {
          if (mounted) setState(() => _direct = result);
        }),
        _ask([
          {
            'role': 'system',
            'content':
                'Решай задачу пошагово. Сначала выдели ограничения, затем '
                'перебери разумные стратегии, посчитай каждый шаг и отдельно '
                'докажи, что найденное время минимально. Отвечай по-русски, '
                'не более 250 слов.',
          },
          {'role': 'user', 'content': _task},
        ]).then((result) {
          if (mounted) setState(() => _stepByStep = result);
        }),
        _runSelfPrompting(),
        _ask([
          {
            'role': 'system',
            'content':
                'Ты — консилиум из трёх экспертов. Аналитик формализует '
                'ограничения и предлагает решение. Оптимизатор ищет более '
                'быструю стратегию. Критик проверяет расчёты и минимальность. '
                'Покажи краткое мнение каждого под отдельным заголовком, затем '
                'дай согласованный итог консилиума. Каждой роли дай максимум '
                'два предложения. Весь ответ — на русском, максимум 120 слов, '
                'обязательно закончи числовым итогом.',
          },
          {'role': 'user', 'content': _task},
        ]).then((result) {
          if (mounted) setState(() => _experts = result);
        }),
      ]);
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка эксперимента: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runSelfPrompting() async {
    final promptResult = await _ask([
      {
        'role': 'system',
        'content':
            'Ты — prompt engineer. Создай самостоятельный, точный prompt, '
            'который поможет другой LLM правильно решить переданную задачу. '
            'Сохрани все исходные данные и потребуй проверить минимальность. '
            'Потребуй ответить по-русски не более чем в 250 словах. Сам prompt '
            'должен быть не длиннее 180 слов. Верни только готовый prompt.',
      },
      {
        'role': 'user',
        'content':
            'Создай качественный prompt для решения этой задачи:\n$_task',
      },
    ]);
    if (mounted) setState(() => _generatedPrompt = promptResult.content);

    final solution = await _ask([
      {'role': 'user', 'content': promptResult.content},
    ]);
    if (mounted) setState(() => _selfPrompting = solution);
  }

  Future<_ApiResult> _ask(List<Map<String, String>> messages) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'thinking': {'type': 'disabled'},
        'temperature': 0.3,
        'max_tokens': 1000,
        'messages': messages,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'] as Map<String, dynamic>?;
      throw Exception(error?['message'] ?? 'HTTP ${response.statusCode}');
    }

    final choices = data['choices'] as List<dynamic>?;
    final choice = choices?.firstOrNull as Map<String, dynamic>?;
    final message = choice?['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const FormatException('DeepSeek вернул пустой ответ');
    }

    final usage = data['usage'] as Map<String, dynamic>?;
    return _ApiResult(
      content: content.trim(),
      tokens: usage?['completion_tokens'] as int?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day 3 · Prompting strategies')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Одна задача → 4 стратегии',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Задача',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(_task),
                    Divider(height: 24),
                    Text(
                      'Правильный ответ для проверки: 17 минут',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isLoading ? null : _runExperiment,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.science),
              label: Text(
                _isLoading
                    ? 'DeepSeek выполняет 5 вызовов...'
                    : 'Запустить эксперимент',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            _ResultTile(
              number: 1,
              title: 'Direct',
              subtitle: 'Исходная задача без стратегии',
              result: _direct,
              loading: _isLoading,
            ),
            _ResultTile(
              number: 2,
              title: 'Step-by-step',
              subtitle: 'Ограничения → варианты → проверка',
              result: _stepByStep,
              loading: _isLoading,
            ),
            _ResultTile(
              number: 3,
              title: 'Self-prompting',
              subtitle: 'Call 1: prompt → Call 2: решение',
              result: _selfPrompting,
              loading: _isLoading,
              generatedPrompt: _generatedPrompt,
            ),
            _ResultTile(
              number: 4,
              title: 'Experts',
              subtitle: 'Аналитик + оптимизатор + критик',
              result: _experts,
              loading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.result,
    required this.loading,
    this.generatedPrompt,
  });

  final int number;
  final String title;
  final String subtitle;
  final _ApiResult? result;
  final bool loading;
  final String? generatedPrompt;

  @override
  Widget build(BuildContext context) {
    final isReady = result != null;
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: isReady
              ? const Icon(Icons.check, color: Colors.green)
              : Text('$number'),
        ),
        title: Text(
          '$number · $title',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isReady
              ? '$subtitle · ${result!.tokens ?? '—'} токенов'
              : loading
              ? title == 'Self-prompting' && generatedPrompt != null
                    ? 'Call 1 готов, выполняется Call 2...'
                    : 'Выполняется...'
              : subtitle,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (generatedPrompt != null) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Generated prompt (Call 1)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(generatedPrompt!),
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Итоговое решение (Call 2)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              result?.content ??
                  (loading ? 'Ожидаем ответ DeepSeek...' : 'Ещё не запущено.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiResult {
  const _ApiResult({required this.content, required this.tokens});

  final String content;
  final int? tokens;
}
