# Day 23 — Query Rewrite + Similarity relevance filter

Reuses Day 21–22 Structure Aware index, corpus, metadata, disk loading and
Ollama embeddinggemma (768 dimensions). No corpus/model changes or required
rebuild if the Day 22 index is already available.

## Pipelines

- BASE: original question → embedding → cosine similarity → Top-3 → context → LLM.
  No rewrite or threshold.
- IMPROVED: original question → one LLM query rewrite → rewritten-query embedding
  → cosine similarity Top-8 → score >= 0.60 → at most 3 chunks → context → LLM.
- Constants live in RetrievalConfig, filter in RelevanceFilter
  (`lib/retrieval_service.dart`). Candidates retain descending similarity order.
  The 0.60 threshold is an initial moderately selective setting, not calibrated
  against runtime scores. It does not guarantee better answers; inspect actual
  scores and sources manually. This is a threshold filter, not an ML reranker.
- Fewer than three passing chunks are used as-is. Zero passing chunks produce
  an explicit insufficient-context response without final LLM or fallback.
- QueryRewriteService (`lib/rag_service.dart`) uses the existing DeepSeek model.
  It asks for one standalone search query, preserving meaning/names/constraints,
  removing conversational filler, without answering or inventing missing context.
  There is no chat history. Failed rewrite is shown, never silently bypassed.
- Final generation in both modes uses the original question and sources JSON,
  identical grounding instructions/model/temperature=0.2/max_tokens=1000.
  Rewritten query is used only for retrieval. No prior answers or expected facts
  are sent to either generation/rewrite request.
- Each BASE run uses one embedding + one final LLM call. IMPROVED adds one rewrite
  LLM call (and skips final generation if the filter is empty).

## UI and questions

Run BASE / Run IMPROVED preserve answers for the same question. Editing the
question clears results. Compare BASE vs IMPROVED runs just the selected question,
sequentially. Each result shows its original query, sources and scores. IMPROVED
also shows rewritten query, BEFORE FILTER candidates, threshold, passed count,
AFTER FILTER selection and answer. Expand source lists for metadata/text previews.
Selections are shown even if final generation fails; errors remain explicit.

The same ten questions in `evaluation/questions.json` retain predefined expected
facts/sources. Question 1 is now conversational (Kedr event retry count and delay).
It is a useful starting point for both rewrite and filtering demonstration;
actual improvements/chunk counts must be checked manually, not presumed.
Question 9 still combines backup interval and log retention across two documents.

## Manual launch

Keep Ollama running on Mac. If the existing model is missing, download it once:

```sh
ollama pull embeddinggemma
```

Keep `DEEPSEEK_API_KEY` in the existing ignored `.env` file. Optional
`DEEPSEEK_MODEL` overrides the existing default `deepseek-v4-flash`.
From project root, with your iOS Simulator open:

```sh
flutter run --dart-define-from-file=.env --dart-define=EMBEDDING_URL=http://127.0.0.1:11434
```

Android Emulator: use `http://10.0.2.2:11434` instead. Both modes need Ollama and
DeepSeek. No MCP, new dependencies, model downloads beyond the existing embedding
model, or separate servers added.

## Manual check / short video

1. Open Day 23 — Improved RAG. Confirm Structure index ready. Only if missing/stale,
   expand the index status at the top → Build/Rebuild Index → wait until ready.
   The existing builder still saves both strategies; retrieval uses Structure.
2. Select control question 1. Show its question, expected 7 retries/13 seconds,
   and expected source kedr-runtime.md / Повторные попытки.
3. Press Run BASE. Show answer; expand BASE retrieved chunks for files, sections,
   scores and previews. Collapse it afterwards to keep the answer visible.
4. Without editing the question, press Run IMPROVED. Show original and rewritten
   queries. Expand BEFORE FILTER to show up to 8 candidates and their scores.
5. Collapse BEFORE FILTER; show threshold 0.60 and passed count. Expand AFTER FILTER:
   only passing chunks, at most 3. It can legitimately contain fewer or zero.
6. Collapse source lists and compare BASE and IMPROVED answers with expected facts.
   Similar answers are possible; the visible pipeline differences are the proof.

Only flutter analyze is permitted during implementation. No tests, application
launch, index rebuilding or real API calls are performed by the coding agent.
