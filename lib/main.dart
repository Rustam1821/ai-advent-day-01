import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
const _endpoint = 'https://api.deepseek.com/chat/completions';
const _model = 'deepseek-v4-flash';
const _stopSequence = '<END>';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Advent — Day 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ComparePage(),
    );
  }
}

class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  final _promptController = TextEditingController();
  _DeepSeekResult? _freeResult;
  _DeepSeekResult? _controlledResult;
  String _sentPrompt = '';
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _compareAnswers() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isLoading) return;
    if (_apiKey.isEmpty) {
      setState(
        () => _error =
            'API key не найден. Запустите приложение с '
            '--dart-define-from-file=.env',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _sentPrompt = prompt;
      _freeResult = null;
      _controlledResult = null;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _requestDeepSeek(prompt: prompt, controlled: false),
        _requestDeepSeek(prompt: prompt, controlled: true),
      ]);
      if (!mounted) return;
      setState(() {
        _freeResult = results[0];
        _controlledResult = results[1];
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось получить ответы: $error');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<_DeepSeekResult> _requestDeepSeek({
    required String prompt,
    required bool controlled,
  }) async {
    final messages = <Map<String, String>>[];
    if (controlled) {
      messages.add({
        'role': 'system',
        'content':
            '''
Return only valid JSON in exactly this format:
{"title":"short title","summary":"up to 40 words","key_points":["point 1","point 2","point 3"]}
Keep exactly these three fields and exactly 3 key_points. Each key point must be at most 12 words. Do not use Markdown. Immediately after the closing JSON brace emit $_stopSequence and finish.
''',
      });
    }
    messages.add({'role': 'user', 'content': prompt});

    final body = <String, dynamic>{'model': _model, 'messages': messages};
    if (controlled) {
      body.addAll({
        'thinking': {'type': 'disabled'},
        'response_format': {'type': 'json_object'},
        'max_tokens': 220,
        'stop': [_stopSequence],
      });
    }

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode(body),
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

    var displayContent = content.trim();
    if (controlled) {
      final json = jsonDecode(displayContent) as Map<String, dynamic>;
      _validateControlledJson(json);
      displayContent = const JsonEncoder.withIndent('  ').convert(json);
    }

    final usage = data['usage'] as Map<String, dynamic>?;
    return _DeepSeekResult(
      content: displayContent,
      finishReason: choice?['finish_reason'] as String? ?? 'unknown',
      completionTokens: usage?['completion_tokens'] as int?,
    );
  }

  void _validateControlledJson(Map<String, dynamic> json) {
    const expectedKeys = {'title', 'summary', 'key_points'};
    final keys = json.keys.toSet();
    final points = json['key_points'];
    if (keys.difference(expectedKeys).isNotEmpty ||
        !keys.containsAll(expectedKeys) ||
        json['title'] is! String ||
        json['summary'] is! String ||
        points is! List ||
        points.length != 3 ||
        points.any((point) => point is! String)) {
      throw const FormatException(
        'контролируемый ответ не соответствует заданной JSON-структуре',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day 2 · Формат ответа')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Один prompt → два ответа',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Исходный prompt для обоих режимов',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _compareAnswers,
                icon: _isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compare_arrows),
                label: Text(
                  _isLoading ? 'Получаем оба ответа...' : 'Сравнить два ответа',
                ),
              ),
              if (_sentPrompt.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Одинаковый prompt: “$_sentPrompt”'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              _AnswerCard(
                title: '1 · Без ограничений',
                subtitle: 'Только исходный prompt, без требований к ответу',
                result: _freeResult,
              ),
              const SizedBox(height: 12),
              _AnswerCard(
                title: '2 · С контролем',
                subtitle: 'JSON · 3 пункта · max 220 tokens · stop <END>',
                result: _controlledResult,
                controlled: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.title,
    required this.subtitle,
    required this.result,
    this.controlled = false,
  });

  final String title;
  final String subtitle;
  final _DeepSeekResult? result;
  final bool controlled;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: controlled ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            SelectableText(
              result?.content ?? 'Ответ появится здесь.',
              style: controlled
                  ? const TextStyle(fontFamily: 'monospace')
                  : null,
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              Text(
                'Завершение: ${result!.finishReason} · '
                'токенов: ${result!.completionTokens ?? '—'}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeepSeekResult {
  const _DeepSeekResult({
    required this.content,
    required this.finishReason,
    required this.completionTokens,
  });

  final String content;
  final String finishReason;
  final int? completionTokens;
}
