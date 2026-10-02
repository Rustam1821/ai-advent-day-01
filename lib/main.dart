import 'package:flutter/material.dart';
import 'chat_session.dart';
import 'documents.dart';
import 'indexing_service.dart';
import 'rag_service.dart';
import 'retrieval_service.dart';

void main() => runApp(const MyApp());
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 25 — RAG Chat', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)), useMaterial3: true),
    home: const ChatPage(),
  );
}
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}
class _ChatPageState extends State<ChatPage> {
  final _indexing = IndexingService();
  late final _repository = IndexRepository(_indexing);
  late final _rag = RagService(_repository);
  final _store = ChatStore();
  ChatSession _session = ChatSession();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = true, _loadFailed = false;
  String _indexStatus = 'Loading index…', _progress = '';
  String? _storageError;

  @override
  void initState() { super.initState(); _initialize(); }
  Future<void> _initialize() async {
    try {
      final session = await _store.load();
      if (mounted) setState(() => _session = session);
      if (session.messages.isNotEmpty && session.messages.last.role == 'user') {
        _progress = 'Предыдущий запрос прерван. Отправьте следующий вопрос для продолжения.';
      }
    } catch (error) {
      _loadFailed = true;
      _storageError = 'История не загружена: $error. Файл не перезаписан. Повторите загрузку или начните новый диалог.';
    }
    await _loadIndex();
    if (mounted) { setState(() => _busy = false); _bottom(); }
  }
  Future<void> _loadIndex() async {
    try {
      await _repository.load();
      if (mounted) setState(() => _indexStatus = 'Structure index ready · ${_repository.chunks.length} chunks');
    } catch (error) {
      if (mounted) setState(() => _indexStatus = '$error');
    }
  }
  Future<void> _save() async {
    try {
      await _store.save(_session);
      if (mounted) setState(() => _storageError = null);
    } catch (error) {
      if (mounted) setState(() => _storageError = 'Не удалось сохранить чат: $error. Данные пока только в памяти.');
    }
  }
  Future<void> _retryStorage() async {
    setState(() => _busy = true);
    if (_loadFailed) {
      _loadFailed = false; _storageError = null;
      await _initialize();
    } else {
      await _save();
      if (mounted) setState(() => _busy = false);
    }
  }
  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });
  void _updateProgress(String value) { if (mounted) setState(() => _progress = value); }
  Future<void> _send() async {
    final question = _input.text.trim();
    if (_busy || _loadFailed || question.isEmpty) return;
    final recent = _session.recent(); // Current question is sent separately, exactly once.
    setState(() {
      _busy = true; _input.clear();
      _session.messages.add(ChatMessage(role: 'user', content: question));
    });
    _bottom();
    await _save();
    RagResult? partial;
    try {
      final result = await _rag.answer(question, _session.state, recent, (state) async {
        if (mounted) setState(() => _session.state = state);
        await _save();
      }, _updateProgress, (result) => partial = result);
      if (mounted) {
        setState(() => _session.messages.add(ChatMessage(role: 'assistant',
          content: result.answer!.answer, answer: result.answer, evidence: result.retrieved, candidates: result.candidates,
          query: result.rewrittenQuery, finalLlmRequested: result.finalLlmRequested)));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _session.messages.add(ChatMessage(role: 'assistant',
          content: 'Запрос не завершён: $error', error: true, evidence: partial?.retrieved ?? [], candidates: partial?.candidates ?? [],
          query: partial?.rewrittenQuery, finalLlmRequested: partial?.finalLlmRequested ?? false)));
      }
    } finally {
      await _save();
      if (mounted) { setState(() { _busy = false; _progress = ''; }); _bottom(); }
    }
  }
  Future<void> _reset() async {
    setState(() => _busy = true);
    final empty = ChatSession();
    try {
      await _store.save(empty);
      if (mounted) {
        setState(() { _session = empty; _loadFailed = false; _storageError = null; _progress = ''; _input.clear(); });
      }
    } catch (error) {
      if (mounted) setState(() => _storageError = 'Новый диалог не сохранён: $error. Старый чат оставлен.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _rebuild() async {
    setState(() => _busy = true);
    try {
      await _indexing.build(await DocumentLoader().load(), _updateProgress);
      await _loadIndex();
      _updateProgress('Index saved');
    } catch (error) { _updateProgress('Rebuild failed: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Widget _message(ChatMessage m) => Card(
    color: m.role == 'user' ? Theme.of(context).colorScheme.primaryContainer : null,
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.role == 'user' ? 'User' : 'Assistant', style: const TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(m.content, style: m.error ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
        if (m.answer?.isInsufficientContext == true) ...[
          Text(m.answer!.clarificationRequest!), const Text('Sources: none · Недостаточно контекста'),
        ],
        if (m.answer != null && !m.answer!.isInsufficientContext) ...[
          const SizedBox(height: 8),
          const Text('Sources & quotes · проверены ID / metadata / quote'),
          for (final c in m.answer!.citations) Padding(padding: const EdgeInsets.only(top: 6),
            child: SelectableText('${c.source} / ${c.section ?? "—"}\n${c.chunkId}\n«${c.quote}»')),
        ],
        if (m.role == 'assistant') ExpansionTile(title: const Text('RAG details'), children: [
          SelectableText('Query: ${m.query ?? "не получен"}\nThreshold: ${RetrievalConfig.similarityThreshold}\n'
            'Filtered chunks: ${m.evidence.length} · Final LLM: ${m.finalLlmRequested ? "requested" : "not called"}'),
          const Text('BEFORE FILTER — candidates'),
          if (m.candidates.isEmpty) const Text('Кандидаты не сохранены: отправьте вопрос заново.'),
          for (final hit in m.candidates) Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SelectableText('${hit.chunk.metadata['source']} / ${hit.chunk.metadata['section']}\n'
              'Score: ${hit.score.toStringAsFixed(4)} · '
              '${hit.score >= RetrievalConfig.similarityThreshold ? "PASS" : "BELOW THRESHOLD"}\n'
              '${(hit.chunk.metadata['text'] as String).length > 300 ? (hit.chunk.metadata['text'] as String).substring(0, 300) : hit.chunk.metadata['text']}'),
          ),
          const Text('AFTER FILTER — sent context'),
          for (final hit in m.evidence) Text('${hit.chunk.metadata['source']} / '
            '${hit.chunk.metadata['section']} · ${hit.score.toStringAsFixed(3)}'),
        ]),
      ],
    )),
  );
  @override
  void dispose() { _input.dispose(); _scroll.dispose(); _rag.dispose(); _indexing.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 25 — RAG Chat')),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850),
      child: Column(children: [
        Expanded(child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
          ExpansionTile(title: const Text('TASK STATE'), children: [
            SelectableText('Goal: ${_session.state.goal}\n'
              'Clarifications:\n${_session.state.clarifications.join('\n')}\n'
              'Constraints:\n${_session.state.constraints.join('\n')}\n'
              'Terms:\n${_session.state.terms.join('\n')}'),
          ]),
          ExpansionTile(title: Text(_indexStatus), children: [
            OutlinedButton(onPressed: _busy ? null : _rebuild, child: const Text('Build/Rebuild Index')),
          ]),
          if (_session.messages.isEmpty) const Text('Задайте цель диалога и первый вопрос по базе знаний.'),
          for (final m in _session.messages) _message(m),
        ])),
        if (_storageError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [Text(_storageError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextButton(onPressed: _busy ? null : _retryStorage, child: const Text('Retry storage'))])),
        if (_busy) const LinearProgressIndicator(),
        if (_progress.isNotEmpty) Text(_progress),
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: _input, enabled: !_busy && !_loadFailed,
            minLines: 1, maxLines: 4, maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Message', counterText: ''))),
          FilledButton(onPressed: _busy || _loadFailed ? null : _send, child: const Text('Send')),
        ])),
        TextButton(onPressed: _busy ? null : _reset, child: const Text('New conversation')),
      ]),
    ))),
  );
}
