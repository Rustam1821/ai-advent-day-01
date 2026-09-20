import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

enum McpStatus { disconnected, connecting, connected, error }

class ToolInfo {
  const ToolInfo(this.name, this.description);
  final String name;
  final String? description;
}

/// Only connects and discovers tools. No tool execution or LLM integration.
class McpClientService extends ChangeNotifier {
  static final endpoint = Uri.parse('https://learn.microsoft.com/api/mcp');
  McpClient? _client;
  bool _disposed = false;
  McpStatus status = McpStatus.disconnected;
  bool loadingTools = false;
  bool toolsLoaded = false;
  String? error;
  List<ToolInfo> tools = const [];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect() async {
    if (_disposed || status == McpStatus.connecting || status == McpStatus.connected) return;
    status = McpStatus.connecting;
    error = null;
    tools = const [];
    toolsLoaded = false;
    _notify();
    final client = McpClient(
      const Implementation(name: 'ai-advent-day16', version: '1.0.0'),
    );
    _client = client;
    client.onclose = () {
      if (_disposed || _client != client) return;
      status = McpStatus.disconnected;
      _notify();
    };
    try {
      // SDK performs protocol negotiation and initialization.
      await client.connect(StreamableHttpClientTransport(endpoint))
          .timeout(const Duration(seconds: 30));
      if (_disposed || _client != client) return;
      status = McpStatus.connected;
      _notify();
    } catch (_) {
      await _fail(client, 'Не удалось подключиться. Проверьте интернет и нажмите Connect ещё раз.');
    }
  }

  Future<void> getTools() async {
    final client = _client;
    if (_disposed || client == null || status != McpStatus.connected || loadingTools) return;
    loadingTools = true;
    toolsLoaded = false;
    tools = const [];
    error = null;
    _notify();
    try {
      final result = await _listAll(client).timeout(const Duration(seconds: 30));
      if (_disposed || _client != client) return;
      tools = List.unmodifiable(result);
      toolsLoaded = true;
    } catch (_) {
      await _fail(client, 'Не удалось получить tools. Нажмите Connect и повторите Get Tools.');
    } finally {
      loadingTools = false;
      _notify();
    }
  }

  Future<List<ToolInfo>> _listAll(McpClient client) async {
    final result = <ToolInfo>[];
    final seen = <String>{};
    String? cursor;
    do {
      if (_disposed || _client != client) throw StateError('Connection closed');
      final page = await client.listTools(
        params: cursor == null ? null : ListToolsRequest(cursor: cursor),
      );
      result.addAll(page.tools.map((tool) => ToolInfo(tool.name, tool.description)));
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw StateError('Repeated pagination cursor');
      }
    } while (cursor != null);
    return result;
  }

  Future<void> _fail(McpClient client, String message) async {
    if (_client != client) return;
    _client = null;
    status = McpStatus.error;
    error = message;
    _notify();
    await _close(client);
  }

  Future<void> _close(McpClient client) async {
    try {
      await client.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Cleanup failure must not hide the original connection error.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final client = _client;
    _client = null;
    if (client != null) unawaited(_close(client));
    super.dispose();
  }
}
