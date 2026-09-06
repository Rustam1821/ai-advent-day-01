// Manual live API check using the same request builder and timing as the UI.
// Run: dart run tool/run_day5.dart
import 'dart:convert';

import 'dart:io';

import 'package:ai_advent_day_01/experiment.dart';

Future<void> main(List<String> args) async {
  final env = <String, String>{};
  for (final line in File('.env').readAsLinesSync()) {
    final split = line.indexOf('=');
    if (split < 1 || line.trimLeft().startsWith('#')) continue;
    var value = line.substring(split + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    env[line.substring(0, split).trim()] = value;
  }
  final deepSeekKey = env['DEEPSEEK_API_KEY'] ?? '';
  final canonical = requestBody(models.first.id)..remove('model');
  for (final model in models) {
    final payload = requestBody(model.id)..remove('model');
    if (jsonEncode(payload) != jsonEncode(canonical)) {
      throw StateError('Request parameters differ');
    }
  }
  await Future.wait(
    models.map((model) async {
      final r = await askModel(model, deepSeekKey);
      stdout.writeln(
        jsonEncode({
          'requested_model': model.id,
          'actual_model': r.actualModel,
          'elapsed_ms': r.elapsed?.inMilliseconds,
          'input': r.input,
          'output': r.output,
          'total': r.total,
          'cached': r.cached,
          'cost_usd': r.cost,
          'price_period': r.pricePeriod,
          'finish_reason': r.finishReason,
          'error': r.error,
          'content': r.content,
        }),
      );
    }),
  );
}
