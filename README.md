# Day 24 — Grounded RAG

Reuses Day 23: Structure Aware disk index, corpus, Ollama embeddinggemma 768,
query rewrite, cosine Top-8, threshold 0.60, at most 3 filtered chunks.
No corpus/model changes, dependencies or required index rebuild. BASE comparison
removed. Retrieval details are collapsed; answers, verified sources and quotes
are the main UI.

## Generation and verification

The existing DeepSeek generation uses a strict JSON prompt with defensive parsing:

```json
{"answer":"...","isInsufficientContext":false,"clarificationRequest":null,
 "citations":[{"chunkId":"...","source":"documents/...","section":"...","quote":"..."}]}
```

GroundedAnswer contains answer, citations, isInsufficientContext and optional
clarificationRequest. Citation contains source, nullable section, chunkId, quote.
Only filtered chunks are sent, with explicit chunkId/source/section/text fields.
Prompt requires context-only facts and short exact supporting quotes, forbids
invented sources/knowledge and treats documents as untrusted data, not commands.
Answer and citations are generated in one request, without repair or judge calls.

GroundingValidator (`lib/grounded_answer.dart`) checks required fields, at least
one citation for factual answers, exact chunk ID/source/section against the sent
context, and quote substring after trim and whitespace collapse (including line
breaks). Duplicate quotes per chunk are removed. Any invalid citation or malformed
JSON rejects the entire answer with a debug reason; unverified answer text is hidden.
Technical validation proves quote existence, not semantic support of the answer.
The user marks Answer supported by quotes: Yes / No after reading the answer.

Zero chunks after filtering produces a deterministic refusal and skips final LLM:
“Я не знаю ответа на основании доступной базы знаний.”
“Пожалуйста, уточните вопрос или укажите компонент/проект.”
Citations are empty. Rewrite and embedding still run. If filtered context exists
but does not answer the question, the LLM can also abstain; its refusal is replaced
with the same safe text. Retrieval details distinguish whether final LLM was requested.

## Launch manually

Keep the existing Ollama running with embeddinggemma installed. Existing `.env`
needs DEEPSEEK_API_KEY; optional DEEPSEEK_MODEL retains its existing behavior.
From the project root, with iOS Simulator open:

```sh
flutter run --dart-define-from-file=.env --dart-define=EMBEDDING_URL=http://127.0.0.1:11434
```

For Android Emulator use http://10.0.2.2:11434. If index is missing, expand its
status at the top of the app and press Build/Rebuild Index. Existing Day 22/23
index remains compatible; changing evaluation questions does not affect it.

## Ten-question manual evaluation

`evaluation/questions.json` reuses questions 1–9, replaces 10 with an intentional
negative question about methane lakes on Titan. Expectations are UI-only.

For each question select it, read Expected facts / sources, press Ask. For positive
answers inspect Source present / Quote present / Quote exists in chunk, then read
quotes and mark semantic support Yes/No. Insufficient context on a positive is
shown as unanswered, not a passed citation check. Errors are recorded separately.
Evaluation keeps outcomes/manual marks for this session; selecting a completed
question restores its result. Rerunning resets its manual mark. No batch API calls.

Negative #10 expects refusal, clarification and no sources. Check Retrieval details:
if Selected=0, Final LLM must be not called. The question is outside corpus, but
zero retrieval hits cannot be guaranteed without runtime scores. If any pass,
the final LLM may abstain instead; that does not demonstrate the zero-hit guard.
Threshold is unchanged and no question-specific retrieval rule is added.

## Short video

1. Open Day 24 — Grounded RAG; confirm index ready.
2. Choose #1 (Kedr retries); show expected 7 retries/13 seconds; press Ask.
3. Show answer, source/section/chunkId/exact quote and technical validation.
4. Compare meaning yourself; mark Yes or No accordingly.
5. Choose #10 (Titan), Ask; show refusal + clarification and no sources.
6. Expand Retrieval details to show threshold, selected count and final LLM status.
7. Show Evaluation with the ten questions; run all ten manually for full verification.

Only flutter analyze is run by the coding agent. No tests, app launch, embeddings,
LLM requests, index rebuild or runtime scenarios are executed during implementation.
