import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'llm_configuration.dart';
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
    title: 'Day 29 — Local LLM Optimization', debugShowCheckedModeBanner: false,
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

  Future<void> _ask() async {
    if (_busy) return;
    if (_input.text.trim().isEmpty) {
      setState(() => _error = 'Enter a question before sending.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true; _error = null; _result = null;
      _activity = 'Retrieving once, then generating BASELINE and OPTIMIZED…';
    });
    try {
      if (kDebugMode) debugPrint('[DAY29] Comparison started');
      final result = await _rag.compare(_input.text);
      _logComparison(_input.text.trim(), result);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (kDebugMode) debugPrint('[DAY29] Comparison failed: $error');
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

  void _logComparison(String question, RagResult result) {
    if (!kDebugMode) return;
    Map<String, Object?> generation(GenerationResult value) => {
      'configuration': value.configuration.label,
      'model': value.configuration.model,
      'options_sent': value.configuration.options,
      'omitted_options': 'Inherited from model/runtime, not measured effective values',
      'prompt_template': value.configuration.promptTemplate.name,
      'ollama_template_override': value.configuration.ollamaTemplate,
      'raw_qwen_format': value.configuration.ollamaTemplate != null,
      'structured_answer_json': value.configuration.ollamaTemplate != null,
      'generation_seconds': value.elapsed.inMicroseconds / 1000000,
      'answer': value.response?.text,
      'error': value.error,
      'done_reason': value.response?.doneReason,
      'ollama_metrics_raw_ns_and_counts': value.response?.metrics,
    };
    final report = {
      'question': question,
      'baseline': generation(result.baseline),
      'optimized': generation(result.optimized),
      'shared_retrieved_sources': [
        for (final hit in result.sources) {
          ...hit.chunk.metadata,
          'similarity': hit.score,
        },
      ],
    };
    debugPrint('[DAY29] BEGIN COMPARISON RESULT');
    debugPrint(const JsonEncoder.withIndent('  ').convert(report), wrapWidth: 180);
    debugPrint('[DAY29] END COMPARISON RESULT');
  }

  Widget _answer(GenerationResult answer) {
    final config = answer.configuration;
    final response = answer.response;
    final metrics = response?.metrics ?? <String, int>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(config.label, style: Theme.of(context).textTheme.titleLarge),
          SelectableText('Model: ${config.model}\n'
            'Temperature: ${config.temperature ?? "Inherited (installed qwen3:4b: 0.6)"}\n'
            'Max output tokens: ${config.maxOutputTokens ?? "Inherited (Ollama default: -1, unlimited)"}\n'
            'Context window: ${config.contextWindow ?? "Runtime-selected / server override"}\n'
            'Prompt: ${config.promptTemplate == RagPromptTemplate.general ? "General RAG (Day 28)" : "Technical RAG (experimental)"}'),
          if (config.ollamaTemplate != null) const Text('Qwen format: raw + structured final answer'),
          const SizedBox(height: 10),
          Text('${answer.error == null ? "Generation time" : "Failed after"}: ${(answer.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} s'),
          for (final entry in metrics.entries)
            Text('${entry.key}: ${entry.key.endsWith("duration") ? "${(entry.value / 1000000000).toStringAsFixed(3)} s" : entry.value}'),
          if (response?.doneReason != null) Text('Stop reason: ${response!.doneReason}'),
          if (response?.doneReason == 'length')
            Text('Output stopped at a token/context limit; it may be incomplete.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 10),
          SelectableText(response?.text ?? answer.error!, style: answer.error == null ? null : TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 29 — Local LLM Optimization')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExpansionTile(
            title: const Text('Details'),
            initiallyExpanded: false,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SelectableText('Provider: Ollama\nModel: ${LocalLlmConfig.model}\nTask: Local RAG\nRetrieval: Local\nEmbedding: ${EmbeddingService.model}:latest (768)\nEndpoint: ${LocalLlmConfig.baseUrl}'),
          const SizedBox(height: 12),
          SelectableText(_indexStatus),
          TextButton(onPressed: _busy ? null : _build, child: const Text('Build / Rebuild Local Index')),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _input, enabled: !_busy, minLines: 2, maxLines: 6,
            decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _ask, child: const Text('Compare')),
          const Text('BASELINE → OPTIMIZED, sequentially, with one shared retrieval. '
            'OPTIMIZED is an experimental configuration, not a proven improvement.'),
          if (_busy) ...[const SizedBox(height: 16), const LinearProgressIndicator(), Text(_activity)],
          if (_error != null) ...[const SizedBox(height: 16), SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          if (_result != null) ...[
            const SizedBox(height: 20),
            _answer(_result!.baseline),
            _answer(_result!.optimized),
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
