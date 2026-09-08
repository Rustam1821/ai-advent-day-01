import 'dart:convert';
import 'dart:io';

/// A JSON array; its order is the conversation order. No config or secrets.
class HistoryStorage {
  HistoryStorage(this._resolveFile);

  final Future<File> Function() _resolveFile;

  Future<List<Map<String, String>>> load() async {
    final file = await _resolveFile();
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString());
    if (data is! List) throw const FormatException('Invalid history');
    return data.map((item) {
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
  }

  Future<void> save(List<Map<String, String>> messages) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(messages), flush: true);
    await temporary.rename(file.path);
  }
}
