import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import 'monitor_store.dart';

McpServer createServer(MonitorStore store) {
  final server = McpServer(const Implementation(name: 'ai-advent-monitors', version: '1.0.0'));
  const descriptions = {
    'schedule_monitor': 'Create a persistent periodic mock health monitor. Existing active names are not duplicated or changed. Stopped names resume with their history. intervalSeconds must be 5..86400.',
    'get_monitor_summary': 'Return server-computed statistics from persisted executions for a monitor name. Unknown names return found=false. Before the first run returns runs=0 and null statistics.',
    'stop_monitor': 'Stop future executions of a named monitor, preserving its history.',
  };
  for (final entry in descriptions.entries) {
    server.registerTool(
      entry.key, description: entry.value,
      inputSchema: JsonSchema.object(
        properties: {
          'name': JsonSchema.string(description: 'Monitor name, e.g. demo-monitor'),
          if (entry.key == 'schedule_monitor')
            'intervalSeconds': JsonSchema.integer(description: 'Interval in seconds, from 5 to 86400'),
        },
        required: ['name', if (entry.key == 'schedule_monitor') 'intervalSeconds'],
      ),
      callback: (arguments, extra) async {
        try {
          final data = await store.execute(entry.key, arguments);
          return CallToolResult(content: [TextContent(text: jsonEncode(data))], structuredContent: data);
        } catch (_) {
          final data = {'error': 'Операция не выполнена. Проверьте name, intervalSeconds (5..86400) и доступность JSON-хранилища.'};
          return CallToolResult(isError: true,
            content: [TextContent(text: jsonEncode(data))], structuredContent: data);
        }
      },
    );
  }
  return server;
}

Future<void> main() async {
  final host = Platform.environment['MCP_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['MCP_PORT'] ?? '3000');
  // Default location is relative to this script, not the terminal working directory.
  final file = Platform.environment['MCP_DATA_FILE'];
  final store = MonitorStore(file == null
      ? File.fromUri(Platform.script.resolve('data/monitors.json')) : File(file));
  await store.initialize();
  final server = StreamableMcpServer(
    serverFactory: (_) => createServer(store),
    host: host, port: port, path: '/mcp',
    allowedHosts: {'localhost', '127.0.0.1', '10.0.2.2', ...?Platform.environment['MCP_ALLOWED_HOST']?.split(',')},
  );
  await server.start();
  store.start(); // One scheduler for all sessions; client disconnect does not stop it.
  stdout.writeln('Monitoring MCP: http://$host:$port/mcp\nStorage: ${store.file.absolute.path}');
  var stopping = false;
  Future<void> stop(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    await store.close();
    await server.stop();
    exit(0);
  }
  ProcessSignal.sigint.watch().listen(stop);
  ProcessSignal.sigterm.watch().listen(stop);
}
