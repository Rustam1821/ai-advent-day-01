# Day 25 — Mini Chat with RAG

## Architecture

- `lib/chat_session.dart`: ChatMessage (id, user/assistant role, content, timestamp,
  grounded answer/citations, source snapshots, retrieval query/scores and error flag),
  ChatSession, TaskState and atomic JSON persistence.
- Full history is displayed and persisted in app Documents/chat_session.json together
  with goal/clarifications/constraints/terms. Source snapshots omit vectors; old
  citations are checked against those snapshots on load, without retrieval/API calls.
- History records what was said. Task State holds current user decisions. RAG index
  remains the documentary knowledge source. Neither history nor state replaces it.
- `TaskStateService` in lib/rag_service.dart combines state extraction and query
  rewrite into one strict JSON LLM request: taskState + retrievalQuery. It receives
  previous state, current user text, and user messages from the last 6 non-error
  messages (max 2000 chars per message). Assistant answers are excluded from state
  extraction to prevent documentary facts entering user state. Final generation
  still receives both roles in the recent window. Current question is not duplicated.
- State is bounded: goal <=500 chars, each list <=8 items of <=250 chars. Prompt
  preserves the long-lived goal, replaces explicitly corrected values, merges
  duplicates, and prohibits copying assistant facts into user constraints. Invalid
  JSON/state fails visibly, retains previous state, and does not silently continue.
  Semantic extraction is model-driven; verify corrections during manual scenarios.
- Every Send saves the user message, updates/saves state, embeds the standalone
  query, loads the existing Structure index, runs cosine Top-8, threshold 0.45,
  max Top-3, and generates a grounded answer. No non-RAG routing exists. Operational
  errors stop the turn visibly rather than claiming retrieval succeeded.
- Final prompt separates TASK STATE, RECENT CONVERSATION, SOURCES and CURRENT USER
  QUESTION. User constraints are not document facts; previous assistant answers are
  not authoritative sources. Final citations may refer only to current filtered chunks.
- Day 24 GroundingValidator unchanged: exact IDs/source/section, quote substring
  after whitespace normalization. Malformed answers/invalid citations are hidden.
  Quotes prove textual provenance, not semantic entailment; inspect meaning manually.
- Ordinary turn: 1 state/rewrite LLM + 1 embedding + 1 final LLM. Zero filtered chunks:
  final LLM skipped; deterministic “не знаю” + clarification, empty sources. If context
  passes threshold but lacks the answer, final LLM may also abstain.
- User turn is persisted before APIs; updated state before retrieval; response after
  validation. A interrupted turn is not auto-replayed on restart. Send a follow-up.
  Save failures remain visible with Retry storage; load failures block Send to avoid
  overwriting unread history. New conversation writes an empty session, leaves index
  and corpus untouched. No chat list, summarizer, MCP or extra memory layers.

## Changes and launch

Day 24 evaluation/comparison controls replaced by chat, compact Task State and
per-answer RAG details. Existing control dataset remains available in repository.
Corpus, embeddinggemma 768, index, grounding validator and dependencies unchanged.
No rebuild required for an existing current index. If missing, expand index status
near top of chat → Build/Rebuild Index.

Keep Ollama running with embeddinggemma installed. Existing `.env`:
DEEPSEEK_API_KEY required, DEEPSEEK_MODEL optional (same default deepseek-v4-flash).
With iOS Simulator already open, from project root:

```sh
flutter run --dart-define-from-file=.env --dart-define=EMBEDDING_URL=http://127.0.0.1:11434
```

Android Emulator: use http://10.0.2.2:11434. Nothing new to install.

## Manual scenarios

Send each row as a separate message and wait for completion. Inspect sources/quotes
and RAG details on every factual answer, including late turns. These are proposed
manual scenarios, not executed results. Sources live in documents/kedr-runtime.md
and documents/kedr-support.md. Insufficient context or invalid citations are visible
failures to obtain the desired factual answer, not successful scenario verification.

### Scenario 1 — sender configuration (12 user turns)

Start with New conversation.

| Turn | Exact user message | Check |
|---|---|---|
| 1 | Хочу подготовить настройки отправителя событий проекта Кедр. Каковы документированные правила повторной отправки? | Long-lived goal; retrieval retry section (7 repeats, 13 seconds). |
| 2 | Настраиваем тестовую среду. Какие лимиты пакета нужно учитывать? | clarification environment=test; packet limits 240 events/48 KiB. |
| 3 | Буду называть отправитель «курьером». Какой максимум повторов поддерживается для него? | term курьер=отправитель; follow-up + fresh retrieval. |
| 4 | Для нашей конфигурации ограничим повторы пятью. Это укладывается в документацию? | constraint 5 user-selected vs documented 7. |
| 5 | Ещё ограничение: в пакете не больше 100 событий. Это допустимо? | second constraint 100 vs documented 240. |
| 6 | А сколько ему ждать между повторами? | resolve ему via state/recent history; 13 seconds. |
| 7 | Нет, среду меняем с тестовой на production. Напомни правила повторов для курьера, не придумывая отдельные production-правила. | replace old environment, retain goal/alias/constraints. |
| 8 | Исправление: максимум повторов у нас теперь 3, а не 5. Сравни с документированным максимумом. | replace constraint 5→3, preserve 100 events. |
| 9 | А что происходит после их исчерпания? | follow-up retry exhaustion → manual queue. |
| 10 | Каков максимальный размер одного события для него? | alias survives recent-window turnover; 48 KiB. |
| 11 | Сравни наш лимит пакета с документированным и напомни ограничение размера события. | old constraint 100 retained, sources refreshed (240/48 KiB). |
| 12 | Подведи итог настройки курьера для выбранной среды: наши ограничения на повторы и пакет, документированные пределы и пауза. | original goal; production, 3 retries, 100 events; cite retrieved limits, no stale 5. |

### Scenario 2 — on-call memo (12 user turns)

Press New conversation first; verify empty chat and all four empty state fields.

| Turn | Exact user message | Check |
|---|---|---|
| 1 | Хочу составить памятку дежурному проекта Кедр по инцидентам и восстановлению. Кто принимает первичные инциденты? | new goal, no sender state; Север-4 source. |
| 2 | Памятка пока для опытных сотрудников. Какой канал используется для эскалации? | audience clarification; #kedr-p1. |
| 3 | Буду называть подтверждение инцидента «квитанцией». Какой срок у квитанции по регламенту? | term, 11 minutes; support section. |
| 4 | Наш внутренний целевой срок квитанции — 8 минут. Он укладывается в регламент? | user target 8 vs documentary maximum 11. |
| 5 | И не называй квитанцию устранением причины. Что именно означает подтверждение? | constraint distinguishing acknowledgement vs repair. |
| 6 | А кто должен её дать? | follow-up to acknowledgement; duty role, not invented role. |
| 7 | Исправляю аудиторию: памятка для новичков, а не опытных сотрудников. Объясни им смысл квитанции. | replace audience; retained term and constraint. |
| 8 | Целевой срок меняем с 8 на 5 минут. Сравни новый срок с регламентом. | replace target, no stale 8. |
| 9 | Под «учением» дальше понимаю учебное восстановление. Когда оно проводится? | second term; first Friday, 09:15 UTC. |
| 10 | А кто отвечает за него? | follow-up учение → Север-4. |
| 11 | Учение заменяет окно развёртывания или у него своё расписание? | cross-file retrieval; distinct Tuesday 02:40 UTC vs first Friday 09:15 UTC. |
| 12 | Заверши памятку для выбранной аудитории: квитанция, наш целевой срок, регламентный срок и отличие подтверждения от устранения причины. | goal retained; novices, target 5 vs documented 11, correct meaning and sources. |

## Persistence check and short video

1. Run scenario 1 turns 1–6; show Goal, constraints, alias, and turn 6 RAG query/quotes.
2. Send turns 7–8; show production replaces test, and 3 replaces 5.
3. Finish 9–12; show sources still present and original goal retained.
4. Wait for response/save (no storage error). Stop and restart app using same launch
   configuration and same simulator/device; do not uninstall or clear app data.
5. Show old messages, their sources/quotes, and restored Task State.
6. Send “А какой теперь наш лимит повторов для курьера и какой предел в документации?”
   Verify 3 vs 7, a fresh standalone query and fresh citations without re-explaining goal.
7. Press New conversation; verify history/state cleared, index still ready.
8. Run scenario 2 separately in full. For a short recording show 1, 3–4, 7–8, 10, 12
   as excerpts of the real sequence; all 12 exact inputs are documented above.

Runtime scenarios were subsequently authorized by the user. The shared threshold was
calibrated to 0.45 (retry query ~0.58; out-of-corpus Titan query ~0.21). DeepSeek JSON
output mode is enabled for state/rewrite and final generation. Candidate scores before
filtering are visible in RAG details. No automated test suite was added.

Runtime verification results: [docs/day25-runtime.md](docs/day25-runtime.md).
