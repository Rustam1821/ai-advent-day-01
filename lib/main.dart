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
    title: 'Day 23 — Improved RAG', debugShowCheckedModeBanner: false,
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
  String? _baseError, _improvedError;
  RagResult? _base, _improved;

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
  void _clearResults() { _base = _improved = null; _baseError = _improvedError = null; }
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
  Future<void> _ask(List<RagMode> modes) async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      for (final mode in modes) {
        if (mode == RagMode.improved) { _improved = null; _improvedError = null; }
        else { _base = null; _baseError = null; }
      }
    });
    for (final mode in modes) {
      if (!mounted) { break; }
      try {
        final result = await _rag.answer(question, mode, _updateProgress, (partial) {
          if (mounted) {
            setState(() {
              if (mode == RagMode.improved) { _improved = partial; } else { _base = partial; }
            });
          }
        });
        if (mounted) setState(() { if (mode == RagMode.improved) { _improved = result; } else { _base = result; } });
      } catch (error) {
        if (mounted) setState(() { if (mode == RagMode.improved) { _improvedError = 'RAG failed: $error'; } else { _baseError = 'BASE failed: $error'; } });
      }
    }
    if (mounted) setState(() { _busy = false; _progress = 'Запрос завершён'; });
  }
  Widget _chunks(String title, List<RetrievedChunk> hits) => ExpansionTile(
    title: Text('$title · ${hits.length}'),
    children: [for (final (i, hit) in hits.indexed) Padding(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText('#${i + 1} · ${hit.chunk.metadata['file']}\n'
          'Section: ${hit.chunk.metadata['section']} · Score: ${hit.score.toStringAsFixed(3)}\n'
          'ID: ${hit.chunk.metadata['chunk_id']}\nSource: ${hit.chunk.metadata['source']}'),
        Text(hit.chunk.metadata['text'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
      ]),
    )],
  );
  Widget _answer(String title, RagResult? result, String? error) => Card(child: Padding(
    padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (result != null) ...[
        SelectableText('Original query: ${result.question}'),
        if (result.mode == RagMode.improved) ...[
          SelectableText('Rewritten query: ${result.rewrittenQuery ?? "ещё не получен"}'),
          const Text('Similarity relevance filter · Threshold: ${RetrievalConfig.similarityThreshold}'),
          if (result.candidates.isNotEmpty) ...[
            Text('Candidates: ${result.candidates.length} / max ${RetrievalConfig.topKBefore} · '
              'Passed threshold: ${result.passedThreshold} · '
              'Selected for LLM: ${result.retrieved.length} / max ${RetrievalConfig.topKAfter}'),
            _chunks('BEFORE FILTER', result.candidates),
            _chunks('AFTER FILTER', result.retrieved),
          ],
        ] else if (result.candidates.isNotEmpty) ...[
          Text('Retrieved / selected for LLM: ${result.retrieved.length}'),
          _chunks('BASE retrieved chunks', result.retrieved),
        ],
        if (result.answer != null) SelectableText(result.answer!),
      ],
      if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (result == null && error == null) const Text('Ещё не выполнено'),
    ]),
  ));
  @override
  void dispose() { _question.dispose(); _rag.dispose(); _indexing.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 23 — Improved RAG')),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        ExpansionTile(title: Text(_indexStatus), children: [
          const Text('Day 21 · Structure Aware · embeddinggemma 768'),
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
          OutlinedButton(onPressed: _busy ? null : () => _ask([RagMode.base]), child: const Text('Run BASE')),
          OutlinedButton(onPressed: _busy ? null : () => _ask([RagMode.improved]), child: const Text('Run IMPROVED')),
          FilledButton(onPressed: _busy ? null : () => _ask([RagMode.base, RagMode.improved]), child: const Text('Compare BASE vs IMPROVED')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        Text(_progress),
        _answer('BASE RAG', _base, _baseError),
        _answer('IMPROVED RAG', _improved, _improvedError),
      ]),
    ))),
  );
}
