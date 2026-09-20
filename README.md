# AI Advent — Day 16

Minimal Flutter MCP demo: connect → list tools → display names and descriptions.

- SDK: `mcp_dart` 2.4.2.
- Server: Microsoft Learn, `https://learn.microsoft.com/api/mcp`.
- Transport: Streamable HTTP over HTTPS. No API keys or local server required.
- `lib/mcp_client_service.dart` owns initialization, paginated `tools/list`, errors and cleanup.
- `lib/main.dart` shows connection status and the server's actual tool list.
- No tool execution, LLM, or previous-day demo flow.

## Run and record

Start an iOS simulator or connect a supported device, then run:

```sh
flutter run
```

No `.env` or Dart defines are needed. Flutter resolves dependencies automatically.

1. Show `Status: Disconnected` and the server URL.
2. Press **Connect**; wait for **Connected** (MCP initialization succeeded).
3. Press **Get Tools**; wait for **Available tools: N**.
4. Show the returned names and descriptions. Tools cannot be executed from this UI.

If the server/network fails, the screen shows **Error**. Press **Connect**, then
**Get Tools** to retry manually. Tool names/count are not hardcoded.

## Sources

- https://pub.dev/packages/mcp_dart
- https://learn.microsoft.com/en-us/training/support/mcp
- https://learn.microsoft.com/en-us/training/support/mcp-developer-reference

Runtime connection is intentionally left for manual verification.
