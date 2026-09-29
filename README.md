# Day 22 — first RAG

Reuses Day 21 corpus, chunkers, embeddings and disk format. Main index is
`day21/run_TIMESTAMP/index_structure.json`, located through `current.json`
in the app Documents directory. Heading metadata makes this index easy to inspect.

- IndexRepository (`lib/retrieval_service.dart`) loads only Structure from disk,
  validates metadata/vectors/model/dimensions and corpus hash. Missing/stale/corrupt
  indexes produce a visible error; use Build/Rebuild Index.
- EmbeddingService unchanged: Ollama embeddinggemma, 768 dimensions, /api/embed.
  Query uses the same raw-text embedding method as the indexed documents.
- RetrievalService: cosine = dot/(norm*norm), all chunks scored, descending sort,
  fixed Top-K=3; no keyword rules, reranker, threshold or vector database.
- RagService: OFF → question → DeepSeek only. ON → load index → query embedding
  → Top-K → sources JSON + original question → same DeepSeek model.
- LlmService uses identical temperature=0.2/max_tokens=1000/thinking disabled in
  both modes. Requests have no chat history; earlier RAG results/expected answers
  never leak into the baseline. Grounding instructions apply to ON only.
- Retrieved metadata/text/scores appear next to answers. These are supplied
  sources, not a claim that each source was cited or used by the model.
- RAG failures are visible, never silently replaced by a baseline answer.

## Corpus and controls

Original Rust Book documents retained. Added two original, explicitly fictional
internal specifications: documents/kedr-runtime.md and kedr-support.md.
**Rebuild is required once for Day 22**; old Day 21 corpus hashes are rejected.
The current manifest lists all 14 documents. New docs are not Rust Book content.

`evaluation/questions.json` holds 10 questions with predefined expectedFacts and
expectedSources (not indexed and never included in prompts). Eight direct facts
from different sections; two cross-document questions. No automatic judge or
batch evaluation. Dropdown selects one question; Compare Both executes only it.

## Setup / run manually

Keep Ollama open on Mac; if not installed use https://ollama.com/download/mac.
Download model once if not already available:

```sh
ollama pull embeddinggemma
```

`.env` must contain `DEEPSEEK_API_KEY=your_key`. Do not commit this file.
Default LLM remains deepseek-v4-flash; optional DEEPSEEK_MODEL override.
From project root, with iOS Simulator open:

```sh
flutter run --dart-define-from-file=.env --dart-define=EMBEDDING_URL=http://127.0.0.1:11434
```

Android Emulator: replace the embedding URL host with 10.0.2.2.
No MCP servers or new packages required. Ollama is needed for indexing and RAG ON;
RAG OFF only needs DeepSeek. Index loading at screen startup does not add context
to OFF requests or perform embedding/retrieval.

## Manual check / video

1. Expand the index status, press Build/Rebuild Index, wait until saved. This is
   the original Day 21 build for both strategies; only Structure is retrieved.
2. Select question 1 about Kedr retries. Show expected 7 attempts/13 seconds and
   expected source. These expectations remain UI-only.
3. Press Without RAG. Show the baseline (it may say it does not know).
4. Without changing the question, press With RAG.
5. Expand Retrieved Context: file/section/score/text for three actual retrieved chunks.
6. Show the two answers and compare with the predefined facts. Baseline may guess;
   retrieval/model output is not guaranteed and must be inspected manually.
7. Open the dropdown to show all 10 prepared questions. Optionally choose question 9
   (backup interval + log retention) and Compare Both; no automatic run of all questions.

Day 21 comparison/chunk browser removed from active UI; indexing remains available.
No added dependencies. Only flutter analyze is run during implementation;
no API calls, index builds, app runs or automated tests.
