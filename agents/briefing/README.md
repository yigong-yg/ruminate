# Morning Briefing

Synthesizes recent digest files and vector memory into a daily insight briefing.

## Inputs

| Source | Path | Required |
|--------|------|----------|
| Digest files | `$DIGEST_DIR/*.md` (default: `~/.config/alma/memory/digest/`) | Yes (at least 1) |
| Vector memory | Alma `POST /api/memories/search` at `$ALMA_BASE_URL` | No (degrades gracefully) |
| OpenAI API | `$OPENAI_API_KEY` (from env or `.env` file) | Yes for non-dry-run |
| Prompt template | `agents/briefing/prompt.md` | Yes |

## Output

| Mode | Behavior |
|------|----------|
| `--dry-run` | Assembled prompt printed to stdout |
| Normal | Dated artifact written to `$BRIEFING_OUTPUT_DIR/YYYY-MM-DD.md` (default: `~/.config/alma/memory/briefings/`). Nothing on stdout. Artifact path printed to stderr. |

## Dependencies

- `bash`, `jq`, `curl`, `node` (for OpenAI HTTP call — curl/Schannel bug workaround)
- `cygpath` (Windows only, for Node.js file path conversion)

## State Ownership

This job owns:
- Output directory: `~/.config/alma/memory/briefings/`
- No watermark or progress file. Each run is independent.

This job reads but does not own:
- `~/.config/alma/memory/digest/*.md` (owned by M0/Alma)
- Alma vector memory (owned by M1 glue layer)

## Idempotency

Same-day reruns **overwrite** the existing artifact. The briefing for a given date is always the latest synthesis.

Not implemented (and not planned for MVP):
- `--force` / `--no-clobber` flags
- `latest.md` symlink
- Append/versioning of same-day runs

## Failure Behavior

| Failure | Result |
|---------|--------|
| No digest files | Exit 1, no artifact written |
| Alma unreachable | Warning logged, briefing generated from digests only |
| OpenAI API error | Exit 1, no artifact written (no partial file) |
| Disk full / write error | Exit 1, no partial file (atomic write via temp+rename) |

## Provenance

Each artifact starts with a provenance header:

```
<!-- briefing-meta
generated_at: 2026-03-29T08:00:00+00:00
model: gpt-4o-mini
days: 3
digests: 2026-03-27.md, 2026-03-26.md, 2026-03-25.md
memory: available
-->
```

This format is not guaranteed stable across versions.

## Usage

```bash
# Preview prompt without API call
bash agents/briefing/morning-briefing.sh --dry-run --days 3

# Generate today's briefing
bash agents/briefing/morning-briefing.sh --days 3

# Custom model
bash agents/briefing/morning-briefing.sh --days 3 --model gpt-4o

# Custom output directory
BRIEFING_OUTPUT_DIR=/tmp/briefings bash agents/briefing/morning-briefing.sh
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DIGEST_DIR` | `~/.config/alma/memory/digest` | Digest file source |
| `BRIEFING_OUTPUT_DIR` | `~/.config/alma/memory/briefings` | Artifact output directory |
| `BRIEFING_MODEL` | `gpt-4o-mini` | OpenAI model for synthesis |
| `BRIEFING_DAYS` | `3` | Number of recent digests to include |
| `OPENAI_API_KEY` | (from `.env`) | Required for synthesis |
| `ALMA_BASE_URL` | `http://localhost:23001` | Alma API for vector search |
| `DRY_RUN` | `false` | Skip synthesis, print prompt |
