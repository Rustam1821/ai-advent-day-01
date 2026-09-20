# Day 18 — server-side monitoring

Existing `mcp_dart` SDK + Streamable HTTP + DeepSeek tool-calling flow.
No new dependencies. Day 17 task records/get_task_status removed.

## Run manually from the repository root

Terminal 1 (leave running):

```sh
dart run server/task_server.dart
```

Terminal 2 (iOS simulator already open):

```sh
flutter run --dart-define-from-file=.env --dart-define=MCP_URL=http://127.0.0.1:3000/mcp
```

`.env`: `DEEPSEEK_API_KEY=your_key`. The model and API are unchanged.
For a fresh checkout, run `flutter pub get` before starting the server.
Android emulator URL: `http://10.0.2.2:3000/mcp` (debug HTTP enabled).
Physical phone: same Wi-Fi, Mac LAN IP in URL; start server with
`MCP_HOST=0.0.0.0 MCP_ALLOWED_HOST=<MAC_LAN_IP> dart run server/task_server.dart`.
Allow local networking on iOS. No Node, database or cloud setup needed.

## Video / manual check

1. Start both processes; press Connect in Flutter.
2. Send: `Запусти мониторинг demo-monitor каждые 10 секунд.`
3. Show Agent confirmation and Last MCP Tool Call: schedule_monitor, name,
   intervalSeconds, persisted job. First execution occurs after the interval.
4. In the Flutter terminal press `q` and close the app if still visible.
   Leave the SERVER terminal open and the Mac awake for 30–40 seconds.
   Server prints a timestamp/value after each committed scheduled execution.
5. Run the Flutter command again, press Connect.
6. Send: `Дай сводку по demo-monitor.`
7. Show Agent summary and Last MCP Tool Call: get_monitor_summary, runs,
   averageValue, latestValue, minValue/maxValue and timestamps.
   Counts depend on actual elapsed time, not on client requests.
8. To finish: `Останови мониторинг demo-monitor.` The stop tool preserves history.

Optional persistence proof: BEFORE stopping the job, Ctrl+C in server terminal,
restart with the same command and data path, reconnect Flutter, ask for summary.
Old runs remain; the next execution occurs one interval after server restart.
Unknown name returns found=false. Before the first run, runs=0 and metrics=null.

## Implementation

- `server/task_server.dart`: registers only schedule_monitor(name, intervalSeconds),
  get_monitor_summary(name), stop_monitor(name). All sessions share one store/scheduler.
- `server/monitor_store.dart`: one 1-second timer checks enabled jobs' nextRunAt.
  Actual runs generate the repeating deterministic sequence 68,72,75,70.
  No runs are created when requesting summaries or for server downtime.
- `server/data/monitors.json`: jobs and results in one atomically replaced JSON file.
  Path defaults relative to the server script; override with MCP_DATA_FILE.
  Run only one server process per data file (no cross-process locking).
- Job: id, name, intervalSeconds, createdAt, lastRunAt, nextRunAt, enabled.
  Result: jobId, timestamp (UTC), value.
- A shared async queue serializes scheduler and tool disk operations. Each operation
  reads persisted state; a run updates metadata and results in the same commit.
- Summary computes count, first/latest, min/max, average and timestamps on server.
- Startup restores jobs/results and reschedules enabled jobs from current time.
  Missing file starts empty; corrupt JSON is preserved as .corrupt-TIMESTAMP and
  replaced with empty storage, with a warning. Disk access failures disable scheduling
  and produce tool errors rather than silently claiming persistence.
- Repeated schedule for an active name returns the existing job unchanged.
  Scheduling a stopped name resumes it with history; it does not reset results.
- Flutter has no scheduler/polling and no metric dataset. Agent discovers schemas,
  requests one MCP action, passes result to DeepSeek for a final response.

For a clean repeat of the video, use a new monitor name, or stop the server and
remove `server/data/monitors.json` (this deletes all demo history) before restarting.
Static analysis only during implementation; runtime verification is manual.
