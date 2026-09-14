import 'dart:io';

import 'json_file_storage.dart';

/// Atomic JSON state; accepts the legacy Day 7 message array. No secrets.
class HistoryStorage {
  HistoryStorage(Future<File> Function() resolveFile)
    : _json = JsonFileStorage(resolveFile);

  final JsonFileStorage _json;

  Future<Map<String, dynamic>> loadState() async {
    final decoded = await _json.read();
    if (decoded == null) return {};
    final state = decoded is List
        ? <String, dynamic>{'messages': decoded}
        : Map<String, dynamic>.from(decoded as Map);
    final data = state['messages'];
    if (data is! List) throw const FormatException('Invalid history');
    state['messages'] = data.map((item) {
      if (item is! Map ||
          (item['role'] != 'user' && item['role'] != 'assistant') ||
          item['content'] is! String ||
          (item['content'] as String).trim().isEmpty) {
        throw const FormatException('Invalid message');
      }
      return <String, String>{
        'role': item['role'] as String,
        'content': item['content'] as String,
      };
    }).toList();
    return state;
  }

  Future<List<Map<String, String>>> load() async {
    final state = await loadState();
    return (state['messages'] as List? ?? []).cast<Map<String, String>>();
  }

  Future<void> save(List<Map<String, String>> messages) =>
      saveState({'messages': messages});

  Future<void> saveState(Map<String, dynamic> state) => _json.write(state);
}
