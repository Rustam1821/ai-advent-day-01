import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'local_llm_client.dart';

void main() => runApp(const PrivateChatApp());

class PrivateChatApp extends StatelessWidget {
  const PrivateChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 34 — Project File Assistant',
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
  bool _support = false;
  Map<String, dynamic>? _proposal;
  List<dynamic> _trace = [];
  String? _fileProgress;

  void _clearConversation() {
    _messages.clear();
    _trace = [];
    _proposal = null;
    _fileProgress = null;
    _error = null;
    _input.clear();
  }

  Future<void> _newChat() async {
    if (_busy) return;
    if (_proposal != null) await _decision(false);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(_clearConversation);
  }

  Future<void> _decision(bool approved) async {
    final proposal = _proposal;
    if (_busy || proposal == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _client.files(_url.text, _token.text, {
        'action': approved ? 'approve' : 'cancel', 'proposal': proposal['id'],
      });
      if (!mounted) return;
      setState(() {
        _proposal = null;
        _messages.add({'role': 'assistant', 'content': result['answer'] as String});
      });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _proposal = null; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _files(String text) async {
    final started = await _client.files(_url.text, _token.text,
      {'action': 'start', 'question': text.substring(6).trim()});
    while (mounted) {
      final state = await _client.files(_url.text, _token.text,
        {'action': 'status', 'job': started['job']});
      if (!mounted) return;
      setState(() {
        _trace = state['trace'] as List<dynamic>;
        final progress = state['progress'] as Map<String, dynamic>?;
        _fileProgress = '${progress?['phase'] ?? "Обработка"} · '
          'шаг ${progress?['step'] ?? 0} · ${state['elapsed_seconds'] ?? 0} с';
      });
      if (state['done'] == true) {
        if (state['error'] != null) throw LocalLlmException(state['error'] as String);
        final result = state['result'] as Map<String, dynamic>;
        setState(() {
          _messages.addAll([{'role': 'user', 'content': text},
            {'role': 'assistant', 'content': result['answer'] as String}]);
          _proposal = result['proposal'] as Map<String, dynamic>?;
          _input.clear();
        });
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  String _stepSummary(dynamic step) {
    final result = step['result'];
    if (result is Map) {
      if (result['error'] != null) return result['error'].toString();
      if (result['read'] == true) return 'Файл прочитан';
      final results = result['results'];
      if (results is List) {
        final paths = results.take(4).map((item) =>
          item is Map ? '${item['path']}:${item['line']}' : item.toString()).join(', ');
        return 'Результатов: ${results.length}${result['truncated'] == true ? " (есть ещё)" : ""}. $paths';
      }
    }
    return (step['reason'] ?? 'Обработка…').toString();
  }

  int? _ticketId;
  List<Map<String, dynamic>> _tickets = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    try {
      final data = jsonDecode(await rootBundle.loadString('data/tickets.json')) as List;
      final tickets = data.cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _ticketId = tickets.isEmpty ? null : tickets.first['id'] as int;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить список тикетов.');
    }
  }

  String? _error;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_proposal != null) return;
    if (_busy || text.isEmpty || (_support && _ticketId == null)) return;
    FocusScope.of(context).unfocus();
    final pending = [..._messages, {'role': 'user', 'content': text}];
    setState(() { _busy = true; _error = null; _fileProgress = null; _trace = []; });
    try {
      if (text == '/files' || text.startsWith('/files ')) {
        await _files(text == '/files' ? '/files ' : text);
        return;
      }
      final answer = await _client.chat(_url.text, _token.text, pending,
        support: _support, ticketId: _ticketId);
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
    appBar: AppBar(title: const Text('Day 34 — Project File Assistant'),
      actions: [IconButton(onPressed: _busy ? null : _newChat,
        tooltip: 'Новый чат', icon: const Icon(Icons.add_comment_outlined))]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Команда /files <цель> — автономная работа с файлами проекта.'),
      SwitchListTile(title: const Text('Режим Support'), value: _support,
        onChanged: _busy || _proposal != null ? null : (value) => setState(() {
          _support = value; _clearConversation();
        })),
      if (_support) ...[
        DropdownButton<int>(value: _ticketId, isExpanded: true,
          hint: const Text('Выберите тестовый тикет'),
          items: [for (final ticket in _tickets) DropdownMenuItem<int>(
            value: ticket['id'] as int,
            child: Text('#${ticket['id']} · ${ticket['problem']}',
              overflow: TextOverflow.ellipsis))],
          onChanged: _busy || _proposal != null ? null : (value) => setState(() {
            _ticketId = value; _clearConversation();
          })),
        const Text('Тестовые обращения. Данные пользователя и тикета получает Gateway через MCP.'),
      ],
      TextField(controller: _url, enabled: !_busy && _messages.isEmpty,
        keyboardType: TextInputType.url, autocorrect: false,
        decoration: const InputDecoration(labelText: 'Gateway URL', hintText: 'https://ai.example.com')),
      TextField(controller: _token, enabled: !_busy && _messages.isEmpty,
        obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Bearer token')),
      const Text('Токен и история хранятся только в памяти приложения.'),
      TextButton(onPressed: _busy ? null : _newChat, child: const Text('Новый чат')),
      for (final message in _messages) Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message['role'] == 'user' ? 'Вы' : 'qwen3:4b',
            style: const TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(message['content']!),
        ]),
      )),
      for (final step in _trace) Card(child: ExpansionTile(
        title: Text('${step['tool']} ${step['path'] ?? step['query'] ?? ""}'),
        subtitle: Text(_stepSummary(step), maxLines: 3, overflow: TextOverflow.ellipsis),
        children: [Padding(padding: const EdgeInsets.all(8),
          child: SelectableText(const JsonEncoder.withIndent('  ').convert(step)))],
      )),
      if (_proposal != null) ...[
        Text('Предлагается запись: ${_proposal!['path']}'),
        Container(color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(12),
          child: SelectableText(_proposal!['diff'] as String,
            style: const TextStyle(fontFamily: 'monospace'))),
        Wrap(spacing: 12, children: [
          FilledButton(onPressed: _busy ? null : () => _decision(true),
            child: const Text('Подтвердить запись')),
          OutlinedButton(onPressed: _busy ? null : () => _decision(false),
            child: const Text('Отменить')),
        ]),
      ],
      TextField(controller: _input, enabled: !_busy, minLines: 2, maxLines: 6,
        decoration: const InputDecoration(labelText: 'Сообщение', hintText: '/files <цель>' )),
      FilledButton(onPressed: _busy ? null : _send, child: const Text('Отправить')),
      if (_busy) ...[const LinearProgressIndicator(),
        Text(_fileProgress ?? 'Ожидание Gateway…')],
      if (_error != null) SelectableText(_error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
  );
}
