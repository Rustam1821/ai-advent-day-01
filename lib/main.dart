import 'package:flutter/material.dart';

import 'mcp_client_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Advent — Day 16',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4154B3)),
      scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      useMaterial3: true,
    ),
    home: const McpPage(),
  );
}

class McpPage extends StatefulWidget {
  const McpPage({super.key});
  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  final _service = McpClientService();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day 16 · MCP')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              final connected = _service.status == McpStatus.connected;
              final busy = _service.status == McpStatus.connecting || _service.loadingTools;
              final status = switch (_service.status) {
                McpStatus.disconnected => 'Disconnected',
                McpStatus.connecting => 'Connecting…',
                McpStatus.connected => 'Connected',
                McpStatus.error => 'Error',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Microsoft Learn MCP', style: Theme.of(context).textTheme.titleLarge),
                        SelectableText(McpClientService.endpoint.toString()),
                        const Text('Streamable HTTP · без API key'),
                        const SizedBox(height: 16),
                        Text('Status: $status', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, children: [
                          FilledButton(
                            onPressed: busy || connected ? null : _service.connect,
                            child: const Text('Connect'),
                          ),
                          OutlinedButton(
                            onPressed: busy || !connected ? null : _service.getTools,
                            child: const Text('Get Tools'),
                          ),
                        ]),
                        if (busy) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                          Text(_service.loadingTools ? 'Loading tools…' : 'Initializing MCP…'),
                        ],
                        if (_service.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_service.error!, style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                          ),
                        if (_service.toolsLoaded) ...[
                          const SizedBox(height: 12),
                          Text('Available tools: ${_service.tools.length}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: _service.toolsLoaded
                        ? _service.tools.isEmpty
                            ? const Center(child: Text('Сервер вернул пустой список tools.'))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: _service.tools.length,
                                itemBuilder: (context, index) {
                                  final tool = _service.tools[index];
                                  return Card(child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SelectableText(tool.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        if (tool.description?.isNotEmpty == true) ...[
                                          const SizedBox(height: 6),
                                          SelectableText(tool.description!),
                                        ],
                                      ],
                                    ),
                                  ));
                                },
                              )
                        : const Center(child: Text('Connect → Get Tools')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
