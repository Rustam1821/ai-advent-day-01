import 'package:flutter/material.dart';
import 'cloud_llm_client.dart';
import 'documents.dart';
import 'embedding_service.dart';
import 'indexing_service.dart';
import 'local_llm_config.dart';
import 'rag_service.dart';
import 'retrieval_service.dart';

void main() => runApp(const LocalRagApp());

class LocalRagApp extends StatelessWidget {
  const LocalRagApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Day 28 — Local RAG', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)), useMaterial3: true),
    home: const LocalRagPage(),
  );
}

class LocalRagPage extends StatefulWidget {
  const LocalRagPage({super.key});
  @override
  State<LocalRagPage> createState() => _LocalRagPageState();
}

class _LocalRagPageState extends State<LocalRagPage> {
  final _input = TextEditingController();
  final _storage = IndexingService();
  late final _repository = IndexRepository(_storage);
  late final _rag = RagService(_repository);
  bool _busy = true;
  String _indexStatus = 'Loading local index…';
  String _activity = '';
  String? _error;
  RagResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _repository.load();
      if (mounted) setState(() => _indexStatus = 'Index ready: ${_repository.chunks.length} chunks\n${_repository.path}');
    } catch (error) {
      if (mounted) setState(() => _indexStatus = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _build() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _result = null; _activity = 'Building local index…'; });
    try {
      await _storage.build(await DocumentLoader().load(), (progress) {
        if (mounted) setState(() => _activity = progress);
      });
      await _repository.load();
      if (mounted) setState(() => _indexStatus = 'Index ready: ${_repository.chunks.length} chunks\n${_repository.path}');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() { _busy = false; _activity = ''; });
    }
  }

  Future<void> _ask({bool compare = false}) async {
    if (_busy) return;
    if (_input.text.trim().isEmpty) {
      setState(() => _error = 'Enter a question before sending.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true; _error = null; _result = null;
      _activity = compare ? 'Retrieving once, then generating Local and Cloud answers…' : 'Local retrieval and generation…';
    });
    try {
      final result = await _rag.ask(_input.text, compare: compare);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() { _busy = false; _activity = ''; });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _storage.dispose();
    super.dispose();
  }

  Widget _answer(String label, GenerationResult answer) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.titleLarge),
        Text('${answer.error == null ? 'Generation' : 'Failed after'}: ${(answer.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s'),
        const SizedBox(height: 10),
        SelectableText(answer.text ?? answer.error!, style: answer.error == null ? null : TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 28 — Local RAG')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SelectableText('Mode: LOCAL RAG\nRetrieval: Local\nGenerator: Ollama / ${LocalLlmConfig.model}\nEmbedding: ${EmbeddingService.model}:latest (768)\nEndpoint: ${LocalLlmConfig.baseUrl}'),
          const SizedBox(height: 12),
          SelectableText(_indexStatus),
          TextButton(onPressed: _busy ? null : _build, child: const Text('Build / Rebuild Local Index')),
          const SizedBox(height: 16),
          TextField(controller: _input, enabled: !_busy, minLines: 2, maxLines: 6,
            decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : () => _ask(), child: const Text('Ask Local')),
          OutlinedButton(onPressed: _busy || !CloudLlmClient.available ? null : () => _ask(compare: true),
            child: const Text('Compare Local vs Cloud')),
          Text(CloudLlmClient.available
            ? 'Comparison sends the same retrieved context to DeepSeek / ${CloudLlmClient.model}.'
            : 'Cloud comparison unavailable: no DEEPSEEK_API_KEY. Ask Local works without it.'),
          if (_busy) ...[const SizedBox(height: 16), const LinearProgressIndicator(), Text(_activity)],
          if (_error != null) ...[const SizedBox(height: 16), SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          if (_result != null) ...[
            const SizedBox(height: 20),
            _answer('LOCAL — ${LocalLlmConfig.model}', _result!.local),
            if (_result!.cloud != null) _answer('CLOUD — ${CloudLlmClient.model}', _result!.cloud!),
            const SizedBox(height: 16),
            Text('Retrieved sources (shared context)', style: Theme.of(context).textTheme.titleLarge),
            const Text('These chunks were provided to generation; they are not verified citations.'),
            for (final hit in _result!.sources) ExpansionTile(
              title: Text(hit.chunk.metadata['source'] as String),
              subtitle: Text('${hit.chunk.metadata['section'] ?? 'No section'}\n${hit.chunk.metadata['chunk_id']} · score ${hit.score.toStringAsFixed(3)}'),
              children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(hit.chunk.metadata['text'] as String))],
            ),
          ],
        ]),
      )),
    )),
  );
}
