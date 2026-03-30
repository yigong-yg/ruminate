# YouTube Ingestion

Extracts metadata and transcript from a YouTube video and produces a structured canonical artifact (frontmatter + cleaned transcript organized by chapters).

MVP ships the structural layer only. Anchor summaries (1-2 sentence chapter anchors via LLM) are future work per ADR-010.

## Inputs

| Source | Path | Required |
|--------|------|----------|
| YouTube URL | First argument | Yes |
| yt-dlp | On PATH | Yes |

## Output

| Mode | Behavior |
|------|----------|
| Normal | Artifact written to `$YOUTUBE_OUTPUT_DIR/{video-id}.md`. Nothing on stdout. Artifact path printed to stderr. |
| `--dry-run` | Artifact printed to stdout. No file written. |

Default output directory: `~/.config/alma/memory/ingested/youtube/`

## Dependencies

- `yt-dlp` (required — extracts metadata and subtitles)
- `jq` (required — JSON processing)
- `bash`, `sed`, `awk` (transcript segmenting)

## State Ownership

This job owns:
- Output directory: `~/.config/alma/memory/ingested/youtube/`
- No watermark or progress file. Each run is independent per video.

Temporary files are created in a temp directory during processing and cleaned up on exit.

## Idempotency

Re-ingesting the same URL **overwrites** the existing artifact. The artifact for a given video ID is always the latest ingestion.

Not implemented:
- `--force` / `--no-clobber` flags
- Batch URL processing
- Auto-fetch from playlists or channels

## Failure Behavior

| Failure | Result |
|---------|--------|
| yt-dlp not on PATH | Exit 1, no artifact |
| Invalid/private URL | Exit 1, no artifact |
| No subtitles available | Exit 1, clear error (Whisper out of scope for MVP) |
| Disk write error | Exit 1, no partial file (atomic write via temp+rename) |

## Subtitle Language

Official captions are always preferred over auto-generated. Within each source, language is chosen by priority:

1. `SUBTITLE_LANG` explicit override (e.g. `SUBTITLE_LANG=zh-Hans`)
2. Video's original language (from yt-dlp `.language` metadata), with prefix matching for variants like `en-US`
3. `en` fallback
4. First available track

If no official track matches any priority, the same policy is applied to auto-generated captions. If neither source has any tracks, the script fails with a clear error.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `YOUTUBE_OUTPUT_DIR` | `~/.config/alma/memory/ingested/youtube` | Artifact output directory |
| `SUBTITLE_LANG` | (auto-detect) | Preferred subtitle language |
| `DRY_RUN` | `false` | Print artifact to stdout instead of writing |
| `SEGMENT_MINUTES` | `5` | Fallback segment length when video has no chapters |

---

## Derived Views: chew-short

`youtube-chew.sh` reads a canonical artifact and produces a distilled chew-short view (~1000-2000 words). This is distillation, not summarization — it extracts the narrative skeleton and preserves specific anchors, not generic opinions.

**Input:** Canonical artifact path (positional argument). Does not re-fetch from YouTube.

**Output:**

| Mode | Behavior |
|------|----------|
| Normal | Writes `{video-id}-short.md` to `{input-dir}/chew/`. Nothing on stdout. Path printed to stderr. |
| `--dry-run` | Prints assembled prompt to stdout. No file written. |

**Output structure:**
- `## Core Throughline` — actual thesis and stakes, not "X discusses Y"
- `## Narrative Arc` — 5-8 key turning points with concrete anchors. Chinese sources include original-language fragments
- `## Precision Anchors` — 10-20 specific information nodes (people, orgs, years, papers, decisions)
- `## Tensions & Contrarian Claims` — sharp edges preserved, not smoothed

**Source coverage:**

Long canonical artifacts may be truncated before synthesis to stay within model token/prompt limits (`MAX_INPUT_CHARS`, default 30000). The artifact frontmatter always records whether truncation occurred:
- `source_truncated: true|false`
- `source_chars_used` / `source_chars_total`

**Anti-hallucination constraints:**
- No quotation marks in output (no quotes section)
- Chinese sources require original-language fragments as grounding proof
- Generic statements ("X emphasizes Y") are explicitly prohibited

**Idempotency:** Re-running overwrites existing chew artifact.

**Environment Variables:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CHEW_OUTPUT_DIR` | (sibling `chew/` dir of input) | Override output directory |
| `CHEW_MODEL` | `gpt-4o` | OpenAI model, override with `--model` |
| `OPENAI_API_KEY` | (from `.env`) | Required for synthesis |

**Usage:**

```bash
# Preview prompt
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md --dry-run

# Generate chew-short
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md

# Different model
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md --model gpt-4o-mini
```
