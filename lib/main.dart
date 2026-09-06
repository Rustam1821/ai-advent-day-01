import 'package:flutter/material.dart';

import 'experiment.dart';

const _apiKey = String.fromEnvironment('DEEPSEEK_API_KEY');

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 5',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)),
      scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      useMaterial3: true,
    ),
    home: const ModelComparisonPage(),
  );
}

class ModelComparisonPage extends StatefulWidget {
  const ModelComparisonPage({super.key});
  @override
  State<ModelComparisonPage> createState() => _ModelComparisonPageState();
}

class _ModelComparisonPageState extends State<ModelComparisonPage> {
  final Map<String, ApiResult> _results = {};
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    await Future.wait(
      models.map((model) async {
        final result = await askModel(model, _apiKey);
        if (mounted) setState(() => _results[model.id] = result);
      }),
    );
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 5 · Сравнение моделей')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Один prompt. Три модели.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Качество · Время полного ответа · Токены · Стоимость',
                ),
                const SizedBox(height: 12),
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Общий user prompt'),
                    childrenPadding: const EdgeInsets.all(16),
                    children: const [SelectableText(userPrompt)],
                  ),
                ),
                Card(
                  child: ExpansionTile(
                    title: const Text('Одинаковые условия эксперимента'),
                    subtitle: const Text(
                      'temperature 0 · max tokens 1600 · без streaming',
                    ),
                    childrenPadding: const EdgeInsets.all(16),
                    children: const [
                      SelectableText(
                        'System prompt:\n$systemPrompt\n\n'
                        'top_p: 1; frequency_penalty: 0; presence_penalty: 0; '
                        'n: 1; response_format: text; thinking: disabled. '
                        'Меняется только model. Запросы запускаются параллельно, '
                        'без автоматических повторов.\n\n'
                        'Flash — условно Weak, Pro — условно Strong. Vision — '
                        'экспериментальная версия Flash, не подтверждённый Medium. '
                        'Это три модели, но не строгая градация Weak / Medium / Strong. ',
                      ),
                    ],
                  ),
                ),
                if (_apiKey.trim().isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Для запуска нужен DEEPSEEK_API_KEY в .env и полный '
                      'перезапуск с --dart-define-from-file=.env.',
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _running
                        ? 'Готово ${_results.length} / 3…'
                        : 'Сравнить три модели',
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      for (final model in models)
                        _ResultCard(
                          model: model,
                          result: _results[model.id],
                          running: _running,
                        ),
                    ];
                    if (constraints.maxWidth >= 1000) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final card in cards) Expanded(child: card),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cards,
                    );
                  },
                ),
                _ComparisonSummary(results: _results, running: _running),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.model,
    required this.result,
    required this.running,
  });
  final ModelSpec model;
  final ApiResult? result;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final pending = running && r == null;
    String tokens(int? value) => value?.toString() ?? 'N/A';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.category, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            SelectableText(model.id, style: const TextStyle(fontSize: 13)),
            const Divider(height: 24),
            Text(
              '${r?.error != null ? 'Время до ошибки' : 'Response time'}: '
              '${r?.elapsed == null ? 'N/A' : '${(r!.elapsed!.inMilliseconds / 1000).toStringAsFixed(3)} с'}',
            ),
            Text(
              'Tokens · input: ${tokens(r?.input)} · output: ${tokens(r?.output)}',
            ),
            Text(
              'Total: ${tokens(r?.total)} · cached input: ${tokens(r?.cached)}',
            ),
            Text(
              'Cost: ${r?.cost == null ? 'N/A' : '\$${r!.cost!.toStringAsFixed(6)} USD (расчёт)'}',
            ),
            const Divider(height: 24),
            if (pending) const LinearProgressIndicator(),
            if (r?.error != null)
              Text(
                r!.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (r?.finishReason != null && r!.finishReason != 'stop')
              Text(
                'Ответ не завершён: ${r.finishReason}. Учитывайте это при сравнении.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (r?.actualModel != null && r!.actualModel != model.id)
              Text('API вернул модель: ${r.actualModel}'),
            const SizedBox(height: 8),
            SelectableText(
              r?.content ??
                  (pending
                      ? 'Ожидаем полный ответ…'
                      : r?.error == null
                      ? 'Ещё не запущено.'
                      : 'Ответ не получен.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSummary extends StatelessWidget {
  const _ComparisonSummary({required this.results, required this.running});

  final Map<String, ApiResult> results;
  final bool running;

  String _name(ModelSpec model) => switch (model.id) {
    'deepseek-v4-flash' => 'Flash',
    'deepseek-v4-flash-vision-exp' => 'Vision',
    _ => 'Pro',
  };

  bool _complete(ModelSpec model) {
    final result = results[model.id];
    return result != null && result.error == null &&
        result.finishReason == 'stop' && result.actualModel == model.id &&
        (result.content?.trim().isNotEmpty ?? false);
  }

  String _extreme(String title, num? Function(ApiResult) metric,
      String Function(num) format, {bool maximum = false}) {
    final available = models.where((model) =>
        _complete(model) && metric(results[model.id]!) != null).toList();
    if (available.length < 2) {
      return '$title: недостаточно сопоставимых данных.';
    }
    final values = available.map((model) => metric(results[model.id]!)!);
    final extreme = values.reduce((a, b) =>
        maximum ? (a > b ? a : b) : (a < b ? a : b));
    final names = available.where((model) =>
        metric(results[model.id]!) == extreme).map(_name).join(', ');
    final scope = available.length == models.length
        ? '' : ' (среди ${available.length} моделей с полными данными)';
    return '$title: $names — ${format(extreme)}$scope.';
  }

  @override
  Widget build(BuildContext context) {
    final finished = !running && results.length == models.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сравнительный анализ',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!finished)
              Text(running ? 'Собираем результаты: ${results.length} / 3…'
                  : 'Запустите три модели, чтобы сравнить результаты.'),
            if (results.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Модель')),
                    DataColumn(label: Text('Время, с'), numeric: true),
                    DataColumn(label: Text('Output'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Cost, USD'), numeric: true),
                  ],
                  rows: [for (final model in models)
                    DataRow(cells: [
                      DataCell(Text(_name(model))),
                      DataCell(Text(results[model.id]?.error != null ||
                          results[model.id]?.elapsed == null ? 'N/A' :
                          (results[model.id]!.elapsed!.inMilliseconds / 1000)
                              .toStringAsFixed(3))),
                      DataCell(Text(results[model.id]?.output?.toString() ?? 'N/A')),
                      DataCell(Text(results[model.id]?.total?.toString() ?? 'N/A')),
                      DataCell(Text(results[model.id]?.cost?.toStringAsFixed(6) ?? 'N/A')),
                    ]),
                  ],
                ),
              ),
            ],
            if (finished) ...[
              const SizedBox(height: 12),
              Text(_extreme('Самая быстрая',
                  (r) => r.elapsed?.inMilliseconds,
                  (v) => '${(v / 1000).toStringAsFixed(3)} с')),
              const SizedBox(height: 6),
              Text(_extreme('Самая дешёвая',
                  (r) => r.cost, (v) => '\$${v.toStringAsFixed(6)}')),
              const SizedBox(height: 6),
              Text(_extreme('Самая дорогая',
                  (r) => r.cost, (v) => '\$${v.toStringAsFixed(6)}',
                  maximum: true)),
              const SizedBox(height: 6),
              Text(_extreme('Меньше всего токенов',
                  (r) => r.total, (v) => '$v')),
              const SizedBox(height: 6),
              Text(_extreme('Больше всего токенов',
                  (r) => r.total, (v) => '$v', maximum: true)),
            ],
          ],
        ),
      ),
    );
  }
}
