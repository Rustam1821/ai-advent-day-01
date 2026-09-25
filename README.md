# Day 20 — multi-server MCP orchestration

Two separate Dart processes/endpoints using the existing mcp_dart SDK:
- server/task_server.dart, port 3000: get_task_data, get_task_history. Owns mock data.
- server/report_server.dart, port 3001: create_task_summary, save_report. No task dataset or server-to-server calls.

lib/mcp_client_service.dart: McpServerRegistry owns two clients. Discovered tools
retain serverId, name, description and schema. Routing looks up that owner, never
broadcasts tool calls. Endpoints: TASK_MCP_URL and REPORT_MCP_URL.

lib/agent.dart: DeepSeek sees the discovered descriptions/schemas and selects
one next tool each turn (maximum 4 calls plus a final decision). No fixed report
pipeline. A status request needs only get_task_data; history only get_task_history.
A full saved report should select data → history → summary → save.
Application guards require data before summary and summary before save, and reject
mixed task IDs/repeated calls. Actual accumulated results are bound as summary/save
arguments by the orchestrator, rather than trusting LLM copies of those results.
Each result returns to DeepSeek for its next choice. Final Agent text is formatted
from actual results. It never claims a file was saved without save_report success.

UI trace retains chronological server/tool/input/output and the failed step.
On failure flow stops immediately. Connection errors are separate per server;
Task-only queries can run if Report is offline. Tool selection is model-driven
and must be verified manually; no runtime validation was performed.

## Manual launch — three terminals, all in project root

Stop the older server on port 3000 with Ctrl+C first.

1. Task MCP:
```sh
dart run server/task_server.dart
```
2. Report MCP:
```sh
dart run server/report_server.dart
```
3. Flutter (iOS Simulator already open):
```sh
flutter run --dart-define-from-file=.env --dart-define=TASK_MCP_URL=http://127.0.0.1:3000/mcp --dart-define=REPORT_MCP_URL=http://127.0.0.1:3001/mcp
```

.env needs the existing DEEPSEEK_API_KEY. No new dependencies or provider.
On fresh checkout run flutter pub get first. Android Emulator: use 10.0.2.2 for
both URLs. Physical phone: use Mac LAN IP, start each server with
MCP_HOST=0.0.0.0 MCP_ALLOWED_HOST=<MAC_LAN_IP>, same Wi-Fi and local-network permission.
MCP_PORT optionally overrides each server's default port.

## Video / manual check

1. Connect; show Task Server connected and Report Server connected.
2. Send: Подготовь полный отчёт по задаче AI-101 с историей и сохрани его.
3. Expand MCP Orchestration: Task/get_task_data → Task/get_task_history →
   Report/create_task_summary → Report/save_report. Show input/output transfer.
4. Show Agent answer and saved filename. Open file if desired:
```sh
open -a TextEdit server/reports/report_AI-101.txt
```
5. Send: Какой сейчас статус AI-102?
   Expect only Task/get_task_data, Done/Maria; no Report calls.
6. Optional: Покажи историю AI-101. Expect only Task/get_task_history.
7. Optional failure: Подготовь полный отчёт по AI-999 и сохрани его.
   Expect failed get_task_data, Flow stopped, no dependent calls.

Reports remain confined to server/reports, safe AI-numeric filenames, symlink
targets rejected. Same task overwrites its report. Old Day 19 fixed pipeline was
replaced by bounded model-driven selection. No scheduler, tests or new packages.
Only flutter analyze (including both servers) is run during implementation.
