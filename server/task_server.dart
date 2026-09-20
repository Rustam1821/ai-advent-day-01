import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

const tasks = {
  'AI-101': {'status': 'In Progress', 'assignee': 'Alex'},
  'AI-102': {'status': 'Done', 'assignee': 'Maria'},
  'AI-103': {'status': 'Blocked', 'assignee': 'John'},
};

McpServer createServer() {
  final server = McpServer(const Implementation(name: 'ai-advent-tasks', version: '1.0.0'));
  server.registerTool(
    'get_task_status',
    description: 'Returns current status and assignee of a task by task ID. Returns found=false for unknown IDs.',
    inputSchema: JsonSchema.object(
      properties: {'taskId': JsonSchema.string(description: 'Task ID, for example AI-101')},
      required: ['taskId'],
    ),
    callback: (arguments, extra) async {
      final id = (arguments['taskId'] as String).trim().toUpperCase();
      final task = tasks[id];
      final data = <String, dynamic>{
        'taskId': id,
        'found': task != null,
        if (task != null) ...task else 'message': 'Task $id not found',
      };
      return CallToolResult(
        content: [TextContent(text: jsonEncode(data))],
        structuredContent: data,
      );
    },
  );
  return server;
}

Future<void> main() async {
  final host = Platform.environment['MCP_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['MCP_PORT'] ?? '3000');
  final server = StreamableMcpServer(
    serverFactory: (_) => createServer(),
    host: host, port: port, path: '/mcp',
    allowedHosts: {
      'localhost', '127.0.0.1', '10.0.2.2',
      ...?Platform.environment['MCP_ALLOWED_HOST']?.split(','),
    },
  );
  await server.start();
  stdout.writeln('Task MCP server: http://$host:$port/mcp');
}
