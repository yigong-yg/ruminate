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

Language selection is automatic by default:
1. Official/manual captions — first available language
2. Auto-generated captions — first available language
3. No subtitles → fail with message

No language is implicitly preferred. Override with `SUBTITLE_LANG` to select a specific track (e.g. `SUBTITLE_LANG=zh-Hans`).

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `YOUTUBE_OUTPUT_DIR` | `~/.config/alma/memory/ingested/youtube` | Artifact output directory |
| `SUBTITLE_LANG` | (auto-detect) | Preferred subtitle language |
| `DRY_RUN` | `false` | Print artifact to stdout instead of writing |
| `SEGMENT_MINUTES` | `5` | Fallback segment length when video has no chapters |

---

## Derived Views: chew-short

`youtube-chew.sh` reads a canonical artifact and produces a compressed chew-short view (~800-1500 words).

**Input:** Canonical artifact path (positional argument). Does not re-fetch from YouTube.

**Output:**

| Mode | Behavior |
|------|----------|
| Normal | Writes `{video-id}-short.md` to `{input-dir}/chew/`. Nothing on stdout. Path printed to stderr. |
| `--dry-run` | Prints assembled prompt to stdout. No file written. |

**Idempotency:** Re-running overwrites existing chew artifact.

**Environment Variables:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CHEW_OUTPUT_DIR` | (sibling `chew/` dir of input) | Override output directory |
| `CHEW_MODEL` | `gpt-4o-mini` | OpenAI model, override with `--model` |
| `OPENAI_API_KEY` | (from `.env`) | Required for synthesis |

**Usage:**

```bash
# Preview prompt
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md --dry-run

# Generate chew-short
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md

# Different model
bash pipelines/youtube/youtube-chew.sh path/to/video-id.md --model gpt-4o
```
