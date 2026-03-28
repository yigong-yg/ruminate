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
        printf '%s\x1e' "$chunk"
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
    local filename

    for file in "$DIGEST_DIR"/*.md; do
        [[ -f "$file" ]] || continue

        filename=$(basename "$file" .md)

        # Skip files at or before watermark (lexicographic YYYY-MM-DD compare)
        if [[ -n "$last_date" && ! "$filename" > "$last_date" ]]; then
            log_verbose "Skip $filename (watermark=$last_date)"
            continue
        fi

        log_verbose "Processing $filename..."

        local file_failed=0
        while IFS= read -r -d $'\x1e' chunk; do
            [[ -z "$chunk" ]] && continue
            if post_chunk "$filename" "$chunk"; then
                chunks_sent=$((chunks_sent + 1))
            else
                file_failed=$((file_failed + 1))
            fi
        done < <(chunk_markdown "$file")

        chunks_failed=$((chunks_failed + file_failed))
        files_processed=$((files_processed + 1))

        if [[ "$file_failed" -eq 0 ]]; then
            log "Processed $filename"
            if [[ "$DRY_RUN" != "true" ]]; then
                write_watermark "$filename"
            fi
        else
            log "WARN: $filename had $file_failed failed chunks, watermark not advanced"
        fi
    done

    echo "$files_processed files, $chunks_sent chunks sent, $chunks_failed failed"
    log "Complete: $files_processed files, $chunks_sent chunks, $chunks_failed failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
