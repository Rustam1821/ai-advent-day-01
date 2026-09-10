import 'dart:convert';
import 'dart:io';

/// Atomic JSON state; accepts the legacy Day 7 message array. No secrets.
class HistoryStorage {
  HistoryStorage(this._resolveFile);

  final Future<File> Function() _resolveFile;

  Future<Map<String, dynamic>> loadState() async {
    final file = await _resolveFile();
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
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

  Future<void> saveState(Map<String, dynamic> state) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(file.path);
  }
}
