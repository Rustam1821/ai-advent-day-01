# Day 17 — Agent → custom MCP tool → answer

Server: `server/task_server.dart`, SDK `mcp_dart` 2.4.2, Streamable HTTP.
The same installed SDK provides both server and client: no Node/Python setup.
Mock records exist only on the server: AI-101 (In Progress / Alex),
AI-102 (Done / Maria), AI-103 (Blocked / John).

`get_task_status` is registered using `registerTool`, with a description and
object input schema requiring `taskId: string`. Unknown IDs return `found: false`.

## Run manually (from repository root)

Terminal 1:

```sh
dart run server/task_server.dart
```

Terminal 2, with an iOS simulator already open:

```sh
flutter run --dart-define-from-file=.env --dart-define=MCP_URL=http://127.0.0.1:3000/mcp
```

`.env` must contain `DEEPSEEK_API_KEY=your_key`. It is sent only to DeepSeek,
never to the MCP server. The existing model default is `deepseek-v4-flash`;
`--dart-define=DEEPSEEK_MODEL=...` can override it if needed for your account.

### Other devices

- Android emulator: `--dart-define=MCP_URL=http://10.0.2.2:3000/mcp`.
  Local cleartext HTTP is enabled in the Android debug manifest.
- Physical iPhone/Android: use the Mac's LAN IP, same Wi-Fi, allow local network
  access on iOS. Start server with `MCP_HOST=0.0.0.0 MCP_ALLOWED_HOST=192.168.1.10 dart run server/task_server.dart`
  (replace the example IP), and use `--dart-define=MCP_URL=http://192.168.1.10:3000/mcp`.
- iOS simulator: `127.0.0.1` reaches the Mac. Local networking is declared in Info.plist.

No MCP authentication, database, server installation or Inspector required.
Dependencies are shared with the Flutter project. If checking out fresh, run
`flutter pub get` before the server command.

## Video/manual scenario

1. Start server and app. Show URL and MCP disconnected.
2. Press Connect. Show connected and Discovered: get_task_status.
3. Ask `Какой статус задачи AI-101?`. Expect In Progress / Alex.
4. Expand Last MCP Tool Call: name, taskId argument and actual MCP result.
5. Ask `А что с AI-103?`. Expect Blocked / John; show updated proof.
6. Optionally ask `Какой статус AI-999?`: not found, no invented status.

The Agent obtains the function schema from MCP discovery. DeepSeek chooses the
function and JSON arguments; the app permits one get_task_status call only.
The MCP result returns as a role=tool message with the matching tool_call_id;
a second DeepSeek request generates the answer with tool_choice=none.
No endless loop. Unknown IDs/tool errors have a grounded fallback response.
Network/API failures are shown without exposing API keys.

Only static analysis is performed during implementation. Runtime verification
is left to the user.
