# M1 Glue Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bash script that reads digest `.md` files, splits them into semantic chunks by `## ` headings, and POSTs each chunk to Alma's memory API for vector embedding.

**Architecture:** Standalone bash script `pipelines/digest/digest-to-vector.sh` that sources `orchestrator/api-client.sh` for REST wrappers. Reads from `~/.config/alma/memory/digest/*.md`, POSTs to `POST /api/memories` (Alma handles embedding server-side via configured `text-embedding-3-small`), tracks progress in `.vector-watermark` (JSON). Error philosophy: skip + log, never block.

**Tech Stack:** Bash, curl, jq, Alma REST API (`localhost:23001`)

---

## Gating Prerequisite

**BLOCKER**: OpenAI provider must be enabled in Alma settings before this script can run in production. `POST /api/memories` returns 400 without a configured embedding model.

The script includes a preflight check that detects this and exits with a clear error message. The script does NOT configure the provider — that requires Karla's manual action.

To enable (via API — documented in `orchestrator/adapters/alma-memory-api-internals.md` §4.3):
```bash
curl -s -X PUT http://localhost:23001/api/providers/openai \
  -H "Content-Type: application/json" -d '{"enabled": true}'
current=$(curl -s http://localhost:23001/api/settings)
updated=$(echo "$current" | jq '.memory.embeddingModel = "openai:text-embedding-3-small"')
curl -s -X PUT http://localhost:23001/api/settings \
  -H "Content-Type: application/json" -d "$updated"
```

---

## File Structure

```
pipelines/digest/
└── digest-to-vector.sh        # Main glue layer script (CREATE)

tests/
└── test-digest-to-vector.sh   # Tests (CREATE)
```

No modifications to existing files. `orchestrator/api-client.sh` is sourced at runtime but not modified — JSON payload construction uses `jq` directly in the new script.

---

## Key Design Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| JSON construction | `jq -n --arg` per chunk | Handles escaping of quotes, newlines, CJK in digest content |
| Chunking | Pure bash loop (no awk) | Simpler to test, no subprocess for small files |
| Chunk separator | ASCII Record Separator (`\x1e`) | Allows chunks with embedded newlines to pass through pipes |
| Content format | `"{date}: {chunk text}"` | Date prefix in content enables temporal semantic search; date also in metadata for filtering |
| Watermark format | JSON `{lastProcessed, lastDate}` | Mirrors existing `.watermark` pattern in same directory |
| Watermark comparison | Lexicographic `YYYY-MM-DD` | Dates sort correctly as strings; skip files where filename <= lastDate |
| Error on POST | `continue` (skip chunk) | Skip + log per spec §0, never block the pipeline |
| Dry-run | `--dry-run` flag + `DRY_RUN` env var | Testable without Alma running |
| Source guard | `[[ BASH_SOURCE[0] == $0 ]]` | Script can be sourced for testing without running main() |

---

## Reference: Existing Digest File Format

From `~/.config/alma/memory/digest/2026-03-23.md`:
```markdown
# 2026-03-23 群聊摘要

## 主要话题
- [服务器初建]: Fireflow Discord 服务器正式启用

## 关键事件与决策
- Fireflow服务器创建，仅两人

## 人物动态
- @karlamo: 创建了Fireflow服务器

## 氛围
- 新手村开荒气氛
```

Each `## ` section becomes one chunk. The `# ` title line is skipped (date is in the filename).

## Reference: Alma POST /api/memories

From `orchestrator/adapters/alma-memory-api-internals.md` §3.1:
```bash
curl -s -X POST http://localhost:23001/api/memories \
  -H "Content-Type: application/json" \
  -d '{"content": "...", "metadata": {"source": "digest", "date": "2026-03-23"}}'
```
- `content`: string, required — Alma calls embedding model server-side
- `metadata`: optional JSON — stored in `metadata` column
- Returns 400 if no embedding provider configured
- Returns 503 if memory service not ready

## Reference: Existing .watermark Format

```json
{"lastProcessed": "2026-03-27T21:03:00Z", "lastDate": "2026-03-26"}
```

The `.vector-watermark` follows the same schema.

---

### Task 1: Test harness + sample data fixtures

**Files:**
- Create: `tests/test-digest-to-vector.sh`

- [ ] **Step 1: Create test script with harness and fixtures**

```bash
#!/bin/bash
# tests/test-digest-to-vector.sh — Tests for digest-to-vector glue layer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/pipelines/digest/digest-to-vector.sh"

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: '$expected'"; echo "    actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: '$needle')"; FAIL=$((FAIL + 1))
    fi
}

# --- Fixtures ---
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

create_fixtures() {
    cat > "$TEST_DIR/2026-03-23.md" << 'FIXTURE'
# 2026-03-23 群聊摘要

## 主要话题
- [服务器初建]: Fireflow Discord 服务器正式启用

## 关键事件与决策
- Fireflow服务器创建，仅两人

## 氛围
- 新手村开荒气氛
FIXTURE

    cat > "$TEST_DIR/2026-03-24.md" << 'FIXTURE'
# 2026-03-24 群聊摘要

## 主要话题
- [Agent Voice上线]: 语音播报系统搭建完成
- [频道架构]: 创建了#agent-internal频道

## 关键事件与决策
- Agent Voice成功上线
- 语音播报系统完整闭环

## 人物动态
- @karlamo: 展现强执行力

## 氛围
- 高产出日
FIXTURE
}

create_fixtures

# --- Tests go here (added in subsequent tasks) ---

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```

- [ ] **Step 2: Verify test harness runs**

Run: `bash tests/test-digest-to-vector.sh`

Expected output:
```
=== Results: 0 passed, 0 failed, 0 total ===
```
Exit code: 0

- [ ] **Step 3: Commit**

```bash
git add tests/test-digest-to-vector.sh
git commit -m "test: add test harness and fixtures for digest-to-vector"
```

---

### Task 2: Implement chunk_markdown function (TDD)

**Files:**
- Create: `pipelines/digest/digest-to-vector.sh`
- Modify: `tests/test-digest-to-vector.sh`

- [ ] **Step 1: Add chunking tests**

Insert after `create_fixtures` in `tests/test-digest-to-vector.sh`:

```bash
echo "=== Chunking ==="

# Source script (loads functions, does not run main)
export DIGEST_DIR="$TEST_DIR"
source "$SCRIPT"

# Test: 3-section file produces 3 chunks
chunks=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-23.md")
assert_eq "3-section file produces 3 chunks" "3" "${#chunks[@]}"

# Test: first chunk starts with ## heading
assert_contains "chunk 1 starts with heading" "## 主要话题" "${chunks[0]}"

# Test: first chunk contains body text
assert_contains "chunk 1 contains body" "服务器初建" "${chunks[0]}"

# Test: top-level title is not in any chunk
all_chunks="${chunks[*]}"
TOTAL=$((TOTAL + 1))
if [[ "$all_chunks" != *"# 2026-03-23 群聊摘要"* ]]; then
    echo "  PASS: top-level title excluded from chunks"
    PASS=$((PASS + 1))
else
    echo "  FAIL: top-level title found in chunks"
    FAIL=$((FAIL + 1))
fi

# Test: 4-section file produces 4 chunks
chunks2=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks2+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-24.md")
assert_eq "4-section file produces 4 chunks" "4" "${#chunks2[@]}"

# Test: last chunk of 4-section file
assert_contains "last chunk is atmosphere" "高产出日" "${chunks2[3]}"
```

- [ ] **Step 2: Run tests — should fail (script doesn't exist)**

Run: `bash tests/test-digest-to-vector.sh`

Expected: Error sourcing script — file not found

- [ ] **Step 3: Create digest-to-vector.sh with chunk_markdown**

```bash
#!/bin/bash
# pipelines/digest/digest-to-vector.sh — Glue layer: digest .md → Alma vector memory
#
# Usage: ./digest-to-vector.sh [--dry-run] [--verbose]
# Env:   DIGEST_DIR     — override digest directory (default: ~/.config/alma/memory/digest)
#        DRY_RUN        — "true" to skip POST calls
#        ALMA_BASE_URL  — override Alma URL (default: http://localhost:23001)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "${REPO_ROOT}/orchestrator/api-client.sh"

DIGEST_DIR="${DIGEST_DIR:-$HOME/.config/alma/memory/digest}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# --- Chunking ---
# Splits a markdown file by ## headings.
# Outputs chunks separated by ASCII Record Separator (0x1e).
# Skips top-level # title lines.
chunk_markdown() {
    local file="$1"
    local chunk=""
    local first=true

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^##\  ]]; then
            if [[ -n "$chunk" ]]; then
                [[ "$first" == true ]] && first=false || printf '\x1e'
                printf '%s' "$chunk"
            fi
            chunk="$line"
        elif [[ "$line" =~ ^#\  ]]; then
            continue
        elif [[ -n "$chunk" ]]; then
            chunk="${chunk}
${line}"
        fi
    done < "$file"

    if [[ -n "$chunk" ]]; then
        [[ "$first" == true ]] || printf '\x1e'
        printf '%s' "$chunk"
    fi
}

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "digest-to-vector: not yet fully implemented"
fi
```

- [ ] **Step 4: Run tests — chunking tests should pass**

Run: `bash tests/test-digest-to-vector.sh`

Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pipelines/digest/digest-to-vector.sh tests/test-digest-to-vector.sh
git commit -m "feat: add chunk_markdown function for digest-to-vector"
```

---

### Task 3: Implement watermark functions (TDD)

**Files:**
- Modify: `pipelines/digest/digest-to-vector.sh`
- Modify: `tests/test-digest-to-vector.sh`

- [ ] **Step 1: Add watermark tests**

Insert after the chunking tests in the test script:

```bash
echo "=== Watermark ==="

# Test: read returns empty when no watermark file
WATERMARK_FILE="$TEST_DIR/.vector-watermark"
rm -f "$WATERMARK_FILE"
result=$(read_watermark)
assert_eq "no watermark file → empty string" "" "$result"

# Test: write then read roundtrip
write_watermark "2026-03-23"
result=$(read_watermark)
assert_eq "write/read roundtrip" "2026-03-23" "$result"

# Test: watermark file is valid JSON
TOTAL=$((TOTAL + 1))
if jq -e . "$WATERMARK_FILE" > /dev/null 2>&1; then
    echo "  PASS: watermark is valid JSON"; PASS=$((PASS + 1))
else
    echo "  FAIL: watermark is not valid JSON"; FAIL=$((FAIL + 1))
fi

# Test: watermark has ISO timestamp in lastProcessed
ts=$(jq -r '.lastProcessed' "$WATERMARK_FILE")
assert_contains "lastProcessed has ISO timestamp" "202" "$ts"

# Test: overwrite updates lastDate
write_watermark "2026-03-25"
result=$(read_watermark)
assert_eq "overwrite updates lastDate" "2026-03-25" "$result"

# Cleanup
rm -f "$WATERMARK_FILE"
```

- [ ] **Step 2: Run tests — watermark tests should fail**

Run: `bash tests/test-digest-to-vector.sh`

Expected: Chunking PASS, watermark FAIL (functions not defined)

- [ ] **Step 3: Add watermark + logging functions to digest-to-vector.sh**

Insert after the `VERBOSE` variable definition, before `# --- Chunking ---`:

```bash
WATERMARK_FILE="${WATERMARK_FILE:-${DIGEST_DIR}/.vector-watermark}"
LOG_FILE="${DIGEST_DIR}/.vector-log"

# --- Logging ---
log() {
    local msg="[$(date -Iseconds)] $*"
    [[ -d "$(dirname "$LOG_FILE")" ]] && echo "$msg" >> "$LOG_FILE" || true
}
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo "$*" >&2 || true; }

# --- Watermark ---
read_watermark() {
    if [[ -f "$WATERMARK_FILE" ]]; then
        jq -r '.lastDate // ""' "$WATERMARK_FILE"
    else
        echo ""
    fi
}

write_watermark() {
    local date="$1"
    jq -n --arg date "$date" --arg ts "$(date -Iseconds)" \
        '{lastProcessed: $ts, lastDate: $date}' > "$WATERMARK_FILE"
}
```

- [ ] **Step 4: Run tests — all should pass**

Run: `bash tests/test-digest-to-vector.sh`

Expected: All 11 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pipelines/digest/digest-to-vector.sh tests/test-digest-to-vector.sh
git commit -m "feat: add watermark read/write for digest-to-vector"
```

---

### Task 4: Implement preflight + main loop + dry-run (TDD)

**Files:**
- Modify: `pipelines/digest/digest-to-vector.sh`
- Modify: `tests/test-digest-to-vector.sh`

- [ ] **Step 1: Add dry-run end-to-end tests**

Insert after watermark tests:

```bash
echo "=== Dry-Run End-to-End ==="

# Test: processes all files when no watermark exists
output=$(DIGEST_DIR="$TEST_DIR" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1)
assert_contains "processes 2 files" "2 files" "$output"
assert_contains "sends 7 chunks" "7 chunks sent" "$output"
assert_contains "zero failures" "0 failed" "$output"

# Test: watermark NOT written in dry-run
TOTAL=$((TOTAL + 1))
if [[ ! -f "$TEST_DIR/.vector-watermark" ]]; then
    echo "  PASS: dry-run does not write watermark"; PASS=$((PASS + 1))
else
    echo "  FAIL: dry-run wrote watermark"; FAIL=$((FAIL + 1))
fi

# Test: watermark causes older files to be skipped
echo '{"lastProcessed":"2026-03-27T00:00:00Z","lastDate":"2026-03-23"}' > "$TEST_DIR/.vector-watermark"
output=$(DIGEST_DIR="$TEST_DIR" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1)
assert_contains "skips file at watermark, processes 1" "1 files" "$output"
assert_contains "only newer file chunks" "4 chunks sent" "$output"

# Cleanup
rm -f "$TEST_DIR/.vector-watermark"
```

- [ ] **Step 2: Run tests — dry-run tests should fail**

Run: `bash tests/test-digest-to-vector.sh`

Expected: Chunking + watermark PASS, dry-run FAIL (main not implemented)

- [ ] **Step 3: Implement preflight, post_chunk, and main**

Replace the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then` block at the end of `digest-to-vector.sh` with:

```bash
# --- Preflight ---
preflight_check() {
    local model
    model=$(alma_get "/api/memories/embedding-model" 2>/dev/null | jq -r '.model // "null"') || {
        echo "ERROR: Cannot reach Alma at $ALMA_BASE_URL" >&2
        return 1
    }

    if [[ "$model" == "null" ]]; then
        echo "ERROR: No embedding model configured. POST /api/memories will 400." >&2
        echo "Enable OpenAI provider — see orchestrator/adapters/alma-memory-api-internals.md §4.3" >&2
        return 1
    fi

    log_verbose "Preflight OK: embedding model=$model"
}

# --- Post one chunk to Alma ---
post_chunk() {
    local date="$1"
    local chunk="$2"

    local payload
    payload=$(jq -n \
        --arg content "${date}: ${chunk}" \
        --arg source "digest" \
        --arg date "$date" \
        '{content: $content, metadata: {source: $source, date: $date}}')

    if [[ "$DRY_RUN" == "true" ]]; then
        log_verbose "  [DRY-RUN] chunk: ${chunk:0:80}..."
        return 0
    fi

    local response
    response=$(alma_post "/api/memories" "$payload" 2>&1) || {
        log "WARN: POST connection failed for $date"
        return 1
    }

    local error
    error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
    if [[ -n "$error" ]]; then
        log "WARN: POST rejected for $date: $error"
        return 1
    fi
}

# --- Main ---
main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --verbose) VERBOSE=true ;;
        esac
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        preflight_check || exit 1
    fi

    local last_date
    last_date=$(read_watermark)
    log_verbose "Watermark: ${last_date:-(none)}"

    local files_processed=0 chunks_sent=0 chunks_failed=0

    for file in "$DIGEST_DIR"/*.md; do
        [[ -f "$file" ]] || continue

        local filename
        filename=$(basename "$file" .md)

        # Skip files at or before watermark (lexicographic YYYY-MM-DD compare)
        if [[ -n "$last_date" && ! "$filename" > "$last_date" ]]; then
            log_verbose "Skip $filename (watermark=$last_date)"
            continue
        fi

        log_verbose "Processing $filename..."

        while IFS= read -r -d $'\x1e' chunk; do
            [[ -z "$chunk" ]] && continue
            if post_chunk "$filename" "$chunk"; then
                chunks_sent=$((chunks_sent + 1))
            else
                chunks_failed=$((chunks_failed + 1))
            fi
        done < <(chunk_markdown "$file")

        files_processed=$((files_processed + 1))
        log "Processed $filename"

        if [[ "$DRY_RUN" != "true" ]]; then
            write_watermark "$filename"
        fi
    done

    echo "$files_processed files, $chunks_sent chunks sent, $chunks_failed failed"
    log "Complete: $files_processed files, $chunks_sent chunks, $chunks_failed failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 4: Run tests — all should pass**

Run: `bash tests/test-digest-to-vector.sh`

Expected: All 17 tests PASS
```
=== Chunking ===
  PASS: 3-section file produces 3 chunks
  PASS: chunk 1 starts with heading
  PASS: chunk 1 contains body
  PASS: top-level title excluded from chunks
  PASS: 4-section file produces 4 chunks
  PASS: last chunk is atmosphere
=== Watermark ===
  PASS: no watermark file → empty string
  PASS: write/read roundtrip
  PASS: watermark is valid JSON
  PASS: lastProcessed has ISO timestamp
  PASS: overwrite updates lastDate
=== Dry-Run End-to-End ===
  PASS: processes 2 files
  PASS: sends 7 chunks
  PASS: zero failures
  PASS: dry-run does not write watermark
  PASS: skips file at watermark, processes 1
  PASS: only newer file chunks

=== Results: 17 passed, 0 failed, 17 total ===
```

- [ ] **Step 5: Commit**

```bash
git add pipelines/digest/digest-to-vector.sh tests/test-digest-to-vector.sh
git commit -m "feat(M1): complete digest-to-vector glue layer with preflight and dry-run"
```

---

### Task 5: Integration smoke test (requires Alma + embedding provider)

**This task can only run after Karla enables the OpenAI embedding provider. Skip if not yet configured.**

**Files:** None (manual verification only)

- [ ] **Step 1: Verify Alma is running and provider configured**

```bash
source orchestrator/api-client.sh
alma_memory_embedding_model
```

Expected: `{"model":"openai:text-embedding-3-small"}`

If `{"model":null}` — **STOP**. Karla must enable the provider first.

- [ ] **Step 2: Run against one real digest file**

```bash
# Set watermark to skip all but 2026-03-26
echo '{"lastProcessed":"2026-03-28T00:00:00Z","lastDate":"2026-03-25"}' \
  > ~/.config/alma/memory/digest/.vector-watermark

bash pipelines/digest/digest-to-vector.sh --verbose
```

Expected output: `1 files, N chunks sent, 0 failed`

- [ ] **Step 3: Verify memories exist in Alma**

```bash
source orchestrator/api-client.sh
alma_memory_stats | jq
alma_memory_search "群聊" | jq '.[0:2]'
```

Expected: `total > 0`, search returns results with source "digest"

- [ ] **Step 4: Verify watermark updated**

```bash
cat ~/.config/alma/memory/digest/.vector-watermark | jq
```

Expected: `lastDate` is `"2026-03-26"`

- [ ] **Step 5: Full backfill (all digest files)**

```bash
rm ~/.config/alma/memory/digest/.vector-watermark
bash pipelines/digest/digest-to-vector.sh --verbose
```

Expected: `4 files, ~17 chunks sent, 0 failed`

- [ ] **Step 6: Verify search works end-to-end**

```bash
source orchestrator/api-client.sh
alma_memory_search "Chrome语言设置" | jq '.[0].content'
alma_memory_search "投递" | jq '.[0].content'
```

Expected: Returns relevant digest chunks with date prefixes

- [ ] **Step 7: Commit watermark state note**

No code changes. If everything passes, M1 glue layer is complete.

---

## Complete File Listings

### pipelines/digest/digest-to-vector.sh (final)

```bash
#!/bin/bash
# pipelines/digest/digest-to-vector.sh — Glue layer: digest .md → Alma vector memory
#
# Usage: ./digest-to-vector.sh [--dry-run] [--verbose]
# Env:   DIGEST_DIR     — override digest directory (default: ~/.config/alma/memory/digest)
#        DRY_RUN        — "true" to skip POST calls
#        ALMA_BASE_URL  — override Alma URL (default: http://localhost:23001)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "${REPO_ROOT}/orchestrator/api-client.sh"

DIGEST_DIR="${DIGEST_DIR:-$HOME/.config/alma/memory/digest}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
WATERMARK_FILE="${WATERMARK_FILE:-${DIGEST_DIR}/.vector-watermark}"
LOG_FILE="${DIGEST_DIR}/.vector-log"

# --- Logging ---
log() {
    local msg="[$(date -Iseconds)] $*"
    [[ -d "$(dirname "$LOG_FILE")" ]] && echo "$msg" >> "$LOG_FILE" || true
}
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo "$*" >&2 || true; }

# --- Watermark ---
read_watermark() {
    if [[ -f "$WATERMARK_FILE" ]]; then
        jq -r '.lastDate // ""' "$WATERMARK_FILE"
    else
        echo ""
    fi
}

write_watermark() {
    local date="$1"
    jq -n --arg date "$date" --arg ts "$(date -Iseconds)" \
        '{lastProcessed: $ts, lastDate: $date}' > "$WATERMARK_FILE"
}

# --- Chunking ---
# Splits a markdown file by ## headings.
# Outputs chunks separated by ASCII Record Separator (0x1e).
# Skips top-level # title lines.
chunk_markdown() {
    local file="$1"
    local chunk=""
    local first=true

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^##\  ]]; then
            if [[ -n "$chunk" ]]; then
                [[ "$first" == true ]] && first=false || printf '\x1e'
                printf '%s' "$chunk"
            fi
            chunk="$line"
        elif [[ "$line" =~ ^#\  ]]; then
            continue
        elif [[ -n "$chunk" ]]; then
            chunk="${chunk}
${line}"
        fi
    done < "$file"

    if [[ -n "$chunk" ]]; then
        [[ "$first" == true ]] || printf '\x1e'
        printf '%s' "$chunk"
    fi
}

# --- Preflight ---
preflight_check() {
    local model
    model=$(alma_get "/api/memories/embedding-model" 2>/dev/null | jq -r '.model // "null"') || {
        echo "ERROR: Cannot reach Alma at $ALMA_BASE_URL" >&2
        return 1
    }

    if [[ "$model" == "null" ]]; then
        echo "ERROR: No embedding model configured. POST /api/memories will 400." >&2
        echo "Enable OpenAI provider — see orchestrator/adapters/alma-memory-api-internals.md §4.3" >&2
        return 1
    fi

    log_verbose "Preflight OK: embedding model=$model"
}

# --- Post one chunk to Alma ---
post_chunk() {
    local date="$1"
    local chunk="$2"

    local payload
    payload=$(jq -n \
        --arg content "${date}: ${chunk}" \
        --arg source "digest" \
        --arg date "$date" \
        '{content: $content, metadata: {source: $source, date: $date}}')

    if [[ "$DRY_RUN" == "true" ]]; then
        log_verbose "  [DRY-RUN] chunk: ${chunk:0:80}..."
        return 0
    fi

    local response
    response=$(alma_post "/api/memories" "$payload" 2>&1) || {
        log "WARN: POST connection failed for $date"
        return 1
    }

    local error
    error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
    if [[ -n "$error" ]]; then
        log "WARN: POST rejected for $date: $error"
        return 1
    fi
}

# --- Main ---
main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --verbose) VERBOSE=true ;;
        esac
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        preflight_check || exit 1
    fi

    local last_date
    last_date=$(read_watermark)
    log_verbose "Watermark: ${last_date:-(none)}"

    local files_processed=0 chunks_sent=0 chunks_failed=0

    for file in "$DIGEST_DIR"/*.md; do
        [[ -f "$file" ]] || continue

        local filename
        filename=$(basename "$file" .md)

        # Skip files at or before watermark (lexicographic YYYY-MM-DD compare)
        if [[ -n "$last_date" && ! "$filename" > "$last_date" ]]; then
            log_verbose "Skip $filename (watermark=$last_date)"
            continue
        fi

        log_verbose "Processing $filename..."

        while IFS= read -r -d $'\x1e' chunk; do
            [[ -z "$chunk" ]] && continue
            if post_chunk "$filename" "$chunk"; then
                chunks_sent=$((chunks_sent + 1))
            else
                chunks_failed=$((chunks_failed + 1))
            fi
        done < <(chunk_markdown "$file")

        files_processed=$((files_processed + 1))
        log "Processed $filename"

        if [[ "$DRY_RUN" != "true" ]]; then
            write_watermark "$filename"
        fi
    done

    echo "$files_processed files, $chunks_sent chunks sent, $chunks_failed failed"
    log "Complete: $files_processed files, $chunks_sent chunks, $chunks_failed failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### tests/test-digest-to-vector.sh (final)

```bash
#!/bin/bash
# tests/test-digest-to-vector.sh — Tests for digest-to-vector glue layer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/pipelines/digest/digest-to-vector.sh"

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: '$expected'"; echo "    actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: '$needle')"; FAIL=$((FAIL + 1))
    fi
}

# --- Fixtures ---
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

create_fixtures() {
    cat > "$TEST_DIR/2026-03-23.md" << 'FIXTURE'
# 2026-03-23 群聊摘要

## 主要话题
- [服务器初建]: Fireflow Discord 服务器正式启用

## 关键事件与决策
- Fireflow服务器创建，仅两人

## 氛围
- 新手村开荒气氛
FIXTURE

    cat > "$TEST_DIR/2026-03-24.md" << 'FIXTURE'
# 2026-03-24 群聊摘要

## 主要话题
- [Agent Voice上线]: 语音播报系统搭建完成
- [频道架构]: 创建了#agent-internal频道

## 关键事件与决策
- Agent Voice成功上线
- 语音播报系统完整闭环

## 人物动态
- @karlamo: 展现强执行力

## 氛围
- 高产出日
FIXTURE
}

create_fixtures

# === Chunking ===
echo "=== Chunking ==="

export DIGEST_DIR="$TEST_DIR"
source "$SCRIPT"

# Test: 3-section file produces 3 chunks
chunks=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-23.md")
assert_eq "3-section file produces 3 chunks" "3" "${#chunks[@]}"

# Test: first chunk starts with ## heading
assert_contains "chunk 1 starts with heading" "## 主要话题" "${chunks[0]}"

# Test: first chunk contains body text
assert_contains "chunk 1 contains body" "服务器初建" "${chunks[0]}"

# Test: top-level title not in any chunk
all_chunks="${chunks[*]}"
TOTAL=$((TOTAL + 1))
if [[ "$all_chunks" != *"# 2026-03-23 群聊摘要"* ]]; then
    echo "  PASS: top-level title excluded from chunks"
    PASS=$((PASS + 1))
else
    echo "  FAIL: top-level title found in chunks"
    FAIL=$((FAIL + 1))
fi

# Test: 4-section file produces 4 chunks
chunks2=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks2+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-24.md")
assert_eq "4-section file produces 4 chunks" "4" "${#chunks2[@]}"

# Test: last chunk is atmosphere section
assert_contains "last chunk is atmosphere" "高产出日" "${chunks2[3]}"

# === Watermark ===
echo "=== Watermark ==="

WATERMARK_FILE="$TEST_DIR/.vector-watermark"
rm -f "$WATERMARK_FILE"
result=$(read_watermark)
assert_eq "no watermark file → empty string" "" "$result"

write_watermark "2026-03-23"
result=$(read_watermark)
assert_eq "write/read roundtrip" "2026-03-23" "$result"

TOTAL=$((TOTAL + 1))
if jq -e . "$WATERMARK_FILE" > /dev/null 2>&1; then
    echo "  PASS: watermark is valid JSON"; PASS=$((PASS + 1))
else
    echo "  FAIL: watermark is not valid JSON"; FAIL=$((FAIL + 1))
fi

ts=$(jq -r '.lastProcessed' "$WATERMARK_FILE")
assert_contains "lastProcessed has ISO timestamp" "202" "$ts"

write_watermark "2026-03-25"
result=$(read_watermark)
assert_eq "overwrite updates lastDate" "2026-03-25" "$result"

rm -f "$WATERMARK_FILE"

# === Dry-Run End-to-End ===
echo "=== Dry-Run End-to-End ==="

output=$(DIGEST_DIR="$TEST_DIR" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1)
assert_contains "processes 2 files" "2 files" "$output"
assert_contains "sends 7 chunks" "7 chunks sent" "$output"
assert_contains "zero failures" "0 failed" "$output"

TOTAL=$((TOTAL + 1))
if [[ ! -f "$TEST_DIR/.vector-watermark" ]]; then
    echo "  PASS: dry-run does not write watermark"; PASS=$((PASS + 1))
else
    echo "  FAIL: dry-run wrote watermark"; FAIL=$((FAIL + 1))
fi

echo '{"lastProcessed":"2026-03-27T00:00:00Z","lastDate":"2026-03-23"}' > "$TEST_DIR/.vector-watermark"
output=$(DIGEST_DIR="$TEST_DIR" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1)
assert_contains "skips file at watermark, processes 1" "1 files" "$output"
assert_contains "only newer file chunks" "4 chunks sent" "$output"

rm -f "$TEST_DIR/.vector-watermark"

# === Summary ===
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```
