import 'dart:convert';
import 'dart:io';

/// Shared local persistence primitive; each owner validates its own JSON shape.
class JsonFileStorage {
  JsonFileStorage(this._resolveFile);
  final Future<File> Function() _resolveFile;

  Future<dynamic> read() async {
    final file = await _resolveFile();
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> write(Object value) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }
}
