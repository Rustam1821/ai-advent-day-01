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
    title: 'Day 24 — Grounded RAG', debugShowCheckedModeBanner: false,
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
  String? _error;
  RagResult? _result;
  final Map<int, RagResult> _runs = {};
  final Map<int, String> _errors = {};
  final Map<int, bool> _meaning = {};

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
  void _clearResults() { _result = null; _error = null; }
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
  Future<void> _ask() async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty) return;
    final selected = _selected;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true; _clearResults();
      if (selected != null) { _runs.remove(selected); _errors.remove(selected); _meaning.remove(selected); }
    });
    try {
      final result = await _rag.answer(question, _updateProgress, (partial) {
        if (mounted) setState(() => _result = partial);
      });
      if (mounted) {
        setState(() { _result = result; if (selected != null) _runs[selected] = result; });
      }
    } catch (error) {
      if (mounted) {
        setState(() { _error = '$error'; if (selected != null) _errors[selected] = '$error'; });
      }
    } finally {
      if (mounted) setState(() { _busy = false; _progress = 'Запрос завершён'; });
    }
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
  Widget _answer() {
    final answer = _result?.answer;
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ANSWER', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const Text('Подтверждённый ответ не получен. Sources / quotes validation: NO.'),
        ] else if (answer != null) ...[
          SelectableText(answer.answer),
          if (answer.isInsufficientContext) ...[
            Text(answer.clarificationRequest!),
            const Text('Недостаточно контекста · Sources: none · Quotes: none\n'
              'Citation checks: N/A — фактический ответ не дан.'),
          ] else ...[
            const SizedBox(height: 12),
            const Text('SOURCES & QUOTES', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final citation in answer.citations) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText('Source: ${citation.source}\nSection: ${citation.section ?? "—"}\n'
                'Chunk: ${citation.chunkId}\nQuote: «${citation.quote}»'),
            ),
            Text('Source present: YES ✓\nQuote present: YES ✓\nQuote exists in chunk: YES ✓\n'
              'Validated citations: ${answer.citations.length}/${answer.citations.length}'),
            const Text('Подлинность цитат проверена кодом. Соответствие смысла ответа проверьте вручную.'),
            if (_selected != null) Wrap(spacing: 8, children: [
              const Text('Answer supported by quotes:'),
              for (final value in [true, false]) ChoiceChip(
                label: Text(value ? 'Yes' : 'No'), selected: _meaning[_selected] == value,
                onSelected: _busy ? null : (_) => setState(() => _meaning[_selected!] = value)),
            ]),
          ],
        ] else const Text('Ещё не выполнено'),
      ]),
    ));
  }
  Widget _evaluation() => ExpansionTile(
    title: Text('Evaluation · ${_runs.length + _errors.length} / ${_questions.length} выполнено'),
    children: [
      const Text('Текущая сессия. Проверка смысла — вручную; автоматического прогона нет.'),
      for (var i = 0; i < _questions.length; i++) ListTile(
        title: Text('${i + 1}. ${_questions[i]['question']}'),
        subtitle: Text(_errors.containsKey(i) ? 'ERROR · Нет подтверждённого ответа' :
          !_runs.containsKey(i) ? 'Не выполнено' :
          _runs[i]!.answer!.isInsufficientContext ?
            'Не знаю · ${_questions[i]['isNegative'] == true ? "Ожидаемый отказ" : "Positive: ответ не получен"} · '
            'Final LLM: ${_runs[i]!.finalLlmRequested ? "requested" : "not called"}' :
            'Sources: YES · Quotes: YES · Quote exists: YES\n'
            'Meaning: ${_meaning[i] == null ? "не проверено" : _meaning[i]! ? "Yes" : "No"}'
            '${_questions[i]['isNegative'] == true ? " · Negative: ожидался отказ" : ""}'),
      ),
    ],
  );
  @override
  void dispose() { _question.dispose(); _rag.dispose(); _indexing.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 24 — Grounded RAG')),
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
                _selected = value; _question.text = _questions[value]['question'] as String;
                _result = _runs[value]; _error = _errors[value];
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
        FilledButton(onPressed: _busy ? null : _ask, child: const Text('Ask')),
        if (_busy) const LinearProgressIndicator(),
        Text(_progress),
        _answer(),
        if (_result != null) ExpansionTile(title: const Text('Retrieval details'), children: [
          SelectableText('Original: ${_result!.question}\nRewritten: ${_result!.rewrittenQuery ?? "—"}'),
          Text('Threshold: ${RetrievalConfig.similarityThreshold} · '
            'Candidates: ${_result!.candidates.length} · Passed: ${_result!.passedThreshold} · '
            'Selected: ${_result!.retrieved.length}\n'
            'Final LLM: ${_result!.finalLlmRequested ? "requested" : "not called"}'),
          _chunks('Candidates', _result!.candidates),
          _chunks('Filtered context', _result!.retrieved),
        ]),
        _evaluation(),
      ]),
    ))),
  );
}
