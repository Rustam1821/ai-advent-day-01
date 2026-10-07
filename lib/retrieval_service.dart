import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'documents.dart';
import 'embedding_service.dart';
import 'indexing_service.dart';

class IndexedChunk {
  IndexedChunk(this.metadata, this.vector);
  final Map<String, dynamic> metadata;
  final List<double> vector;
}
class RetrievedChunk {
  RetrievedChunk(this.chunk, this.score);
  final IndexedChunk chunk;
  final double score;
}

class IndexRepository {
  IndexRepository(this.storage);
  final IndexingService storage;
  List<IndexedChunk> chunks = [];
  String? path;
  Future<void> load() async {
    chunks = []; path = null;
    try {
      final saved = await storage.restore(strategy: 'structure');
      if (saved.isEmpty) throw StateError('Local RAG index not found. Build the index first.');
      final result = saved.single;
      final data = result.data;
      if (data['version'] != 1 || data['strategy'] != 'structure' || data['embeddingProvider'] != 'Ollama' ||
          data['embeddingModel'] != EmbeddingService.model || data['embeddingDimensions'] != EmbeddingService.dimensions) {
        throw StateError('Несовместимая модель/размерность индекса. Нужен Rebuild Index.');
      }
      final docs = await DocumentLoader().load();
      final hash = sha256.convert(utf8.encode(jsonEncode([
        for (final doc in docs) {'file': doc.file, 'content': doc.content},
      ]))).toString();
      if (data['corpusSha256'] != hash) throw StateError('Corpus изменён. Нажмите Build/Rebuild Index для новых документов.');
      final loaded = <IndexedChunk>[];
      final ids = <String>{};
      for (final raw in result.chunks) {
        final m = Map<String, dynamic>.from(raw as Map);
        for (final key in ['chunk_id','source','file','title','text']) {
          if (m[key] is! String || (m[key] as String).trim().isEmpty) throw const FormatException('Повреждённые metadata');
        }
        if (!ids.add(m['chunk_id'] as String) || (m['section'] != null && m['section'] is! String)) {
          throw const FormatException('Повреждённые metadata');
        }
        final vector = (m.remove('embedding') as List).map((n) => (n as num).toDouble()).toList();
        if (vector.length != EmbeddingService.dimensions || vector.any((v) => !v.isFinite) || vector.every((v) => v == 0)) {
          throw const FormatException('Некорректный vector или несовпадение размерностей');
        }
        loaded.add(IndexedChunk(m, vector));
      }
      if (loaded.isEmpty) throw StateError('Index пуст. Нажмите Rebuild Index.');
      chunks = loaded; path = result.path;
    } on StateError { rethrow; }
    catch (error) { throw StateError('Индекс не прочитан или повреждён: $error. Выполните Rebuild Index.'); }
  }
}

class RetrievalService {
  double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) throw StateError('Embedding dimensions mismatch.');
    double dot = 0, aa = 0, bb = 0;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].isFinite || !b[i].isFinite) throw StateError('Invalid vector.');
      dot += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i];
    }
    if (aa == 0 || bb == 0) throw StateError('Zero vector.');
    return (dot / (sqrt(aa) * sqrt(bb))).clamp(-1.0, 1.0);
  }
  List<RetrievedChunk> retrieve(List<double> query, List<IndexedChunk> chunks, {required int topK}) {
    final ranked = chunks.map((c) => RetrievedChunk(c, cosine(query, c.vector))).toList()
      ..sort((a,b) { final score = b.score.compareTo(a.score); return score != 0 ? score : (a.chunk.metadata['chunk_id'] as String).compareTo(b.chunk.metadata['chunk_id'] as String); });
    if (ranked.isEmpty) throw StateError('Нет пригодных chunks для retrieval.');
    return ranked.take(topK).toList();
  }
}

// Calibrated on the local embeddinggemma index: relevant retry query ~0.58;
// out-of-corpus Titan question ~0.21. Keep a shared relevance guard.
class RetrievalConfig {
  static const topKBefore = 8;
  static const topKAfter = 3;
  static const similarityThreshold = 0.45;
}

class RelevanceFilter {
  List<RetrievedChunk> apply(List<RetrievedChunk> candidates) => candidates
      .where((hit) => hit.score >= RetrievalConfig.similarityThreshold).toList();
}
