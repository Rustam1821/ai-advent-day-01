import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'local_llm_config.dart';
import 'llm_configuration.dart';

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LlmResponse {
  const LlmResponse(this.text, this.metrics, this.doneReason);
  final String text;
  final Map<String, int> metrics;
  final String? doneReason;
}

class LocalLlmClient {
  Future<LlmResponse> generate(String prompt, LlmConfiguration configuration) async {
    final input = prompt.trim();
    if (input.isEmpty) {
      throw const LocalLlmException('Enter a prompt before sending.');
    }
    // Each request owns its connection; timeout/disposal closes it.
    final native = HttpClient()..findProxy = (_) => 'DIRECT';
    final client = IOClient(native);
    try {
      configuration.validate();
      final request = http.Request('POST', LocalLlmConfig.endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': configuration.model,
          'prompt': configuration.ollamaTemplate == null ? input :
            configuration.ollamaTemplate!.replaceAll('{{ .Prompt }}', input)
              .replaceAll('{{ .Response }}', ''),
          if (configuration.ollamaTemplate != null) 'raw': true,
          if (configuration.ollamaTemplate != null) 'format': {
            'type': 'object', 'properties': {
              'answer': {'type': 'string'},
            }, 'required': ['answer'], 'additionalProperties': false,
          },
          'stream': false,
          'think': false,
          if (configuration.options.isNotEmpty) 'options': configuration.options,
          // Explicit configurations reject overflow instead of silently trimming context.
          if (configuration.contextWindow != null) 'truncate': false,
          if (configuration.contextWindow != null) 'shift': false,
        });
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(LocalLlmConfig.timeout);
      if (response.statusCode == 404) {
        throw LocalLlmException(
          'Local model unavailable. Run ollama list and make sure '
          '${configuration.model} is installed.',
        );
      }
      if (response.statusCode == 400) {
        throw const LocalLlmException(
          'Ollama rejected the request. Check generation options and context window; '
          'the input or output may exceed the configured context.',
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
      var answer = (data['response'] as String).trim();
      if (configuration.ollamaTemplate != null) {
        if (data['done_reason'] == 'length') {
          throw const LocalLlmException('Optimized output reached its token/context limit before completing JSON.');
        }
        final parsed = jsonDecode(answer);
        if (parsed is! Map || parsed['answer'] is! String) {
          throw const LocalLlmException('Optimized response did not contain a final answer.');
        }
        answer = (parsed['answer'] as String).trim();
      }
      if (answer.isEmpty) {
        throw const LocalLlmException('Ollama returned an empty final answer.');
      }
      // Only final response is displayed; thinking is never consumed.
      final metrics = <String, int>{};
      for (final key in ['total_duration', 'load_duration', 'prompt_eval_duration',
        'eval_duration', 'eval_count', 'prompt_eval_count']) {
        final value = data[key];
        if (value is int && value >= 0) metrics[key] = value;
      }
      return LlmResponse(answer, metrics,
        data['done_reason'] is String ? data['done_reason'] as String : null);
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
