// Day 31/32: read-only Git branch and PR snapshot tools.
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
  server.registerTool('get_pr_changes',
    description: 'Read merge-base PR diff and tracked documentation/code blobs. No checkout.',
    inputSchema: JsonSchema.object(properties: {
      'base': JsonSchema.string(), 'head': JsonSchema.string(),
    }, required: ['base', 'head']),
    callback: (args, extra) async {
      try {
        final base = args['base'] as String;
        final head = args['head'] as String;
        if (args.length != 2 || !RegExp(r'^[0-9a-f]{40}$').hasMatch(base) ||
            !RegExp(r'^[0-9a-f]{40}$').hasMatch(head)) {
          throw const FormatException('Expected full commit SHAs');
        }
        Future<String> git(List<String> command) async {
          final result = await Process.run('git', ['-C', projectRoot, '-c', 'core.quotepath=false', ...command])
              .timeout(const Duration(seconds: 30));
          if (result.exitCode != 0) throw StateError('Git failed');
          final output = result.stdout as String;
          if (utf8.encode(output).length > 512000) {
            throw StateError('Git output exceeds review limit');
          }
          return output;
        }
        final ancestor = (await git(['merge-base', base, head])).trim();
        final files = (await git(['diff', '--no-renames', '--name-only', '-z', ancestor, head]))
            .split('\x00').where((p) => p.isNotEmpty).toList();
        if (files.length > 40) throw StateError('More than 40 changed files');
        final diff = await git(['diff', '--no-ext-diff', '--no-textconv',
          '--no-renames', '--unified=3', ancestor, head, '--']);
        if (utf8.encode(diff).length > 48000) {
          throw StateError('Diff exceeds 48000 bytes; split PR');
        }
        final documents = <List<String>>[];
        var size = 0;
        final entries = (await git(['ls-tree', '-r', '-z', head])).split('\x00');
        for (final entry in entries) {
          final tab = entry.indexOf('\t');
          if (tab < 0 || !entry.startsWith('100644 blob ')) continue;
          final path = entry.substring(tab + 1);
          final doc = path == 'README.md' ||
              (path.startsWith('docs/') && path.endsWith('.md'));
          final code = RegExp(r'^(lib|server|gateway)/.*\.(dart|py)$').hasMatch(path);
          if (!doc && !code) continue;
          final oid = entry.substring(12, tab);
          final length = int.parse((await git(['cat-file', '-s', oid])).trim());
          size += length;
          if (length > 64000 || size > 256000) {
            throw StateError('RAG corpus exceeds 64KB/file or 256KB total');
          }
          documents.add([path, await git(['cat-file', 'blob', oid])]);
        }
        final data = {'base': base, 'head': head, 'merge_base': ancestor,
          'files': files, 'diff': diff, 'documents': documents};
        return CallToolResult(content: [TextContent(text: 'PR snapshot ready')],
          structuredContent: data);
      } catch (_) {
        return CallToolResult(isError: true, content: [TextContent(
          text: 'PR snapshot unavailable: check SHAs/history; limits: 40 files, '
            '48KB diff, 64KB per RAG file, 256KB corpus. Split oversized PR.')]);
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
