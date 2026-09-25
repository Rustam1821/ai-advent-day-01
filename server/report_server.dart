import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

String taskId(dynamic value) {
  if (value is! String || !RegExp(r'^AI-[0-9]{1,10}$').hasMatch(value)) {
    throw const FormatException('taskId must match AI-123');
  }
  return value;
}

McpServer createServer(Directory reports) {
  final server = McpServer(const Implementation(name: 'report-server', version: '1.0.0'));
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
          return CallToolResult(isError: true, content: [TextContent(text: 'Не удалось выполнить $name. Проверьте доступ к reports.')]);
        }
      },
    );
  }
  register('create_task_summary', 'Format the task data returned by get_task_data. Does not perform a lookup.',
    ['taskId', 'status', 'assignee', 'priority', 'history'], (args) async {
      final id = taskId(args['taskId']);
      for (final field in ['status', 'assignee', 'priority']) {
        if ((args[field] as String).isEmpty || (args[field] as String).length > 200) {
          throw FormatException('Invalid $field');
        }
      }
      return {'taskId': id, 'content': 'Task $id is currently ${args['status']}.\nAssignee: ${args['assignee']}.\nPriority: ${args['priority']}.\n${(args['history'] as String).isEmpty ? '' : 'History:\n${args['history']}\n'}'};
    });
  register('save_report', 'Save taskId/content returned by create_task_summary as a TXT file in the reports directory. Replaces the report for the same ID.',
    ['taskId', 'content'], (args) async {
      final id = taskId(args['taskId']);
      final content = args['content'] as String;
      if (content.isEmpty || content.length > 10000) throw const FormatException('Invalid report content');
      await reports.create(recursive: true);
      // No caller-controlled path. Reject symlink targets, including the reports directory.
      if (await FileSystemEntity.type(reports.path, followLinks: false) == FileSystemEntityType.link) {
        throw const FormatException('Reports directory must not be a symlink');
      }
      final filename = 'report_$id.txt';
      final file = File('${reports.path}/$filename');
      if (await FileSystemEntity.type(file.path, followLinks: false) == FileSystemEntityType.link) {
        throw const FormatException('Report must not be a symlink');
      }
      await file.writeAsString(content, flush: true);
      return {'success': true, 'taskId': id, 'filename': filename, 'path': file.absolute.path};
    });
  return server;
}

Future<void> main() async {
  final host = Platform.environment['MCP_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['MCP_PORT'] ?? '3001');
  final reports = Directory.fromUri(Platform.script.resolve('reports/'));
  final server = StreamableMcpServer(
    serverFactory: (_) => createServer(reports), host: host, port: port, path: '/mcp',
    allowedHosts: {'localhost', '127.0.0.1', '10.0.2.2', ...?Platform.environment['MCP_ALLOWED_HOST']?.split(',')},
  );
  await server.start();
  stdout.writeln('Report MCP: http://$host:$port/mcp\nReports: ${reports.absolute.path}');
}
