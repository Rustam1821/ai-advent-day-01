import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'agent.dart';
import 'history_storage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 7',
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
      appBar: AppBar(title: const Text('Day 7 · Сохранение контекста')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Агент помнит диалог даже после перезапуска.'),
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
                                if (result != null)
                                  _bubble('Агент', result.content!, false),
                                if (result == null && !_sending)
                                  const Text(
                                    'Ответ не получен. Можно повторить сообщение.',
                                  ),
                                if (result?.elapsed != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Text(
                                      'Время: ${((result!.elapsed?.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)} с'
                                      ' · Токены: ${result.input ?? '—'} → ${result.output ?? '—'}'
                                      ' · Всего: ${result.total ?? '—'}'
                                      '\nСтоимость: ${result.cost == null ? '—' : '\$${result.cost!.toStringAsFixed(6)} USD (расчёт)'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
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

  Widget _bubble(String title, String text, bool user) => Card(
    color: user ? Theme.of(context).colorScheme.primaryContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(text),
        ],
      ),
    ),
  );
}
