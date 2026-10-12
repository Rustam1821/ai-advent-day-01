// Adapted from Day 20 server/task_server.dart: one read-only project tool.
import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

final projectRoot = File.fromUri(Platform.script).parent.parent.path;

McpServer createServer() {
  final server = McpServer(
    const Implementation(name: 'developer-assistant', version: '1.0.0'));
  server.registerTool('get_current_branch',
    description: 'Read the current Git branch of the AI Advent project.',
    inputSchema: JsonSchema.object(properties: {}),
    callback: (args, extra) async {
      try {
        if (args.isNotEmpty) throw const FormatException('No arguments accepted');
        final result = await Process.run('git',
          ['-C', projectRoot, 'symbolic-ref', '--quiet', '--short', 'HEAD'])
          .timeout(const Duration(seconds: 5));
        if (result.exitCode == 1) {
          return CallToolResult(content: [TextContent(text: 'Detached HEAD: no current branch')],
            structuredContent: {'branch': null, 'detached': true});
        }
        final branch = (result.stdout as String).trim();
        if (result.exitCode != 0 || branch.isEmpty) {
          throw StateError('Cannot read Git branch');
        }
        final data = {'branch': branch, 'detached': false};
        return CallToolResult(content: [TextContent(text: jsonEncode(data))],
          structuredContent: data);
      } catch (_) {
        return CallToolResult(isError: true,
          content: [TextContent(text: 'Cannot read project Git branch')]);
      }
    });
  return server;
}

Future<void> main() async {
  final server = StreamableMcpServer(serverFactory: (_) => createServer(),
    host: '127.0.0.1', port: 3000, path: '/mcp', enableJsonResponse: true,
    allowedHosts: {'localhost', '127.0.0.1'});
  await server.start();
  stdout.writeln('Developer MCP: http://127.0.0.1:3000/mcp');
}
