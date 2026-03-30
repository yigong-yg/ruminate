# YouTube Ingestion

Extracts metadata and transcript from a YouTube video and produces a structured canonical artifact (frontmatter + cleaned transcript organized by chapters).

MVP ships the structural layer only. Anchor summaries (1-2 sentence chapter anchors via LLM) are future work per ADR-010.

## Inputs

| Source | Path | Required |
|--------|------|----------|
| YouTube URL | First argument | Yes |
| yt-dlp | On PATH | Yes |

## Output

Canonical artifact written to `$YOUTUBE_OUTPUT_DIR/{video-id}.md`
(default: `~/.config/alma/memory/ingested/youtube/`)

Nothing on stdout. Artifact path printed to stderr.

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
1. Official/manual captions in any available language
2. Auto-generated captions (prefer `en` if available, else first available)
3. No subtitles → fail with message

Override with `SUBTITLE_LANG` to prefer a specific language track (e.g. `SUBTITLE_LANG=zh-Hans`).

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `YOUTUBE_OUTPUT_DIR` | `~/.config/alma/memory/ingested/youtube` | Artifact output directory |
| `SUBTITLE_LANG` | (auto-detect) | Preferred subtitle language |
| `DRY_RUN` | `false` | Print artifact to stdout instead of writing |
| `SEGMENT_MINUTES` | `5` | Fallback segment length when video has no chapters |
