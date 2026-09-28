import 'dart:convert';
import 'package:http/http.dart' as http;

class EmbeddingService {
  static const model = 'embeddinggemma';
  static const dimensions = 768;
  static const baseUrl = String.fromEnvironment('EMBEDDING_URL', defaultValue: 'http://127.0.0.1:11434');
  final _client = http.Client();

  Future<List<List<double>>> embed(List<String> texts) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/embed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model, 'input': texts, 'dimensions': dimensions, 'truncate': false}),
    ).timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw StateError('Ollama HTTP ${response.statusCode}. Убедитесь, что Ollama запущена и выполнено ollama pull $model.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final vectors = (data['embeddings'] as List).map((row) =>
        (row as List).map((v) => (v as num).toDouble()).toList()).toList();
    if (vectors.length != texts.length || vectors.any((v) =>
        v.length != dimensions || v.any((n) => !n.isFinite) || v.every((n) => n == 0))) {
      throw const FormatException('Некорректные embedding vectors от Ollama.');
    }
    return vectors;
  }
  void dispose() => _client.close();
}
