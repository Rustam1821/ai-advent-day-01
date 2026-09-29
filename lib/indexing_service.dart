import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'documents.dart';
import 'embedding_service.dart';

class IndexResult {
  IndexResult(this.data, this.path);
  final Map<String, dynamic> data;
  final String path;
  Map get stats => data['statistics'] as Map;
  List get chunks => data['chunks'] as List;
}

class IndexingService {
  final embeddings = EmbeddingService();
  Future<Directory> _directory() async => Directory('${(await getApplicationDocumentsDirectory()).path}/day21');

  Future<void> _write(File file, Object value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }

  Future<List<IndexResult>> restore({String? strategy}) async {
    final root = await _directory();
    final pointer = File('${root.path}/current.json');
    if (!await pointer.exists()) return [];
    final run = (jsonDecode(await pointer.readAsString()) as Map)['run'] as String;
    if (!RegExp(r'^run_[0-9]+$').hasMatch(run)) throw const FormatException('Invalid index location');
    final results = <IndexResult>[];
    for (final selected in strategy == null ? ['fixed', 'structure'] : [strategy]) {
      final file = File('${root.path}/$run/index_$selected.json');
      results.add(IndexResult(Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map), file.path));
    }
    return results;
  }

  Future<List<IndexResult>> build(List<Document> documents, void Function(String) progress) async {
    if (documents.isEmpty) throw StateError('Нет документов для индексации.');
    final root = await _directory();
    final run = 'run_${DateTime.now().microsecondsSinceEpoch}';
    final hash = sha256.convert(utf8.encode(jsonEncode([
      for (final doc in documents) {'file': doc.file, 'content': doc.content},
    ]))).toString();
    final results = <IndexResult>[];
    for (final chunker in <Chunker>[FixedSizeChunker(), StructureAwareChunker()]) {
      progress('${chunker.name}: Chunking…');
      final chunks = [for (final doc in documents) ...chunker.split(doc)];
      if (chunks.isEmpty) throw StateError('Chunker не создал chunks.');
      final indexed = <Map<String, dynamic>>[];
      for (var start = 0; start < chunks.length; start += 8) {
        final batch = chunks.sublist(start, (start + 8).clamp(0, chunks.length));
        progress('${chunker.name}: Generating embeddings ${indexed.length} / ${chunks.length}');
        final vectors = await embeddings.embed(batch.map((c) => c.text).toList());
        for (var i = 0; i < batch.length; i++) { indexed.add(batch[i].toJson(vectors[i])); }
        progress('${chunker.name}: Generating embeddings ${indexed.length} / ${chunks.length}');
      }
      final lengths = chunks.map((c) => c.text.length).toList()..sort();
      final stats = {
        'documents': documents.length, 'chunks': chunks.length,
        'averageLength': lengths.reduce((a, b) => a + b) / lengths.length,
        'minimumLength': lengths.first, 'maximumLength': lengths.last,
        'sectionsPreserved': chunks.where((c) => c.section != null && c.section != 'Preamble').length,
      };
      final data = <String, dynamic>{
        'version': 1, 'strategy': chunker.name, 'corpusSha256': hash,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'embeddingProvider': 'Ollama', 'embeddingModel': EmbeddingService.model,
        'embeddingDimensions': EmbeddingService.dimensions,
        'chunkSize': 1200, 'overlap': chunker.name == 'fixed' ? 150 : 0,
        'statistics': stats, 'chunks': indexed,
      };
      progress('${chunker.name}: Saving index…');
      final file = File('${root.path}/$run/index_${chunker.name}.json');
      await _write(file, data);
      results.add(IndexResult(data, file.path));
    }
    // Publish comparison only when both indexes for the same corpus are saved.
    await _write(File('${root.path}/current.json'), {'run': run});
    progress('Done · оба индекса сохранены');
    return results;
  }
  void dispose() => embeddings.dispose();
}
