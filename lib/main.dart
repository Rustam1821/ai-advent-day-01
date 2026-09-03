import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
const _endpoint = 'https://api.deepseek.com/chat/completions';
const _model = 'deepseek-v4-flash';
const _systemPrompt = '''
Ты — креативный русскоязычный копирайтер. Строго соблюдай все ограничения пользователя. Не объясняй свой выбор, выведи только готовый результат.
''';
const _userPrompt = '''
Придумай название и рекламный слоган для новой кофейни на Марсе. Название должно состоять максимум из двух слов. Слоган должен содержать слово «кофе» и быть не длиннее 10 слов. Кратко объясни идею названия. Оформи ответ тремя строками: «Название», «Слоган» и «Идея».
''';
const _temperatures = [0.0, 0.7, 1.2];

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Advent — Day 4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const TemperatureExperimentPage(),
    );
  }
}

class TemperatureExperimentPage extends StatefulWidget {
  const TemperatureExperimentPage({super.key});

  @override
  State<TemperatureExperimentPage> createState() =>
      _TemperatureExperimentPageState();
}

class _TemperatureExperimentPageState extends State<TemperatureExperimentPage> {
  final Map<double, _ApiResult> _results = {};
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
      _results.clear();
      _error = null;
    });

    try {
      await Future.wait(
        _temperatures.map((temperature) async {
          final result = await _askDeepSeek(temperature);
          if (mounted) {
            setState(() => _results[temperature] = result);
          }
        }),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка эксперимента: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<_ApiResult> _askDeepSeek(double temperature) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'thinking': {'type': 'disabled'},
        'temperature': temperature,
        'max_tokens': 350,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': _userPrompt},
        ],
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
      appBar: AppBar(title: const Text('Day 4 · Temperature')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Один prompt → 3 температуры',
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
                      'Одинаковый prompt',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(_userPrompt),
                    Divider(height: 24),
                    Text(
                      'Модель, system prompt и все остальные параметры '
                      'одинаковы. Меняется только temperature.',
                      style: TextStyle(fontSize: 12),
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
                  : const Icon(Icons.thermostat),
              label: Text(
                _isLoading
                    ? 'DeepSeek выполняет 3 запроса...'
                    : 'Запустить эксперимент',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            for (final temperature in _temperatures)
              _TemperatureCard(
                temperature: temperature,
                result: _results[temperature],
                loading: _isLoading,
              ),
            const SizedBox(height: 8),
            const Text(
              'Обычно низкая temperature даёт более предсказуемые формулировки, '
              'а высокая — больше вариативности. Сравните реальные ответы выше.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  const _TemperatureCard({
    required this.temperature,
    required this.result,
    required this.loading,
  });

  final double temperature;
  final _ApiResult? result;
  final bool loading;

  String get _label => switch (temperature) {
    0 => 'Минимальная вариативность',
    0.7 => 'Средняя вариативность',
    _ => 'Высокая вариативность',
  };

  @override
  Widget build(BuildContext context) {
    final isReady = result != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: isReady
              ? const Icon(Icons.check, color: Colors.green)
              : const Icon(Icons.thermostat),
        ),
        title: Text(
          'temperature = ${temperature.toStringAsFixed(temperature == 0 ? 0 : 1)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isReady
              ? '$_label · ${result!.tokens ?? '—'} токенов'
              : loading
              ? 'Выполняется...'
              : _label,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
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
