import 'package:flutter/material.dart';
import 'local_llm_client.dart';

void main() => runApp(const PrivateChatApp());

class PrivateChatApp extends StatelessWidget {
  const PrivateChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 31 — Developer Assistant',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3))),
    home: const ChatPage(),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _input = TextEditingController();
  final _client = LocalLlmClient();
  final _messages = <Map<String, String>>[];
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final pending = [..._messages, {'role': 'user', 'content': text}];
    setState(() { _busy = true; _error = null; });
    try {
      final answer = await _client.chat(_url.text, _token.text, pending);
      if (!mounted) return;
      setState(() {
        _messages.addAll([{'role': 'user', 'content': text},
          {'role': 'assistant', 'content': answer}]);
        _input.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose(); _token.dispose(); _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 31 — Developer Assistant')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _url, enabled: !_busy && _messages.isEmpty,
        keyboardType: TextInputType.url, autocorrect: false,
        decoration: const InputDecoration(labelText: 'Gateway URL', hintText: 'https://ai.example.com')),
      TextField(controller: _token, enabled: !_busy && _messages.isEmpty,
        obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Bearer token')),
      const Text('Токен и история хранятся только в памяти приложения.'),
      TextButton(onPressed: _busy ? null : () => setState(() {
        _messages.clear(); _error = null;
      }), child: const Text('Новый чат')),
      for (final message in _messages) Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message['role'] == 'user' ? 'Вы' : 'qwen3:4b',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(message['content']!),
        ]),
      )),
      TextField(controller: _input, enabled: !_busy, minLines: 2, maxLines: 6,
        decoration: const InputDecoration(labelText: 'Сообщение', hintText: '/help Как устроен проект?')),
      FilledButton(onPressed: _busy ? null : _send, child: const Text('Отправить')),
      if (_busy) ...[const LinearProgressIndicator(),
        const Text('Ожидание очереди или ответа модели…')],
      if (_error != null) SelectableText(_error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
  );
}
