import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Only the explicit comparison action uses this provider.
class CloudLlmClient {
  static const key = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const model = String.fromEnvironment('DEEPSEEK_MODEL', defaultValue: 'deepseek-flash');
  static bool get available => key.trim().isNotEmpty;

  Future<String> generate(String prompt) async {
    if (!available) throw StateError('Cloud comparison needs DEEPSEEK_API_KEY. Local RAG does not.');
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('https://api.deepseek.com/chat/completions'))
        ..followRedirects = false
        ..headers.addAll({'Authorization': 'Bearer $key', 'Content-Type': 'application/json'})
        ..body = jsonEncode({
          'model': model, 'temperature': 0.2, 'max_tokens': 1000,
          'stream': false, 'thinking': {'type': 'disabled'},
          'messages': [{'role': 'user', 'content': prompt}],
        });
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        throw StateError('DeepSeek HTTP ${response.statusCode}. Check key, balance and model.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      final choice = (data['choices'] as List).first as Map;
      if (choice['finish_reason'] != 'stop') {
        throw StateError('DeepSeek did not return a complete answer.');
      }
      final answer = (choice['message'] as Map)['content'];
      if (answer is! String || answer.trim().isEmpty) throw const FormatException();
      return answer.trim();
    } on TimeoutException {
      throw StateError('Cloud generation timed out after 3 minutes.');
    } on http.ClientException {
      throw StateError('Cannot connect to DeepSeek. Local RAG remains available.');
    } on FormatException {
      throw StateError('Malformed DeepSeek response.');
    } on TypeError {
      throw StateError('Invalid DeepSeek response structure.');
    } on RangeError {
      throw StateError('Empty DeepSeek response.');
    } finally {
      client.close();
    }
  }
}
