import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'agent.dart';
import 'history_storage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 8',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)),
      scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      useMaterial3: true,
    ),
    home: const AgentPage(),
  );
}

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _agent = Agent(
    const AgentConfig(),
    storage: HistoryStorage(() async {
      final directory = await getApplicationSupportDirectory();
      return File('${directory.path}/conversation.json');
    }),
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await _agent.initialize();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  Future<void> _action(String action) async {
    if (_loading || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = action == 'clear'
        ? await _agent.clearConversation()
        : await _agent.prepareDemoHistory(overflow: action == 'overflow');
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null && action == 'clear') _input.clear();
    });
  }

  Future<void> _send() async {
    if (_loading || _sending || _input.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await _agent.send(_input.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = result.error;
      if (result.error == null) _input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turns = _agent.turns;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day 8 · Токены'),
        actions: [
          IconButton(
            tooltip: 'Очистить диалог',
            onPressed: _loading || _sending ? null : () => _action('clear'),
            icon: const Icon(Icons.delete_outline),
          ),
          if (kDebugMode)
            PopupMenuButton<String>(
              tooltip: 'Day 8 demo',
              enabled: !_loading && !_sending,
              onSelected: _action,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'long',
                  child: Text('Demo: + длинная история'),
                ),
                PopupMenuItem(
                  value: 'overflow',
                  child: Text('Demo: + overflow (1M+)'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Context = system + вся история + новое сообщение.\n'
                    'DeepSeek Flash · окно 1M · история сохраняется.',
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : turns.isEmpty
                      ? const Center(
                          child: Text(
                            'Расскажите что-нибудь, затем задайте вопрос.',
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: turns.length,
                          itemBuilder: (context, index) {
                            final turn = turns[index];
                            final result = turn.result;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _bubble('Вы', turn.userText, true),
                                if (result?.content != null)
                                  _bubble('Агент', result!.content!, false),
                                if (result == null && !_sending)
                                  const Text(
                                    'Нет ответа (локальные demo-данные или незавершённая отправка).',
                                  ),
                                if (result?.elapsed != null) _metrics(turn),
                                if (result?.finishReason != null &&
                                    result!.finishReason != 'stop')
                                  const Text('Ответ может быть неполным.'),
                              ],
                            );
                          },
                        ),
                ),
                if (_sending) const LinearProgressIndicator(),
                if (_error != null || _agent.storageWarning != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error ?? _agent.storageWarning!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !_loading && !_sending,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Сообщение',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading || _sending ? null : _send,
                        child: Text(_sending ? 'Ждём…' : 'Отправить'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metrics(AgentTurn turn) {
    final result = turn.result!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current message ≈ ${turn.estimatedMessageTokens} tokens (оценка)',
            ),
            Text('Context: ${result.input ?? '—'} tokens (API)'),
            Text('Response: ${result.output ?? '—'} tokens (API)'),
            Text('Total call: ${result.total ?? '—'} tokens (API)'),
            if (result.input == null)
              const Text('API не вернул usage. История не обрезана.'),
            Text(
              'Время: ${(result.elapsed!.inMilliseconds / 1000).toStringAsFixed(2)} с',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String title, String text, bool user) => Card(
    color: user ? Theme.of(context).colorScheme.primaryContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(
            text.length > 600 ? '${text.substring(0, 600)}…' : text,
          ),
          if (text.length > 600)
            const Text(
              'Показан фрагмент. В истории и API — полный текст.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    ),
  );
}
