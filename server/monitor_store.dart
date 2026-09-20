import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One process owns this file. All tools and scheduler ticks share this queue.
class MonitorStore {
  MonitorStore(this.file);
  final File file;
  Future<void> _queue = Future.value();
  Timer? _timer;
  bool _ticking = false;
  bool _ready = false;
  static const _values = [68, 72, 75, 70];

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  Future<Map<String, dynamic>> _read() async {
    final data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
    final jobs = data['jobs'] as List;
    final results = data['results'] as List;
    final ids = <String>{};
    final names = <String>{};
    for (final job in jobs) {
      if (job['id'] is! String || job['name'] is! String ||
          !ids.add(job['id'] as String) || !names.add(job['name'] as String) ||
          job['intervalSeconds'] is! int || job['intervalSeconds'] < 5 ||
          job['intervalSeconds'] > 86400 || job['enabled'] is! bool) {
        throw const FormatException('Invalid job');
      }
      DateTime.parse(job['createdAt'] as String);
      DateTime.parse(job['nextRunAt'] as String);
      if (job['lastRunAt'] != null) DateTime.parse(job['lastRunAt'] as String);
    }
    for (final result in results) {
      if (!ids.contains(result['jobId']) || result['value'] is! int) {
        throw const FormatException('Invalid result');
      }
      DateTime.parse(result['timestamp'] as String);
    }
    return data;
  }

  Future<void> _write(Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> initialize() async {
    try {
      Map<String, dynamic> data;
      if (!await file.exists()) {
        data = {'jobs': [], 'results': []};
      } else {
        try {
          data = await _read();
        } catch (error) {
          if (error is FileSystemException) rethrow;
          final backup = '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}';
          await file.rename(backup);
          stderr.writeln('Corrupt storage preserved at $backup; starting empty.');
          data = {'jobs': [], 'results': []};
        }
      }
      // Restart schedules from now, without fabricating missed executions.
      final now = DateTime.now().toUtc();
      for (final job in data['jobs'] as List) {
        if (job['enabled'] == true) {
          job['nextRunAt'] = now.add(Duration(seconds: job['intervalSeconds'] as int)).toIso8601String();
        }
      }
      await _write(data);
      _ready = true;
    } catch (error) {
      stderr.writeln('Storage unavailable; tools will return an error: $error');
    }
  }

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_ready || _ticking) return;
      _ticking = true;
      try {
        await _exclusive(_tick);
      } catch (error) {
        stderr.writeln('Scheduled run not saved: $error');
      } finally {
        _ticking = false;
      }
    });
  }

  Future<void> close() async {
    _timer?.cancel();
    await _queue;
  }

  Future<void> _tick() async {
    final data = await _read();
    final results = data['results'] as List;
    final now = DateTime.now().toUtc();
    final logs = <String>[];
    for (final job in data['jobs'] as List) {
      if (job['enabled'] != true || DateTime.parse(job['nextRunAt'] as String).isAfter(now)) continue;
      final count = results.where((r) => r['jobId'] == job['id']).length;
      final value = _values[count % _values.length];
      results.add({'jobId': job['id'], 'timestamp': now.toIso8601String(), 'value': value});
      job['lastRunAt'] = now.toIso8601String();
      job['nextRunAt'] = now.add(Duration(seconds: job['intervalSeconds'] as int)).toIso8601String();
      logs.add('${job['name']} run #${count + 1}: value=$value at ${job['lastRunAt']}');
    }
    if (logs.isNotEmpty) {
      await _write(data); // Commit job metadata and execution records together.
      for (final log in logs) { stdout.writeln(log); }
    }
  }

  Future<Map<String, dynamic>> execute(String tool, Map<String, dynamic> args) => _exclusive(() async {
    if (!_ready) throw StateError('Хранилище недоступно. Проверьте права и перезапустите сервер.');
    final name = (args['name'] as String).trim();
    if (name.isEmpty || name.length > 80) throw const FormatException('name: от 1 до 80 символов.');
    final data = await _read();
    final jobs = data['jobs'] as List;
    final matches = jobs.where((j) => j['name'] == name);
    final existing = matches.isEmpty ? null : matches.first;
    if (tool == 'schedule_monitor') {
      final interval = args['intervalSeconds'];
      if (interval is! int || interval < 5 || interval > 86400) {
        throw const FormatException('intervalSeconds: целое число от 5 до 86400.');
      }
      if (existing != null && existing['enabled'] == true) {
        return {'found': true, 'created': false, 'message': 'Мониторинг уже активен; расписание не изменено.', 'job': existing};
      }
      final now = DateTime.now().toUtc();
      final job = existing ?? <String, dynamic>{
        'id': 'monitor-${now.microsecondsSinceEpoch}', 'name': name,
        'createdAt': now.toIso8601String(), 'lastRunAt': null,
      };
      job['intervalSeconds'] = interval;
      job['enabled'] = true;
      job['nextRunAt'] = now.add(Duration(seconds: interval)).toIso8601String();
      if (existing == null) jobs.add(job);
      await _write(data);
      return {'found': true, 'created': existing == null, 'message': 'Мониторинг запланирован.', 'job': job};
    }
    if (existing == null) return {'found': false, 'name': name, 'message': 'Мониторинг не найден.'};
    if (tool == 'stop_monitor') {
      existing['enabled'] = false;
      await _write(data);
      return {'found': true, 'name': name, 'enabled': false, 'message': 'Мониторинг остановлен; история сохранена.'};
    }
    if (tool != 'get_monitor_summary') throw StateError('Unknown tool');
    final runs = (data['results'] as List).where((r) => r['jobId'] == existing['id']).toList();
    final values = runs.map((r) => r['value'] as int).toList();
    final sorted = [...values]..sort();
    return {
      'found': true, 'jobId': existing['id'], 'jobName': name,
      'intervalSeconds': existing['intervalSeconds'], 'enabled': existing['enabled'],
      'runs': runs.length, 'firstValue': values.firstOrNull, 'latestValue': values.lastOrNull,
      'minValue': sorted.firstOrNull, 'maxValue': sorted.lastOrNull,
      'averageValue': values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length,
      'firstRunAt': runs.firstOrNull?['timestamp'], 'lastRunAt': runs.lastOrNull?['timestamp'],
    };
  });
}
