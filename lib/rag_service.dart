import 'dart:convert';
import 'embedding_service.dart';
import 'retrieval_service.dart';
import 'local_llm_client.dart';
import 'llm_configuration.dart';

class GenerationResult {
  const GenerationResult(this.configuration, this.response, this.error, this.elapsed);
  final LlmConfiguration configuration;
  final LlmResponse? response;
  final String? error;
  final Duration elapsed;
}

class RagResult {
  const RagResult(this.sources, this.baseline, this.optimized);
  final List<RetrievedChunk> sources;
  final GenerationResult baseline, optimized;
}

class RagService {
  RagService(this.repository);
  final IndexRepository repository;
  final _embeddings = EmbeddingService();
  final _local = LocalLlmClient();

  Future<GenerationResult> _generate(LlmConfiguration config,
      String question, String context) async {
    final prompt = config.buildPrompt(question, context);
    final watch = Stopwatch()..start();
    try {
      final response = await _local.generate(prompt, config);
      watch.stop();
      return GenerationResult(config, response, null, watch.elapsed);
    } catch (error) {
      watch.stop();
      return GenerationResult(config, null, error.toString(), watch.elapsed);
    }
  }

  Future<RagResult> compare(String question) async {
    question = question.trim();
    if (question.isEmpty) throw StateError('Enter a question before sending.');
    await repository.load();
    final vector = (await _embeddings.embed([question])).single;
    final candidates = RetrievalService().retrieve(vector, repository.chunks,
      topK: RetrievalConfig.topKBefore);
    final sources = RelevanceFilter().apply(candidates)
      .take(RetrievalConfig.topKAfter).toList();
    if (sources.isEmpty) {
      throw StateError('No relevant chunks above the 0.45 threshold. '
        'The available knowledge base does not contain enough information. No generation was sent.');
    }
    // One immutable context snapshot, same source metadata/text for both prompts.
    final context = jsonEncode([for (final hit in sources) hit.chunk.metadata]);
    final baseline = await _generate(LlmConfigurations.baseline, question, context);
    final optimized = await _generate(LlmConfigurations.optimized, question, context);
    return RagResult(sources, baseline, optimized);
  }
}
