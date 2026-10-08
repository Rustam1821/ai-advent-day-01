# Day 29 — Local LLM Optimization

Technical documentation RAG: question → local embeddinggemma (768) → unchanged
local cosine retrieval → same chunks → sequential BASELINE and OPTIMIZED Qwen
requests → two answers, generation metrics and shared sources.

OPTIMIZED is an experimental starting configuration. A limited real Flutter experiment is recorded below; it does not establish a universal optimum.

## Actual baseline, not guessed defaults

Day 28 POST `/api/generate` used `qwen3:4b`, `stream:false`, `think:false`, the
General RAG prompt, and **no options overrides**. BASELINE preserves that request
and the exact Day 28 prompt. Missing options remain omitted, not replaced with
arbitrary numbers.

Read-only inspection of the installed model's small manifest/parameter blobs found:

- model: `qwen3:4b`, quantization **Q4_K_M**;
- model parameters: temperature **0.6**, top_k **20**, top_p **0.95**, repeat_penalty **1**;
- no model-level num_predict or num_ctx override.

Ollama 0.34.4 source sets default `num_predict=-1` (no explicit output token cap).
Its context selection depends on the server's `OLLAMA_CONTEXT_LENGTH`, memory and
runtime policy. The actual loaded context length was not inspected by calling the
server, and no fixed value is claimed. BASELINE UI labels context as runtime-selected
and temperature/output as inherited. Keeping the same installed model and server
configuration reproduces the Day 28 behavior. Overriding OLLAMA_MODEL, replacing
weights or changing the server configuration changes that baseline.

References:
[model](https://ollama.com/library/qwen3:4b),
[0.34.4 defaults](https://github.com/ollama/ollama/blob/v0.34.4/api/types.go),
[0.34.4 environment/context](https://github.com/ollama/ollama/blob/v0.34.4/envconfig/config.go).

## Experimental configuration

`lib/llm_configuration.dart` centralizes both immutable configurations and prompt
templates. Null parameters mean inheritance; explicit values enter request options.

| Setting | BASELINE | OPTIMIZED |
| --- | --- | --- |
| Model | qwen3:4b | qwen3:4b |
| Temperature | inherited, installed model 0.6 | 0.2 |
| Maximum output tokens | inherited, runtime default -1 | 512 |
| Context window | runtime/server-selected | 8192 |
| Prompt | actual Day 28 General RAG | Technical RAG |

The optimized request sends `options: {temperature:0.2, num_predict:512, num_ctx:8192}`.
`num_predict` limits generated output, not input. 8192 is a starting budget for at
most three ~1200-character chunks plus question, metadata, prompt and answer; this
is not an exact token count or a guarantee for arbitrarily long questions.

Technical RAG asks for precise numbers/units/conditions, concise complete answers,
no invented technical details, and explicit acknowledgement of insufficient context.
Both templates use the original question and identical metadata/text snapshots.
No query rewriting or additional retrieval is introduced.

Explicit context configurations also send `truncate:false`, `shift:false` to reject
context overflow instead of silently reducing input. BASELINE keeps the original
runtime behavior and may inherit truncation/shift policy. Invalid configurations,
missing model, HTTP/context errors, timeouts and malformed responses are visible.
A `done_reason=length` answer is shown with a warning that it may be incomplete.
No automatic retries or fallback. If one generation fails, the other result remains.

This comparison changes several settings together, so it measures the combined
configuration, not the isolated effect of one parameter. Edit the simple constants
to change one variable at a time. No automatic winner or quality score is computed.

## Retrieval and index retained from Day 28

No changes to corpus, document/query embedding space, indexing algorithm or vectors.
Corpus remains 12 Rust Book chapters and two fictional Kedr specs in `documents/`.
Embedding model remains the installed `embeddinggemma:latest`, 768 dimensions.
Retrieval remains Top-8 candidates → cosine >=0.45 → at most Top-3 chunks.
One query embedding and retrieval supplies both generators; sources are shown once.
Sources describe retrieved context, not automatically validated citations.

Existing index:

```text
<Application Documents>/day21/current.json
<Application Documents>/day21/run_<timestamp>/index_structure.json
```

Existing compatible index is reused. Index loader checks schema, provider/model,
dimensions, corpus SHA-256 and vectors. Vectors are never padded/truncated.
No rebuild is required for Day 29 and none was performed. The existing manual
Build/Rebuild control remains for a missing/corrupt index; do not rebuild a ready
index for this optimization experiment. Missing index/models and no relevant
chunks are explicit errors. No relevant chunks means no generation is sent.

## Speed and resources

Each stopwatch starts immediately before its local client call and stops on the
complete response/error. Prompt construction and retrieval are excluded; request
serialization/network/loading/generation/parsing are included. Generations run
sequentially, BASELINE then OPTIMIZED, without competing requests from this app.

If returned by Ollama, UI shows `total_duration`, `load_duration`,
`prompt_eval_duration`, `eval_duration`, `prompt_eval_count`, `eval_count`, and
`done_reason`. Duration values are converted from nanoseconds to seconds. Missing
metrics are omitted; no fabricated zeros or per-request RAM values.

These timings are not RAM usage. For manual resource evaluation:

1. Open macOS Activity Monitor → Memory; observe the Ollama/model runner processes
   (include helpers, not just the menu-bar app). Observe CPU separately if useful.
2. Record memory/pressure before Compare and watch while BASELINE then OPTIMIZED
   run. Model loading, cache reuse and another resident embedding model affect this.
3. After a comparison, you can manually run `ollama ps` to see loaded model size,
   processor and context. This is a loaded-model snapshot, not exact per-request
   peak RAM or the earlier baseline state. After sequential runs it generally
   reflects the last loaded configuration.
4. For a more useful configuration-specific RAM check, temporarily set both
   configurations to the same options, run and record; then repeat for the other
   options. Record the procedure and avoid claiming precise per-request peaks.

Initial calls can include cold loading; changing num_ctx can reload the runner.
Later calls may benefit from caches. Repeat comparisons and inspect load_duration;
fixed baseline-first order is an experiment limitation, not proof of improvement.
Quality: compare correctness, completeness, source adherence and hallucinations.
Stability: manually repeat several questions; inspect errors and answer consistency.

## Optional quantization experiment

Only `qwen3:4b` was found in the standard local Qwen3 manifest directory, with
Q4_K_M. No additional weights have been downloaded. The official library has
[`qwen3:4b-q8_0`](https://ollama.com/library/qwen3:4b-q8_0), but it is not currently
installed in that inspected directory. Use an alternative only after you yourself
have made it available locally; this project does not download or convert weights.

Model names belong to each configuration. `OPTIMIZED_MODEL` can select an installed
Qwen3 4B quantized tag. The client allows only local Qwen3 4B / quantization tags,
not arbitrary remote model names. Missing model produces an error.

Both default configurations use the same weights, so their comparison **is not a
quantization comparison**. To isolate quantization, first edit OPTIMIZED to match
BASELINE's prompt and options exactly (General RAG, all three option fields null),
and change only its model. Then use the same retrieved context. Confirm that the
variant has matching model defaults too; otherwise set identical explicit options
on both configurations. Do not combine weight precision changes with different
sampling/context/prompt settings and attribute the result to quantization alone.

## Manual setup and demonstration — iOS Simulator

Use the same iOS Simulator/app container as Day 28 to retain its index. Prerequisites:
Flutter/Xcode ready, Simulator booted, Ollama installed/running and both existing
models present: qwen3:4b and embeddinggemma:latest.

Run yourself, from the project root:

```sh
open -a Ollama
ollama list
flutter run --debug
```

No .env or cloud key is needed. Select the iOS Simulator if Flutter asks. Explicit
selection is `flutter run --debug -d <SIMULATOR_ID>` (get ID with `flutter devices`).
Loopback endpoints remain `http://localhost:11434/api/embed` and `/api/generate`.
Existing iOS local-network permissions remain. Physical phones/Android are not
configured by this demo; no macOS desktop target was added.

1. Verify Index ready. Show Provider: Ollama, model and Task: Local RAG.
2. Ask `Каковы правила повторной отправки событий проекта Кедр?` and press Compare.
3. Wait for both results; show settings, answers, seconds, metrics and shared sources.
4. Repeat with `Каковы ограничения размера пакета и одного события проекта Кедр?`.
5. Check exact numbers/conditions in the expanded sources; repeat questions to
   assess consistency. Record Activity Monitor observations separately.
6. With the app/Ollama still running, you may disconnect internet and Compare again.
   The whole pipeline is local.

Record conclusions only after these real runs. Measured results are recorded below; repeat them yourself to assess consistency.

## Changes and verification

Added `llm_configuration.dart`; updated the existing local client, `rag_service.dart`,
comparison UI, README, app labels, launch configuration and pubspec description.
Removed `cloud_llm_client.dart` and all cloud comparison/key UI; local .env is untouched.
No dependency additions/removals, new RAG capabilities or automated tests.
Runtime execution was subsequently explicitly authorized by the user. The limited
Flutter experiment below was performed; no model download or index rebuild was performed.

## Sharing manual results

The technical provider/index/rebuild block is collapsed under **Details** by default.
In debug mode, after Compare completes, Terminal (`flutter run`) or VS Code Debug
Console prints a report between `[DAY29] BEGIN COMPARISON RESULT` and
`[DAY29] END COMPARISON RESULT`. Copy that complete block to share results: it includes
the question, both answers/errors, submitted options, generation seconds, raw Ollama
metrics (durations in ns), and the shared source metadata/text/scores. Logs report
inherited options honestly rather than guessing effective runtime values. No log
file is created; logging is disabled in profile/release mode.

### Follow-up manual experiment

The first supplied comparison produced verbose reasoning in both response fields;
OPTIMIZED stopped at 512 tokens (`done_reason: length`) before finishing the answer.
This does not establish an improvement. The optimized template now ends with Qwen's
`/no_think` instruction; baseline and all generation options remain unchanged.
Repeat the same question to check whether final-answer behavior improves. Debug log
lines are wrapped at 180 characters to avoid long console-line truncation.

The second supplied run still exhausted 512 output tokens without a final optimized
answer (16.14 s versus baseline 13.17 s). Read-only inspection showed the installed
Ollama template always opening `<think>` at the assistant prefix, regardless of
`think:false`. OPTIMIZED now additionally sends a request-level Qwen chat template
with an empty closed `<think>...</think>` prefix (hard non-thinking formatting).
BASELINE keeps its installed template unchanged. The override is included in debug
logs and noted in the result card. No model weights or persistent Ollama configuration are modified. Subsequent
measurements below supersede this intermediate request-template attempt.

The second manual run still exhausted OPTIMIZED's 512 tokens on reasoning. Read-only
inspection found the installed Qwen template always ends with an open `<think>` block.
OPTIMIZED now overrides the request's Ollama `template` with Qwen chat delimiters and
a pre-closed empty thinking block, while retaining `/no_think` and all options.
BASELINE keeps the installed template. This additional template change is part of the
combined configuration experiment; its effectiveness must be checked manually.

## Final tested configuration and limited runtime result

After explicit user authorization, three Flutter UI comparisons were performed.
A fourth accidental text-input request was rejected at retrieval and sent no
generation. Both ordinary template override and raw Qwen non-thinking prefix alone
still produced reasoning; neither was retained as evidence of improvement.

The final OPTIMIZED request retains 0.2 / 512 / 8192 but uses:

- short Russian technical instructions (answer in the question's language);
- manually rendered Qwen chat prefix via `raw:true` to bypass installed templating;
- a JSON schema via `format` requiring a single string field `answer`;
- validation/parsing of that field as the final UI answer.

This constrains generation rather than merely hiding previously produced reasoning.
An incomplete JSON/token-limit result becomes an explicit error, not a fabricated
answer. BASELINE's request and prompt remain unchanged. Changes to the final
format are logged as `raw_qwen_format` and `structured_answer_json`. The UI stays
plain text: no separate citation architecture or JSON editor.

Final comparison in the iOS Simulator, on the same retrieved chunks:

| Question | Baseline | Optimized | Generated tokens | Completion |
| --- | --- | --- | --- | --- |
| Каковы ограничения размера пакета и одного события проекта Кедр? | 30.59 s | 4.65 s | 687 / 45 | stop / stop |

Optimized final answer: «В проекте Кедр один пакет передачи содержит не более
240 событий. Максимальный размер одного события — 48 КиБ.» Correctly matches
`kedr-runtime_structure_005`; no reasoning text or truncation appeared.

Final optimized API metrics: load 1.075 s, prompt evaluation 1.845 s, generation
1.723 s, prompt tokens 580, generated tokens 45. Baseline also arrived at correct
facts but exposed extensive reasoning before its final answer. This validates one
question with the final configuration, not a stability benchmark or guaranteed
speedup. Other questions and repeated trials still need checking.

A loaded-model snapshot during the baseline showed 3.2 GB, context 4096, 100% GPU.
This is `ollama ps` model-size reporting, not measured per-request RAM. No accurate
peak RAM or Activity Monitor measurement was obtained; no RAM reduction is claimed.
