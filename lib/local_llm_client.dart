import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'local_llm_config.dart';

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalLlmClient {
  Future<String> generate(String prompt) async {
    final input = prompt.trim();
    if (input.isEmpty) {
      throw const LocalLlmException('Enter a prompt before sending.');
    }
    // Each request owns its connection; timeout/disposal closes it.
    final native = HttpClient()..findProxy = (_) => 'DIRECT';
    final client = IOClient(native);
    try {
      final request = http.Request('POST', LocalLlmConfig.endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': LocalLlmConfig.model,
          'prompt': input,
          'stream': false,
          'think': false,
        });
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(LocalLlmConfig.timeout);
      if (response.statusCode == 404) {
        throw const LocalLlmException(
          'Local model unavailable. Run ollama list and make sure '
          'qwen3:4b is installed.',
        );
      }
      if (response.statusCode != 200) {
        throw LocalLlmException(
          'Ollama returned HTTP ${response.statusCode}. '
          'Check the local Ollama server and try again.',
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> ||
          data['done'] != true || data['response'] is! String) {
        throw const LocalLlmException('Ollama returned an invalid response.');
      }
      final answer = (data['response'] as String).trim();
      if (answer.isEmpty) {
        throw const LocalLlmException('Ollama returned an empty final answer.');
      }
      // Only final response is displayed; thinking is never consumed.
      return answer;
    } on TimeoutException {
      throw const LocalLlmException(
        'Local generation timed out after 3 minutes. Try a shorter prompt.',
      );
    } on SocketException {
      throw const LocalLlmException(
        'Cannot connect to local Ollama. Start Ollama and try again.',
      );
    } on http.ClientException {
      throw const LocalLlmException(
        'Cannot connect to local Ollama. Start Ollama and try again.',
      );
    } on FormatException {
      throw const LocalLlmException(
        'Invalid local configuration or malformed Ollama JSON response.',
      );
    } finally {
      client.close();
    }
  }
}
