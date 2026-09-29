import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'documents.dart';
import 'indexing_service.dart';
import 'rag_service.dart';
import 'retrieval_service.dart';

void main() => runApp(const MyApp());
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 22 — RAG', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)), useMaterial3: true),
    home: const RagPage(),
  );
}
class RagPage extends StatefulWidget {
  const RagPage({super.key});
  @override
  State<RagPage> createState() => _RagPageState();
}
class _RagPageState extends State<RagPage> {
  final _indexing = IndexingService();
  late final _repository = IndexRepository(_indexing);
  late final _rag = RagService(_repository);
  final _question = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  int? _selected;
  bool _busy = true;
  String _indexStatus = 'Loading index…', _progress = '';
  String? _offError, _onError;
  RagResult? _off, _on;
  List<RetrievedChunk> _hits = [];

  @override
  void initState() { super.initState(); _initialize(); }
  Future<void> _initialize() async {
    try {
      final items = (jsonDecode(await rootBundle.loadString('evaluation/questions.json')) as List)
          .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _questions = items; _selected = 0; _question.text = items.first['question'] as String; });
    } catch (error) {
      if (mounted) setState(() => _progress = 'Набор вопросов не прочитан: $error');
    }
    await _loadIndex();
    if (mounted) setState(() => _busy = false);
  }
  Future<void> _loadIndex() async {
    try {
      await _repository.load();
      if (mounted) setState(() => _indexStatus = 'Structure index ready · ${_repository.chunks.length} chunks');
    } catch (error) {
      if (mounted) setState(() => _indexStatus = '$error');
    }
  }
  void _clearResults() { _off = _on = null; _offError = _onError = null; _hits = []; }
  Future<void> _rebuild() async {
    setState(() { _busy = true; _clearResults(); });
    try {
      await _indexing.build(await DocumentLoader().load(), _updateProgress);
      await _loadIndex();
    } catch (error) {
      _updateProgress('Rebuild failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  void _updateProgress(String text) { if (mounted) setState(() => _progress = text); }
  Future<void> _ask(List<bool> modes) async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      for (final mode in modes) {
        if (mode) { _on = null; _onError = null; _hits = []; }
        else { _off = null; _offError = null; }
      }
    });
    for (final mode in modes) {
      if (!mounted) break;
      try {
        final result = await _rag.answer(question, mode, _updateProgress, (hits) {
          if (mounted) setState(() => _hits = hits);
        });
        if (mounted) setState(() { if (mode) { _on = result; } else { _off = result; } });
      } catch (error) {
        if (mounted) setState(() { if (mode) { _onError = 'RAG failed: $error'; } else { _offError = 'LLM failed: $error'; } });
      }
    }
    if (mounted) setState(() { _busy = false; _progress = 'Запрос завершён'; });
  }
  Widget _answer(String title, RagResult? result, String? error) => Card(child: Padding(
    padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (result != null) ...[Text('Вопрос: ${result.question}'), const SizedBox(height: 8), SelectableText(result.answer)],
      if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (result == null && error == null) const Text('Ещё не выполнено'),
    ]),
  ));
  @override
  void dispose() { _question.dispose(); _rag.dispose(); _indexing.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 22 — RAG')),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        ExpansionTile(title: Text(_indexStatus), children: [
          const Text('Day 21 · Structure Aware · embeddinggemma 768 · Top-K = 3'),
          if (_repository.path != null) SelectableText(_repository.path!),
          OutlinedButton(onPressed: _busy ? null : _rebuild, child: const Text('Build/Rebuild Index')),
          const Text('Перестраивает оба индекса Day 21. Для retrieval используется только Structure.'),
        ]),
        if (_questions.isNotEmpty) DropdownButtonFormField<int>(
          initialValue: _selected, key: ValueKey(_selected), isExpanded: true,
          decoration: const InputDecoration(labelText: 'Control questions · 10'),
          items: [for (var i = 0; i < _questions.length; i++) DropdownMenuItem(value: i,
            child: Text('${i + 1}. ${_questions[i]['question']}', maxLines: 2, overflow: TextOverflow.ellipsis))],
          onChanged: _busy ? null : (value) {
            if (value != null) {
              setState(() {
                _selected = value; _question.text = _questions[value]['question'] as String; _clearResults();
              });
            }
          },
        ),
        if (_selected != null && _questions.isNotEmpty)
          ExpansionTile(title: const Text('Expected facts / sources'), initiallyExpanded: true, children: [
            SelectableText('Expected: ${(_questions[_selected!]['expectedFacts'] as List).join('; ')}\n'
              'Sources: ${(_questions[_selected!]['expectedSources'] as List).join('; ')}'),
            const Text('Эталон только для ручного сравнения; не передаётся модели.'),
          ]),
        TextField(controller: _question, enabled: !_busy, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Question'),
          onChanged: (_) => setState(() { _selected = null; _clearResults(); })),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _ask([false]), child: const Text('Without RAG')),
          OutlinedButton(onPressed: _busy ? null : () => _ask([true]), child: const Text('With RAG')),
          FilledButton(onPressed: _busy ? null : () => _ask([false, true]), child: const Text('Compare Both')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        Text(_progress),
        _answer('WITHOUT RAG', _off, _offError),
        _answer('WITH RAG', _on, _onError),
        if (_hits.isNotEmpty) ExpansionTile(title: Text('Retrieved Context · ${_hits.length} sources'), children: [
          const Text('Источники, переданные модели; это не проверка цитирования.'),
          for (final (i, hit) in _hits.indexed) Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText('#${i+1} · ${hit.chunk.metadata['file']}\n'
                'Section: ${hit.chunk.metadata['section']}\nScore: ${hit.score.toStringAsFixed(3)}\n'
                'ID: ${hit.chunk.metadata['chunk_id']}\nSource: ${hit.chunk.metadata['source']}'),
              SelectableText(hit.chunk.metadata['text'] as String),
            ])),
        ]),
      ]),
    ))),
  );
}
