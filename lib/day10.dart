import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'agent.dart';
import 'history_storage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 10',
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
  static const _strategies = <ContextStrategy>[
    SlidingWindow(),
    StickyFacts(),
    Branching(),
  ];
  static HistoryStorage _storage(String name) => HistoryStorage(() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$name.json');
  });
  final _agents = [
    for (final strategy in _strategies)
      Agent(
        AgentConfig(strategy: strategy),
        storage: _storage('day10-${strategy.id}'),
      ),
  ];
  final _selection = _storage('day10-selection');
  int _selected = 0;
  Agent get _agent => _agents[_selected];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await Future.wait(_agents.map((agent) => agent.initialize()));
    try {
      final state = await _selection.loadState();
      final selected = state['selected'] as int? ?? 0;
      if (selected >= 0 && selected < _agents.length) _selected = selected;
    } catch (_) {
      /* A missing/invalid preference keeps Sliding selected. */
    }
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
    final error = switch (action) {
      'clear' => await _agent.clearConversation(),
      'checkpoint' => await _agent.createCheckpoint(),
      _ => await _agent.switchBranch(action),
    };
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null) _input.clear();
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
        title: const Text('Day 10 · Context strategies'),
        actions: [
          IconButton(
            tooltip: 'Очистить диалог',
            onPressed: _loading || _sending ? null : () => _action('clear'),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: DropdownButton<int>(
                    value: _selected,
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < _strategies.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_strategies[i].label),
                        ),
                    ],
                    onChanged: _loading || _sending
                        ? null
                        : (value) async {
                            if (value == null) return;
                            setState(() => _sending = true);
                            try {
                              await _selection.saveState({
                                'messages': [],
                                'selected': value,
                              });
                              if (!mounted) return;
                              setState(() {
                                _selected = value;
                                _input.clear();
                                _error = null;
                              });
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Не удалось сохранить выбор стратегии.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _sending = false);
                            }
                          },
                  ),
                ),
                if (_agent.config.strategy is Branching)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (!_agent.hasCheckpoint)
                          OutlinedButton(
                            onPressed: _loading || _sending
                                ? null
                                : () => _action('checkpoint'),
                            child: const Text('Create checkpoint'),
                          )
                        else ...[
                          Text(
                            'Checkpoint: ${_agent.checkpointMessageCount} сообщений',
                          ),
                          const Spacer(),
                          for (final name in _agent.branchNames)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text(name),
                                selected: _agent.activeBranch == name,
                                onSelected: _sending
                                    ? null
                                    : (_) => _action(name),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                _strategyInfo(),
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

  Widget _strategyInfo() {
    final chat = _agent.chatUsage;
    final service = _agent.extractionUsage;
    final strategy = _agent.config.strategy!;
    return ExpansionTile(
      key: ValueKey(strategy.id),
      title: Text(
        'Context: ${_agent.lastCall?.result?.input ?? "—"} '
        '· Response: ${_agent.lastCall?.result?.output ?? "—"}',
      ),
      subtitle: Text(
        'Chat: ${chat.total} · Extraction: ${service.total} '
        '· Всего: ${chat.total + service.total}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SizedBox(
          height: 170,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strategy is Branching
                      ? 'Активная ветка: ${_agent.hasCheckpoint ? _agent.activeBranch : "общая история"}. '
                            'Токены суммарно по всем веткам.'
                      : 'Window: 6 сообщений, включая новый user.',
                ),
                Text(
                  'Видимая история: ${_agent.visibleMessages.length} сообщений; '
                  'в последнем API context: ${_agent.lastSentMessages.length} (включая system).',
                ),
                Text('Chat input/output: ${chat.input} / ${chat.output}'),
                if (strategy is StickyFacts) ...[
                  Text(
                    'Extraction input/output: ${service.input} / ${service.output} '
                    '· вызовов: ${service.calls}',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_agent.facts),
                  ),
                ],
                if (chat.unknown + service.unknown > 0)
                  Text(
                    'Usage неизвестен для ${chat.unknown + service.unknown} вызовов; сумма неполная.',
                  ),
              ],
            ),
          ),
        ),
      ],
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
            if (result.input == null) const Text('API не вернул usage.'),
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
          SelectableText(text),
        ],
      ),
    ),
  );
}
