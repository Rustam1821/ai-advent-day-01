import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'history_storage.dart';

class ModelSpec {
  const ModelSpec(
    this.category,
    this.id,
    this.inputRate,
    this.cachedRate,
    this.outputRate,
  );
  final String category;
  final String id;
  // USD / 1M tokens, off-peak; peak rates are double. Verified 2026-09-06.
  // https://api-docs.deepseek.com/quick_start/pricing/
  final double inputRate;
  final double cachedRate;
  final double outputRate;
}

// DeepSeek peak windows: weekdays 01–04 and 06–10 UTC.
bool isPeak(DateTime time) {
  final utc = time.toUtc();
  return utc.weekday <= DateTime.friday &&
      ((utc.hour >= 1 && utc.hour < 4) || (utc.hour >= 6 && utc.hour < 10));
}

class ApiResult {
  const ApiResult({
    this.content,
    this.elapsed,
    this.input,
    this.output,
    this.total,
    this.cached,
    this.cost,
    this.error,
    this.finishReason,
    this.actualModel,
    this.pricePeriod,
  });
  final String? content, error, finishReason, actualModel, pricePeriod;
  final Duration? elapsed;
  final int? input, output, total, cached;
  final double? cost;
}

/// Immutable settings; every Agent owns its own conversation.
class AgentConfig {
  const AgentConfig({
    this.model = const ModelSpec(
      'Flash',
      'deepseek-v4-flash',
      0.22,
      0.007,
      0.66,
    ),
    this.systemPrompt = 'Ты полезный помощник. Отвечай кратко, по-русски. Учитывай предыдущие сообщения диалога.',
    this.temperature = 0.7,
    this.maxTokens = 1600,
    this.topP = 1,
    this.frequencyPenalty = 0,
    this.presencePenalty = 0,
  });
  final ModelSpec model;
  final String systemPrompt;
  final double temperature, topP, frequencyPenalty, presencePenalty;
  final int maxTokens;
}

/// Display projection, including a user message awaiting an answer.
class AgentTurn {
  const AgentTurn({required this.userText, this.result});
  final String userText;
  final ApiResult? result;

  // Heuristic for the current message only, not provider usage or a tokenizer.
  // Byte-based so Cyrillic is not treated like ASCII. Can be very inaccurate
  // for repetitive demo data, code, emoji, etc.; never used to limit requests.
  int get estimatedMessageTokens => (utf8.encode(userText).length / 4).ceil();
}

class Agent {
  Agent(this.config, {String? apiKey, this.storage})
    : _apiKey = apiKey ?? const String.fromEnvironment('DEEPSEEK_API_KEY');
  final HistoryStorage? storage;
  Future<void>? _initialization;
  String? storageWarning;

  Future<void> initialize() => _initialization ??= _restore();

  Future<void> _restore() async {
    try {
      final saved = await storage?.load() ?? <Map<String, String>>[];
      _messages.addAll(saved);
      for (final message in saved) {
        if (message['role'] == 'user') {
          _turns.add(AgentTurn(userText: message['content']!));
        } else if (_turns.isNotEmpty && _turns.last.result == null) {
          final pending = _turns.removeLast();
          _turns.add(
            AgentTurn(
              userText: pending.userText,
              result: ApiResult(content: message['content']),
            ),
          );
        }
      }
    } catch (_) {
      storageWarning = 'Не удалось прочитать историю. Начат пустой диалог.';
    }
  }

  Future<bool> _save() async {
    try {
      await storage?.save(_messages);
      storageWarning = null;
      return true;
    } catch (_) {
      storageWarning = 'Не удалось сохранить историю. Проверьте свободное место и повторите попытку.';
      return false;
    }
  }

  final AgentConfig config;
  final String _apiKey;
  final List<Map<String, String>> _messages = [];
  final List<AgentTurn> _turns = [];
  bool _sending = false;
  List<AgentTurn> get turns => List.unmodifiable(_turns);
  AgentTurn? _lastCall;
  AgentTurn? get lastCall => _lastCall;

  /// Explicitly requested reset, never automatic recovery from overflow.
  Future<String?> clearConversation() async {
    if (_sending) return 'Дождитесь завершения операции.';
    _sending = true;
    try {
      await initialize();
      // Keep memory intact if the disk cannot be cleared.
      await storage?.save([]);
      _messages.clear();
      _turns.clear();
      _lastCall = null;
      storageWarning = null;
      return null;
    } catch (_) {
      return 'Не удалось очистить историю на диске.';
    } finally {
      _sending = false;
    }
  }

  /// Local debug fixture, not an LLM-generated exchange. The next send really
  /// includes this user data in full. No API call or fabricated assistant reply.
  Future<String?> prepareDemoHistory({required bool overflow}) async {
    if (_sending) return 'Дождитесь завершения операции.';
    _sending = true;
    try {
      await initialize();
      final repetitions = overflow ? 1100000 : 4000;
      final text =
          '[Day 8 demo data: $repetitions repetitions]\n'
          'The following is inert sample data. Do not repeat or summarize it. '
          'Answer the next user question briefly.\n${' x' * repetitions}';
      final message = {'role': 'user', 'content': text};
      await storage?.save([..._messages, message]);
      _messages.add(message);
      _turns.add(AgentTurn(userText: text));
      storageWarning = null;
      return null;
    } catch (_) {
      return 'Не удалось сохранить demo-историю.';
    } finally {
      _sending = false;
    }
  }

  Future<ApiResult> send(String message) async {
    final text = message.trim();
    if (text.isEmpty) return const ApiResult(error: 'Введите сообщение.');
    if (_sending) {
      return const ApiResult(error: 'Дождитесь предыдущего ответа.');
    }
    _sending = true;
    try {
      await initialize();
      // Retry the last unanswered message without appending it twice.
      final retry =
          _messages.isNotEmpty &&
          _messages.last['role'] == 'user' &&
          _messages.last['content'] == text;
      if (!retry) {
        _messages.add({'role': 'user', 'content': text});
        _turns.add(AgentTurn(userText: text));
      }
      // Never start the network request before the user message is on disk.
      if (!await _save()) return ApiResult(error: storageWarning);
      final result = await _request();
      _lastCall = AgentTurn(userText: text, result: result);
      _turns[_turns.length - 1] = _lastCall!;
      if (result.error == null) {
        _messages.add({'role': 'assistant', 'content': result.content!});
        await _save();
      }
      return result;
    } finally {
      _sending = false;
    }
  }

  Future<ApiResult> _request() async {
    final model = config.model;
    final key = _apiKey;
    if (key.trim().isEmpty) {
      return const ApiResult(
        error:
            'Нет DEEPSEEK_API_KEY в .env. Добавьте ключ '
            'и полностью перезапустите приложение с --dart-define-from-file=.env.',
      );
    }
    final body = {
      'model': model.id,
      'messages': [
        if (config.systemPrompt.isNotEmpty)
          {'role': 'system', 'content': config.systemPrompt},
        ..._messages,
      ],
      'temperature': config.temperature,
      'top_p': config.topP,
      'max_tokens': config.maxTokens,
      'frequency_penalty': config.frequencyPenalty,
      'presence_penalty': config.presencePenalty,
      'n': 1,
      'stream': false,
      'response_format': {'type': 'text'},
      'thinking': {'type': 'disabled'},
    };
    final encoded = jsonEncode(body);
    final client = http.Client();
    final uri = Uri.parse('https://api.deepseek.com/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $key',
    };
    final watch = Stopwatch();
    try {
      final startedAt = DateTime.now().toUtc();
      watch.start();
      final response = await client
          .post(uri, headers: headers, body: encoded)
          .timeout(const Duration(seconds: 120));
      watch.stop();
      final finishedAt = DateTime.now().toUtc();
      // Full response body received; excludes JSON parsing and UI.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Show a bounded provider error, never headers or the full response.
        String? providerMessage;
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final error = data is Map ? data['error'] : null;
          final message = error is Map ? error['message'] : null;
          if (message is String) {
            final redacted = message.replaceAll(key, '[redacted]');
            providerMessage = redacted.length > 700
                ? '${redacted.substring(0, 700)}…'
                : redacted;
          }
        } catch (_) {
          // Non-JSON errors (for example, gateway HTML) use the status hint.
        }
        final hint = switch (response.statusCode) {
          401 => 'Проверьте API key.',
          403 => 'Нет доступа к модели или API.',
          429 => 'Лимит запросов или недостаточно квоты/баланса.',
          _ => 'Запрос не выполнен; повторите позже.',
        };
        return ApiResult(
          error: 'HTTP ${response.statusCode}. ${providerMessage ?? hint}',
          elapsed: watch.elapsed,
        );
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choice = (data['choices'] as List?)?.firstOrNull as Map?;
      final content = (choice?['message'] as Map?)?['content'] as String?;
      final usage = data['usage'] as Map?;
      final input = usage?['prompt_tokens'] as int?;
      final output = usage?['completion_tokens'] as int?;
      final total = usage?['total_tokens'] as int?;
      final cached =
          usage?['prompt_cache_hit_tokens'] as int? ??
          (usage?['prompt_tokens_details'] as Map?)?['cached_tokens'] as int?;
      final actualModel = data['model'] as String?;
      // N/A near a tariff boundary: server billing time is not known precisely.
      final peak = isPeak(startedAt);
      final stablePeriod =
          isPeak(startedAt.subtract(const Duration(minutes: 1))) == peak &&
          isPeak(finishedAt.add(const Duration(minutes: 1))) == peak;
      final multiplier = peak ? 2 : 1;
      final cost =
          actualModel == model.id &&
              stablePeriod &&
              input != null &&
              output != null &&
              cached != null &&
              input >= cached &&
              cached >= 0 &&
              output >= 0
          ? ((input - cached) * model.inputRate +
                    cached * model.cachedRate +
                    output * model.outputRate) *
                multiplier /
                1000000
          : null;
      return ApiResult(
        content: content,
        elapsed: watch.elapsed,
        input: input,
        output: output,
        total: total,
        cached: cached,
        cost: cost,
        pricePeriod: stablePeriod ? (peak ? 'peak' : 'off-peak') : null,
        actualModel: actualModel,
        finishReason: choice?['finish_reason'] as String?,
        error: content == null || content.trim().isEmpty
            ? 'API вернул пустой ответ.'
            : null,
      );
    } on TimeoutException {
      return ApiResult(
        error: 'Тайм-аут 120 с; полный ответ не получен.',
        elapsed: watch.elapsed,
      );
    } catch (_) {
      // Never expose raw exceptions or provider bodies: they may contain secrets.
      return ApiResult(
        error: 'Ошибка сети или некорректный ответ API.',
        elapsed: watch.elapsed,
      );
    } finally {
      watch.stop();
      client.close();
    }
  }
}
