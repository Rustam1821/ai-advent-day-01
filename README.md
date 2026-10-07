# Day 28 — Local RAG

Question → local Ollama embeddinggemma → local vector search → retrieved chunks
→ Ollama qwen3:4b → answer + retrieved sources.

LOCAL RAG needs no internet or DeepSeek key after models and the index are present.
No cloud embeddings, query rewrite, reranking, task state, chat memory, streaming,
retry, agent framework or automatic quality/stability benchmarks.

## Provenance and index compatibility

Restored from `Day_25` (commit `8a5da09`), inspected against original `Day_21`
(commit `11b3d76`): corpus/manifest/license, document/chunk metadata, structure-aware
chunker, JSON storage/loader, cosine retrieval and deterministic relevance filter.
The corpus is the same 14 documents: 12 Rust Book chapters and two fictional Kedr
specifications, `documents/kedr-runtime.md` and `documents/kedr-support.md`.

Day 21 already used **local Ollama embeddinggemma, 768 dimensions**, not a cloud
embedding provider. `embeddinggemma` resolves to `embeddinggemma:latest`. Documents
and questions use the same model, dimensions and `/api/embed` with `truncate: false`.
Keep the same installed embeddinggemma model used for the old index. Old metadata
has a model name but no weights digest; if you have replaced its weights, manually
rebuild. No compatibility is inferred from dimensions alone.

The index is not committed to git. It lives in the same app's Documents directory:

```text
<Application Documents>/day21/current.json               # {"run":"run_<timestamp>"}
<Application Documents>/day21/run_<timestamp>/index_structure.json
```

Vectors are stored with every chunk in `chunks[].embedding`. Loading validates
version, strategy, Ollama provider, model, dimensions, corpus SHA-256, metadata,
unique IDs and finite nonzero vectors. The actual path and chunk count appear in UI.
A compatible existing index is reused without rebuilding. Whether it still exists
in your particular Simulator's app container must be checked manually.

Missing/corrupt/incompatible index is a visible error. There is no automatic rebuild.
If needed, tap **Build / Rebuild Local Index**. This runs local document embeddings
in batches of eight, builds only the structure index and publishes the pointer after
successful saving. It reuses the old structure chunking and schema, without restoring
fixed-vs-structure comparison. Existing runs remain on disk. No rebuild has been
performed by Codex.

Retrieval embeds the original question once, computes cosine similarity locally,
keeps Top-8 candidates, filters score >=0.45 and supplies at most Top-3 chunks.
Parameters are centralized in `RetrievalConfig`. No truncation/padding of vectors.
No relevant chunks produces a visible insufficient-knowledge message and skips
both generators. A relevant chunk can still lack the answer; the prompt explicitly
asks the generator to acknowledge insufficient context.

## Setup and run — iOS Simulator

Use the existing iOS Simulator on this Mac, same app ID/container if reusing its old
index. There is no macOS target in this project. Physical phones and Android
emulators are not the target of this loopback configuration.

Prerequisites: configured Flutter/Xcode, booted iOS Simulator, Ollama installed,
`qwen3:4b` and the previous `embeddinggemma:latest` installed locally.
Execute yourself:

```sh
open -a Ollama
ollama list
flutter run --debug
```

Check both models in `ollama list`. Choose the booted iOS Simulator if Flutter asks.
For explicit selection: `flutter devices`, then `flutter run --debug -d <SIMULATOR_ID>`.
No model pull or `ollama run` is required for the already installed models.
If the app says the index is missing, tap **Build / Rebuild Local Index** and wait.
Do this before the video; it requires local embeddings but no internet.

`LocalLlmConfig` retains `OLLAMA_BASE_URL=http://localhost:11434`,
`OLLAMA_MODEL=qwen3:4b`, and a 3-minute timeout. Endpoints:

- embeddings: `http://localhost:11434/api/embed`
- generation: `http://localhost:11434/api/generate`

Only loopback HTTP addresses and the Qwen generation model are accepted. Local
clients bypass proxies and disable redirects. Existing iOS local-network ATS
permission is retained, without global arbitrary HTTP permission.

## Optional cloud comparison

The old DeepSeek HTTP integration is reduced to `CloudLlmClient`, used only by the
explicit **Compare Local vs Cloud** action. Without a key this action is disabled;
**Ask Local** remains fully available. The default model is `deepseek-flash`
(current official API model name), configurable with `DEEPSEEK_MODEL`.

To enable comparison with your existing local .env (not modified by this change):

```sh
flutter run --debug --dart-define-from-file=.env --dart-define=DEEPSEEK_MODEL=deepseek-flash
```

Comparison intentionally sends the question and retrieved document context to
`https://api.deepseek.com/chat/completions`. Ask Local never calls this provider.
There is no automatic cloud fallback.

One retrieval produces one immutable prompt containing instructions, the selected
chunks' metadata/text and original question. Both generators receive that exact
prompt. Local and cloud generation run sequentially; each stopwatch starts directly
before its generator call and ends at a complete response/error, excluding retrieval.
The UI shows separate LOCAL/CLOUD answers and seconds, with shared sources below.
A generator failure remains separate and does not hide the other result. Model
settings and output limits differ, so timings describe this demo, not a controlled
performance benchmark. First local generation may include model loading.

Local generation is non-streaming, `think:false`, displaying only final `response`.
Sources are selected by the app (file/source, section, chunk ID, score, expandable
text). They describe retrieved context, not validated citations or proof of each
claim. No chain-of-thought or automatic quality scores are shown.

## Manual verification and video

1. Show `ollama list` with both models and running Ollama.
2. Start Flutter and show Day 28, LOCAL RAG, local retrieval, embedding and generator.
3. Verify index ready; build manually only if missing/incompatible.
4. Ask Local: `Каковы правила повторной отправки событий проекта Кедр?`
5. Check answer against source text (7 repeats, 13-second interval), time and sources.
6. Ask: `Каковы ограничения размера пакета и одного события проекта Кедр?`
   Compare with retrieved source (240 events / 48 KiB; individual event 48 KiB).
7. Leave Ollama/app running, disconnect Wi-Fi and other internet connections, then
   Ask Local again. Successful query embedding + retrieval + generation shows the
   complete pipeline works offline.
8. Optional: reconnect internet, launch with a key, Compare Local vs Cloud on the
   same question. Inspect two answers, generation times and shared sources.

Quality: manually compare correctness, completeness, context adherence and invented
facts. Stability: repeat a few questions and inspect failures/format/context use.
Do not infer a stability score from a single run. No runtime results are claimed.

Error checks (optional): quit Ollama fully and Ask Local; expect a readable local
connection error. Missing model, embedding failure, mismatch, malformed index and
no relevant chunks are explicit errors. Restart Ollama; submit again. Do not remove
models or damage your index just to record an error.

## Files and dependencies

- `lib/documents.dart`: restored corpus loader and structure chunker.
- `lib/indexing_service.dart`: restored storage, optional manual structure builder.
- `lib/retrieval_service.dart`: restored index validation/cosine/filter.
- `lib/embedding_service.dart`: old embedding contract with local-only HTTP handling.
- `lib/local_llm_client.dart`, `lib/local_llm_config.dart`: reused Day 27 generation.
- `lib/rag_service.dart`: one retrieval, shared prompt, generation timing/results.
- `lib/cloud_llm_client.dart`: isolated optional DeepSeek generation.
- `lib/main.dart`: single Day 28 screen.

Restored `crypto` for corpus hashes and `path_provider` for the existing index path.
No new packages, tests or old Days 22–25 screens were added. Old task state, memory,
rewrite, citation validator, evaluation/debug panels remain removed. The local .env
file is preserved. Codex validation is limited to `flutter analyze`; no app, model,
embedding, cloud API, rebuild or runtime benchmark is executed.
