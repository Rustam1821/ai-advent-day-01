import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

enum McpStatus { disconnected, connecting, connected, error }

class ToolInfo {
  const ToolInfo(this.name, this.description, this.schema);
  final String name;
  final String? description;
  final Map<String, dynamic> schema;
}

/// MCP connection, discovery and monitoring tools.
class McpClientService extends ChangeNotifier {
  static const supportedTools = {'schedule_monitor', 'get_monitor_summary', 'stop_monitor'};
  static final endpoint = Uri.parse(const String.fromEnvironment('MCP_URL', defaultValue: 'http://127.0.0.1:3000/mcp'));
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
      const Implementation(name: 'ai-advent-day18', version: '1.0.0'),
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
      final discovered = await _listAll(client).timeout(const Duration(seconds: 30));
      if (!supportedTools.every((name) => discovered.any((tool) => tool.name == name))) {
        throw StateError('Monitoring tools not found');
      }
      if (_disposed || _client != client) return;
      tools = List.unmodifiable(discovered.where((tool) => supportedTools.contains(tool.name)));
      toolsLoaded = true;
      status = McpStatus.connected;
      _notify();
    } catch (_) {
      await _fail(client, 'Не удалось подключиться. Проверьте интернет и нажмите Connect ещё раз.');
    }
  }

  Future<Map<String, dynamic>> callMonitorTool(String name, Map<String, dynamic> arguments) async {
    final client = _client;
    if (client == null || status != McpStatus.connected) {
      throw StateError('MCP не подключён. Нажмите Connect.');
    }
    if (!supportedTools.contains(name)) throw StateError('Неизвестный monitoring tool.');
    try {
      final result = await client.callTool(CallToolRequest(
        name: name, arguments: arguments,
      )).timeout(const Duration(seconds: 30));
      return result.toJson();
    } catch (_) {
      await _fail(client, 'MCP tool недоступен. Проверьте сервер и нажмите Connect.');
      throw StateError('Не удалось выполнить внешний MCP tool. Результат операции неизвестен. Перед повторным созданием запросите сводку.');
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
      result.addAll(page.tools.map((tool) => ToolInfo(tool.name, tool.description, Map<String, dynamic>.from(tool.toJson()['inputSchema'] as Map))));
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
