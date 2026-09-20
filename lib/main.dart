import 'dart:convert';

import 'package:flutter/material.dart';

import 'agent.dart';
import 'mcp_client_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 17', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)), useMaterial3: true),
    home: const AgentPage(),
  );
}

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _mcp = McpClientService();
  late final _agent = Agent(_mcp);
  final _input = TextEditingController();
  final List<({String user, String answer})> _turns = [];
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (_busy || prompt.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final answer = await _agent.send(prompt, () { if (mounted) setState(() {}); });
      if (!mounted) return;
      setState(() { _turns.add((user: prompt, answer: answer)); _input.clear(); });
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось получить ответ: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _agent.dispose(); _mcp.dispose(); _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 17 · Agent + MCP')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: ListenableBuilder(listenable: _mcp, builder: (context, _) {
        final connected = _mcp.status == McpStatus.connected;
        final connecting = _mcp.status == McpStatus.connecting;
        return Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MCP: ${_mcp.status.name}'),
              Text(McpClientService.endpoint.toString(), style: Theme.of(context).textTheme.bodySmall),
              if (connected) const Text('Discovered: get_task_status'),
            ])),
            OutlinedButton(onPressed: _busy || connecting || connected ? null : _mcp.connect,
              child: const Text('Connect')),
          ])),
          if (_busy || connecting) const LinearProgressIndicator(),
          if (_error != null || _mcp.error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error ?? _mcp.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(child: ListView(
            reverse: true, padding: const EdgeInsets.all(12),
            children: [
              if (_agent.lastCall != null)
                Card(child: ExpansionTile(title: const Text('Last MCP Tool Call'),
                  subtitle: Text(jsonEncode(_agent.lastCall!['arguments'])),
                  children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_agent.lastCall)))],
                )),
              for (final turn in _turns.reversed)
                Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('Вы: ${turn.user}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8), SelectableText('Agent: ${turn.answer}')],
                ))),
              if (_turns.isEmpty) const Text('Подключите MCP и спросите: Какой статус задачи AI-101?'),
            ],
          )),
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Expanded(child: TextField(controller: _input, enabled: !_busy,
              minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Сообщение'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy || !connected ? null : _send, child: const Text('Отправить')),
          ])),
        ]);
      }),
    ))),
  );
}
