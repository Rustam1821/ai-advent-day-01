import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'local_llm_config.dart';

// Model name matches the metadata and embedding space used in Day 21–25.
class EmbeddingService {
  static const model = 'embeddinggemma';
  static const dimensions = 768;

  Future<List<List<double>>> embed(List<String> texts) async {
    final client = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
    try {
      final request = http.Request('POST', LocalLlmConfig.endpoint.replace(path: '/api/embed'))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'model': model, 'input': texts,
          'dimensions': dimensions, 'truncate': false});
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(LocalLlmConfig.timeout);
      if (response.statusCode == 404) {
        throw StateError('Local embedding model missing. Check embeddinggemma:latest in ollama list.');
      }
      if (response.statusCode != 200) {
        throw StateError('Local embedding request failed: HTTP ${response.statusCode}.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['embeddings'] is! List) {
        throw const FormatException('Malformed embedding response.');
      }
      final vectors = <List<double>>[];
      for (final row in data['embeddings'] as List) {
        if (row is! List || row.any((v) => v is! num)) {
          throw const FormatException('Malformed embedding vector.');
        }
        final vector = row.map((v) => (v as num).toDouble()).toList();
        if (vector.length != dimensions || vector.any((v) => !v.isFinite) ||
            vector.every((v) => v == 0)) {
          throw StateError('Embedding dimension/model mismatch: expected 768 finite nonzero values.');
        }
        vectors.add(vector);
      }
      if (vectors.length != texts.length) {
        throw const FormatException('Embedding count mismatch.');
      }
      return vectors;
    } on TimeoutException {
      throw StateError('Local embeddings timed out after 3 minutes.');
    } on SocketException {
      throw StateError('Cannot connect to local Ollama. Start Ollama and try again.');
    } on http.ClientException {
      throw StateError('Cannot connect to local Ollama. Start Ollama and try again.');
    } on FormatException {
      throw StateError('Malformed local embedding response or configuration.');
    } finally {
      client.close();
    }
  }
  void dispose() {}
}
