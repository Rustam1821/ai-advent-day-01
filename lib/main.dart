import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepSeek Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _promptController = TextEditingController();
  String _answer = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isLoading) return;

    if (_apiKey.isEmpty) {
      setState(() {
        _answer =
            'API key не найден. Запустите приложение с '
            '--dart-define=DEEPSEEK_API_KEY=ваш_ключ';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _answer = '';
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final choices = data['choices'] as List<dynamic>?;
        final message = choices?.firstOrNull?['message'];
        final content = message?['content'] as String?;
        if (content == null || content.isEmpty) {
          throw const FormatException('DeepSeek вернул пустой ответ');
        }
        setState(() => _answer = content);
      } else {
        final error = data['error'] as Map<String, dynamic>?;
        throw Exception(error?['message'] ?? 'HTTP ${response.statusCode}');
      }
    } on FormatException catch (error) {
      setState(() => _answer = 'Некорректный ответ API: ${error.message}');
    } catch (error) {
      setState(() => _answer = 'Не удалось получить ответ: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepSeek Chat')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _promptController,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Ваш prompt',
                  hintText: 'Например: Объясни, что такое Flutter',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _sendPrompt,
                icon: _isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isLoading ? 'Отправка...' : 'Отправить'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ответ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _answer.isEmpty
                        ? 'Здесь появится ответ DeepSeek.'
                        : _answer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
