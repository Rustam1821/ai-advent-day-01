import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'agent.dart';
import 'json_file_storage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 11',
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
  static JsonFileStorage _storage(String name) => JsonFileStorage(() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$name.json');
  });
  final _agent = Agent(
    const AgentConfig(
      strategy: SlidingWindow(),
      systemPrompt:
          'Ты полезный помощник. Отвечай кратко, по-русски. '
          'Используй только переданные сведения о пользователе и задаче. '
          'Не угадывай отсутствующие факты: пиши «неизвестно».',
    ),
    memory: AgentMemory(
      working: WorkingMemory(_storage('day11-working')),
      longTerm: LongTermMemory(_storage('day11-long-term')),
    ),
  );
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true, _busy = false;
  String? _error;
  bool get _disabled => _loading || _busy;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await _agent.initialize();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _action(Future<String?> Function() action) async {
    if (_disabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (mounted)
      setState(() {
        _busy = false;
        _error = error;
      });
  }

  Future<void> _saveFact() async {
    final fact = await showDialog<_Fact>(
      context: context,
      builder: (_) => const _MemoryEditor(),
    );
    if (!mounted || fact == null) return;
    await _action(
      () => _agent.saveMemory(fact.layer, key: fact.key, value: fact.value),
    );
  }

  Future<void> _send() async {
    if (_disabled || _input.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _agent.send(_input.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
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
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Day 11 · Память агента'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Память'),
            Tab(text: 'Чат'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null || _agent.memory!.warning != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error ?? _agent.memory!.warning!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [_memoryView(), _chatView()]),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _memoryView() {
    final memory = _agent.memory!;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Факты записываются только в выбранный слой.\nСообщения чата → Short-Term.',
        ),
        const SizedBox(height: 8),
        _memoryCard(
          'SHORT-TERM',
          'Сессия · последние ${memory.shortTerm.windowSize} сообщений',
          MemoryLayer.shortTerm,
          memory.shortTerm.messages
              .map((m) => '${m['role']}: ${m['content']}')
              .toList(),
        ),
        _memoryCard(
          'WORKING',
          'Текущая задача · сохраняется при restart',
          MemoryLayer.working,
          memory.working.values.entries
              .map((e) => '${e.key} = ${e.value}')
              .toList(),
        ),
        _memoryCard(
          'LONG-TERM',
          'Профиль и предпочтения · между задачами',
          MemoryLayer.longTerm,
          memory.longTerm.values.entries
              .map((e) => '${e.key} = ${e.value}')
              .toList(),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _disabled ? null : _saveFact,
          icon: const Icon(Icons.add),
          label: const Text('Сохранить факт…'),
        ),
        OutlinedButton(
          onPressed: _disabled ? null : () => _action(_agent.resetTask),
          child: const Text('Новая задача: сбросить Short + Working'),
        ),
        const Text(
          'Корзина у слоя очищает только его. Новая задача также начинает новую сессию, чтобы старые ответы не возвращали прежние факты.',
        ),
      ],
    );
  }

  Widget _memoryCard(
    String title,
    String lifetime,
    MemoryLayer layer,
    List<String> values,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Clear $title',
                icon: const Icon(Icons.delete_outline),
                onPressed: _disabled
                    ? null
                    : () => _action(() => _agent.clearMemory(layer)),
              ),
            ],
          ),
          Text(lifetime, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: SingleChildScrollView(
              child: SelectableText(
                values.isEmpty ? 'Пусто' : values.join('\n'),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chatView() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Context: ${_agent.lastCall?.result?.input ?? '—'} · '
          'Response: ${_agent.lastCall?.result?.output ?? '—'} (API)\n'
          'Всего за сессию: ${_agent.chatUsage.total} tokens'
          '${_agent.chatUsage.unknown > 0 ? ' · есть вызовы без usage' : ''}',
        ),
      ),
      Expanded(
        child: _agent.visibleMessages.isEmpty
            ? const Center(
                child: Text(
                  'Новая сессия. Working и Long-Term доступны агенту.',
                ),
              )
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final message in _agent.visibleMessages)
                    Card(
                      color: message['role'] == 'user'
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['role'] == 'user' ? 'Вы' : 'Агент',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SelectableText(message['content']!),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (_agent.lastCall != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Current message ≈ ${_agent.lastCall!.estimatedMessageTokens} (оценка) · '
            'Total call: ${_agent.lastCall!.result?.total ?? '—'} (API)',
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_disabled,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Сообщение → Short-Term',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _disabled ? null : _send,
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Fact {
  const _Fact(this.layer, this.key, this.value);
  final MemoryLayer layer;
  final String key, value;
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor();
  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  MemoryLayer _layer = MemoryLayer.shortTerm;
  final _key = TextEditingController();
  final _value = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Сохранить факт'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<MemoryLayer>(
            value: _layer,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: MemoryLayer.shortTerm,
                child: Text('Short-Term · сессия'),
              ),
              DropdownMenuItem(
                value: MemoryLayer.working,
                child: Text('Working · задача'),
              ),
              DropdownMenuItem(
                value: MemoryLayer.longTerm,
                child: Text('Long-Term · постоянно'),
              ),
            ],
            onChanged: (value) {
              if (value != null)
                setState(() {
                  _layer = value;
                  _error = null;
                });
            },
          ),
          if (_layer != MemoryLayer.shortTerm)
            TextField(
              controller: _key,
              decoration: const InputDecoration(labelText: 'Ключ'),
            ),
          TextField(
            controller: _value,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Значение / факт'),
          ),
          if (_layer != MemoryLayer.shortTerm)
            const Text(
              'Запись с тем же ключом заменит значение. В чат не добавляется.',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (_value.text.trim().isEmpty ||
              (_layer != MemoryLayer.shortTerm && _key.text.trim().isEmpty)) {
            setState(() => _error = 'Заполните поля.');
            return;
          }
          Navigator.pop(context, _Fact(_layer, _key.text, _value.text));
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
