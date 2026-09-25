import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

const tasks = {
  'AI-101': {'status': 'In Progress', 'assignee': 'Alex', 'priority': 'High'},
  'AI-102': {'status': 'Done', 'assignee': 'Maria', 'priority': 'Medium'},
  'AI-103': {'status': 'Blocked', 'assignee': 'John', 'priority': 'High'},
};

String taskId(dynamic value) {
  if (value is! String || !RegExp(r'^AI-[0-9]{1,10}$').hasMatch(value)) {
    throw const FormatException('taskId must match AI-123');
  }
  return value;
}

McpServer createServer() {
  final server = McpServer(const Implementation(name: 'task-server', version: '1.0.0'));
  void register(String name, String description, List<String> fields,
      Future<Map<String, dynamic>> Function(Map<String, dynamic>) operation) {
    server.registerTool(name, description: description,
      inputSchema: JsonSchema.object(
        properties: {for (final field in fields) field: JsonSchema.string()}, required: fields,
      ),
      callback: (args, extra) async {
        try {
          final data = await operation(args);
          return CallToolResult(content: [TextContent(text: jsonEncode(data))], structuredContent: data);
        } on FormatException catch (error) {
          return CallToolResult(isError: true, content: [TextContent(text: error.message)]);
        } catch (_) {
          return CallToolResult(isError: true, content: [TextContent(text: 'Не удалось выполнить $name. Проверьте taskId.')]);
        }
      },
    );
  }
  register('get_task_data', 'Get structured task data by taskId. Unknown IDs return an error.',
    ['taskId'], (args) async {
      final id = taskId(args['taskId']);
      final task = tasks[id];
      if (task == null) throw FormatException('Task $id not found');
      return {'taskId': id, ...task};
    });
  register('get_task_history', 'Get task history only; use when the user requests history, including full reports.',
    ['taskId'], (args) async {
      final id = taskId(args['taskId']);
      final task = tasks[id];
      if (task == null) throw FormatException('Task $id not found');
      return {'taskId': id, 'history': 'Created\nAssigned to ${task['assignee']}\nMoved to ${task['status']}'};
    });
  return server;
}

Future<void> main() async {
  final host = Platform.environment['MCP_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['MCP_PORT'] ?? '3000');
  final server = StreamableMcpServer(
    serverFactory: (_) => createServer(), host: host, port: port, path: '/mcp',
    allowedHosts: {'localhost', '127.0.0.1', '10.0.2.2', ...?Platform.environment['MCP_ALLOWED_HOST']?.split(',')},
  );
  await server.start();
  stdout.writeln('Task MCP: http://$host:$port/mcp');
}
