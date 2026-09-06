import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const systemPrompt =
    'Ты решаешь задачи на вероятность. Соблюдай все условия, '
    'отвечай по-русски, приводи проверяемое краткое обоснование. '
    'Не используй инструменты. Формат ответа задан пользователем.';
const userPrompt = '''Есть три коробки: с двумя золотыми монетами, двумя серебряными и одной монетой каждого вида. Равновероятно выбирают коробку, затем равновероятно одну монету из неё. Монета оказалась золотой. Какова вероятность, что оставшаяся монета тоже золотая? Объясни, почему ответ не 1/2. Ответ до 100 слов.''';
const referenceAnswer = '''Вероятность — 2/3.
Все шесть монет изначально равновероятны. После наблюдения золотой монеты остаются три равновероятных варианта: две золотые монеты из коробки ЗЗ и одна из коробки ЗС. В двух из трёх случаев оставшаяся монета золотая.
Ответ не 1/2: после наблюдения коробки ЗЗ и ЗС не равновероятны. Из ЗЗ золотая монета выпадает всегда, а из ЗС — лишь в половине случаев, поэтому ЗЗ вдвое вероятнее.''';

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

const models = [
  ModelSpec('Weak · Flash', 'deepseek-v4-flash', 0.22, 0.007, 0.66),
  ModelSpec(
    'Experimental · Vision',
    'deepseek-v4-flash-vision-exp',
    0.22,
    0.007,
    0.66,
  ),
  ModelSpec('Strong · Pro', 'deepseek-v4-pro', 0.66, 0.022, 1.98),
];

// DeepSeek peak windows: weekdays 01–04 and 06–10 UTC.
bool isPeak(DateTime time) {
  final utc = time.toUtc();
  return utc.weekday <= DateTime.friday &&
      ((utc.hour >= 1 && utc.hour < 4) || (utc.hour >= 6 && utc.hour < 10));
}

// The exact same payload is used for all three requests except model.
Map<String, Object> requestBody(String model) => {
  'model': model,
  'messages': [
    {'role': 'system', 'content': systemPrompt},
    {'role': 'user', 'content': userPrompt},
  ],
  'temperature': 0,
  'top_p': 1,
  'max_tokens': 1600,
  'frequency_penalty': 0,
  'presence_penalty': 0,
  'n': 1,
  'stream': false,
  'response_format': {'type': 'text'},
  'thinking': {'type': 'disabled'},
};

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

Future<ApiResult> askModel(ModelSpec model, String key) async {
  if (key.trim().isEmpty) {
    return const ApiResult(
      error:
          'Нет DEEPSEEK_API_KEY в .env. Добавьте ключ '
          'и полностью перезапустите приложение с --dart-define-from-file=.env.',
    );
  }
  final body = requestBody(model.id);
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
      final hint = switch (response.statusCode) {
        401 => 'Проверьте API key.',
        403 => 'Нет доступа к модели или API.',
        429 => 'Лимит запросов или недостаточно квоты/баланса.',
        _ => 'Запрос не выполнен; повторите позже.',
      };
      return ApiResult(
        error: 'HTTP ${response.statusCode}. $hint',
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
