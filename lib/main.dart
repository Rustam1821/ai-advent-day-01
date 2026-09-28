import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'documents.dart';
import 'embedding_service.dart';
import 'indexing_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 21 · Document Indexing', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)), useMaterial3: true),
    home: const IndexingPage(),
  );
}

class IndexingPage extends StatefulWidget {
  const IndexingPage({super.key});
  @override
  State<IndexingPage> createState() => _IndexingPageState();
}

class _IndexingPageState extends State<IndexingPage> {
  final _service = IndexingService();
  List<Document> _documents = [];
  List<IndexResult> _results = [];
  String _progress = 'Loading documents…';
  String? _error;
  bool _busy = true;
  int _words = 0;
  final _selected = <String, int>{};

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final docs = await DocumentLoader().load();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _words = docs.fold(0, (sum, doc) => sum + RegExp(r'\S+').allMatches(doc.content).length);
      });
      final saved = await _service.restore();
      if (!mounted) return;
      setState(() {
        _results = saved;
        _progress = saved.isEmpty ? 'Ready' : 'Сохранённые индексы прочитаны с диска';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка загрузки: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _build() async {
    setState(() { _busy = true; _error = null; _progress = 'Loading documents…'; });
    try {
      // One immutable corpus snapshot is used for both strategies.
      final docs = await DocumentLoader().load();
      final results = await _service.build(docs, (message) {
        if (mounted) setState(() => _progress = message);
      });
      if (mounted) {
        setState(() {
          _documents = docs;
          _results = results;
          _selected.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Индексация остановлена: $error';
          _progress = 'Failed · прежние завершённые индексы сохранены';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _service.dispose(); super.dispose(); }

  Widget _result(IndexResult result) {
    final strategy = result.data['strategy'] as String;
    final index = (_selected[strategy] ?? 0).clamp(0, result.chunks.length - 1);
    final chunk = result.chunks[index] as Map;
    final text = chunk['text'] as String;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strategy == 'fixed' ? 'FIXED SIZE' : 'STRUCTURE AWARE', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SelectableText('Saved: ${result.path}'),
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: result.path)),
          icon: const Icon(Icons.copy, size: 16), label: const Text('Копировать путь'),
        ),
        Row(children: [
          IconButton(onPressed: index > 0 ? () => setState(() => _selected[strategy] = index - 1) : null,
            icon: const Icon(Icons.chevron_left)),
          Text('Chunk ${index + 1} / ${result.chunks.length}'),
          IconButton(onPressed: index + 1 < result.chunks.length ? () => setState(() => _selected[strategy] = index + 1) : null,
            icon: const Icon(Icons.chevron_right)),
        ]),
        SelectableText('ID: ${chunk['chunk_id']}\nFile: ${chunk['file']}\n'
            'Section: ${chunk['section'] ?? 'unknown'}\nLength: ${text.length}\n'
            'Embedding dimensions: ${(chunk['embedding'] as List).length}'),
        const SizedBox(height: 8),
        SelectableText(text.length > 700 ? '${text.substring(0, 700)}…' : text),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 21 · Document Indexing')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Documents: ${_documents.length} · Words: $_words\n'
            'Estimated pages: ${(_words / 500).toStringAsFixed(1)} (500 words/page)'),
        const Text('Corpus: The Rust Programming Language · MIT\n'
            'Fixed: 1200 chars / overlap 150\nStructure: headings + paragraphs, max 1200 chars'),
        const SizedBox(height: 8),
        const Text('Embeddings: Ollama / embeddinggemma · 768 dimensions'),
        const SelectableText(EmbeddingService.baseUrl),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy || _documents.isEmpty ? null : _build,
          child: const Text('Build & Compare Both')),
        if (_documents.isEmpty && !_busy)
          TextButton(onPressed: () { setState(() { _busy = true; _error = null; }); _load(); },
              child: const Text('Повторить загрузку документов')),
        if (_busy) const LinearProgressIndicator(),
        Text(_progress),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_results.length == 2) ...[
          const SizedBox(height: 16),
          const Text('Сравнение одного corpus · длина в символах UTF-16'),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
            columns: const [DataColumn(label: Text('Metric')), DataColumn(label: Text('Fixed')), DataColumn(label: Text('Structure'))],
            rows: [for (final key in ['documents', 'chunks', 'averageLength', 'minimumLength', 'maximumLength', 'sectionsPreserved'])
              DataRow(cells: [DataCell(Text(key)), for (final result in _results)
                DataCell(Text(result.stats[key] is double ? (result.stats[key] as double).toStringAsFixed(1) : '${result.stats[key]}'))])],
          )),
          for (final result in _results) _result(result),
        ],
      ]),
    ))),
  );
}
