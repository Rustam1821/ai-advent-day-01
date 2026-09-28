# Day 21 — Document Indexing

## Corpus

12 Markdown documents from The Rust Programming Language, MIT licensed.
`documents/manifest.json` records the source revision and explicit file list.
31,559 whitespace-delimited words including source code; at 500 words/page this
is about 63.1 pages. This is a volume estimate, not typographic pagination.
mdBook include directives were expanded to complete source examples.
License/attribution/manifest are excluded from indexing.

The Flutter asset loader reads the local files listed in the manifest, sorts them,
and builds one corpus snapshot for both strategies. No runtime document download.

## Pipeline

Documents → chunks → Ollama embeddings (batch of 8) → local JSON → comparison.
No chat, MCP, retrieval, similarity, Top-K or document answering.

- FixedSizeChunker: 1200 UTF-16 characters, overlap 150, section=null.
- StructureAwareChunker: Markdown headings form hierarchical section paths;
  heading-like lines in fenced code are ignored. Chunks never cross section
  boundaries. Paragraphs are packed up to 1200 characters; oversized paragraphs
  split at whitespace (hard boundary fallback). No overlap, section retained.
- Stable IDs: file stem + fixed/structure + sequence (001,002,…).
- Metadata: chunk_id, source, file, title, strategy, section, text, embedding.
- `lib/embedding_service.dart`: real Ollama /api/embed, embeddinggemma,
  768 dimensions, truncate=false. Rejects invalid/empty/non-finite vectors.
- `lib/indexing_service.dart`: batching, progress, statistics and persistence.

Each successful comparison produces a new directory under the app's Documents:
`day21/run_TIMESTAMP/index_fixed.json` and `index_structure.json`.
Each file has model/dimensions, corpus SHA-256, chunk settings, statistics and
all text/metadata/vectors. Atomic file replacement; current.json switches to the
new pair only after BOTH files are saved. Previous complete results remain if a
build fails; incomplete run directories are not loaded as a comparison.
On restart the app reads the last saved pair without calling embeddings.
Stats: document/chunk counts, average/min/max lengths, section-bearing count.
UI lets you browse chunks and shows real embedding dimensions and disk paths.

## First-time setup on Mac (manual)

Install Ollama from https://ollama.com/download/mac and open it.
Then download the embedding model once:

```sh
ollama pull embeddinggemma
```

No paid API/provider account or API key required. DeepSeek/.env is not used.
Ollama must remain running. If using the CLI rather than the Mac app, start
`ollama serve` in a separate terminal (do not start a second instance if the app
already serves port 11434). Model download is about 622 MB.

With the iOS Simulator open, from repository root:

```sh
flutter run --dart-define=EMBEDDING_URL=http://127.0.0.1:11434
```

Android emulator: use http://10.0.2.2:11434 instead. On physical phones use the
Mac LAN IP and configure Ollama to listen on that interface (OLLAMA_HOST), allow
local network access; this is not required for iOS Simulator.

## Manual check / short video

1. Open app: show 12 documents, word/page estimate, model and both chunk settings.
2. Press Build & Compare Both. Fixed is indexed first, Structure second using
   the same corpus. Show generating embeddings progress and Done.
3. Show the comparison table (scroll horizontally if necessary): chunk counts,
   lengths, sectionsPreserved.
4. Browse example chunks in FIXED SIZE: ID/file, unknown section, length, 768 dimensions.
5. Browse STRUCTURE AWARE: section paths, text preview, dimensions.
6. Copy a Saved path. To view the actual index on your Mac (iOS Simulator), run:

```sh
open -a TextEdit "PASTE_COPIED_PATH_HERE"
```

7. Fully restart Flutter: the saved comparison reappears without Build or API calls.

For physical iOS devices indexes are in the app Documents folder with Files/Finder
file sharing enabled. Simulator paths are directly accessible from the host Mac.
Each Build performs new embeddings; there is no cache/retrieval implementation.

Static verification during implementation: flutter analyze only. No app, model,
embedding requests, indexing run or tests are executed by the coding agent.

Sources:
- https://github.com/rust-lang/book (MIT; see documents/LICENSE-MIT.txt)
- https://ollama.com/library/embeddinggemma
- https://docs.ollama.com/api/embed
