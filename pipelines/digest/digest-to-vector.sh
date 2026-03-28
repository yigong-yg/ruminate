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
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

# --- Logging ---
log() {
    local msg="[$(date -Iseconds)] $*"
    [[ -d "$(dirname "$LOG_FILE")" ]] && echo "$msg" >> "$LOG_FILE" || true
}
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo "$*" >&2 || true; }

# --- Watermark ---
# Reads lastDate from watermark. Returns "" on missing/corrupt file.
read_watermark() {
    if [[ -f "$WATERMARK_FILE" ]]; then
        jq -r '.lastDate // ""' "$WATERMARK_FILE" 2>/dev/null || { log "WARN: corrupt watermark, treating as empty"; echo ""; }
    else
        echo ""
    fi
}

# Reads partial chunk progress for a specific file. Returns 0 if no partial state.
read_partial_sent() {
    local file="$1"
    if [[ -f "$WATERMARK_FILE" ]]; then
        local pfile
        pfile=$(jq -r '.partial.file // ""' "$WATERMARK_FILE" 2>/dev/null) || { echo "0"; return; }
        if [[ "$pfile" == "$file" ]]; then
            jq -r '.partial.sent // 0' "$WATERMARK_FILE" 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Atomic write: temp file + rename. Optionally includes partial state.
save_watermark() {
    local last_date="$1"
    local partial_file="${2:-}"
    local partial_sent="${3:-0}"
    local tmpfile="${WATERMARK_FILE}.tmp"

    if [[ -n "$partial_file" ]]; then
        jq -n --arg date "$last_date" --arg ts "$(date -Iseconds)" \
            --arg pfile "$partial_file" --argjson psent "$partial_sent" \
            '{lastProcessed: $ts, lastDate: $date, partial: {file: $pfile, sent: $psent}}' \
            > "$tmpfile"
    else
        jq -n --arg date "$last_date" --arg ts "$(date -Iseconds)" \
            '{lastProcessed: $ts, lastDate: $date}' > "$tmpfile"
    fi
    mv "$tmpfile" "$WATERMARK_FILE"
}

# Backward-compatible alias used by tests
write_watermark() { save_watermark "$1"; }

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
    model=$(alma_get "/api/settings" 2>/dev/null | jq -r '.memory.embeddingModel // "null"') || {
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

    # Write payload to temp file — avoids Windows/Git Bash UTF-8 corruption
    # when passing CJK content via curl -d "$string"
    local tmpfile
    tmpfile=$(mktemp)
    echo "$payload" > "$tmpfile"

    # Capture both body and HTTP status code; enforce timeout
    local raw_response http_code response_body
    raw_response=$(curl -s -w '\n%{http_code}' --max-time "$CURL_TIMEOUT" \
        -X POST "${ALMA_BASE_URL}/api/memories" \
        -H "Content-Type: application/json" \
        -d @"$tmpfile" 2>&1)
    local curl_exit=$?
    rm -f "$tmpfile"

    if [[ $curl_exit -ne 0 ]]; then
        log "WARN: POST failed for $date (curl exit $curl_exit)"
        return 1
    fi

    http_code=$(echo "$raw_response" | tail -1)
    response_body=$(echo "$raw_response" | sed '$d')

    # Check HTTP status
    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]] 2>/dev/null; then
        log "WARN: POST failed for $date: HTTP $http_code"
        return 1
    fi

    # Validate response is JSON with an id (Alma's success shape)
    local id
    id=$(echo "$response_body" | jq -r '.id // empty' 2>/dev/null)
    if [[ -z "$id" ]]; then
        log "WARN: POST for $date returned unexpected response (no .id in body)"
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

        # Check for partial resume state for this file
        local skip_count
        skip_count=$(read_partial_sent "$filename")

        # Skip fully-processed files (at or before watermark, no partial state)
        if [[ -n "$last_date" && ! "$filename" > "$last_date" && "$skip_count" -eq 0 ]]; then
            log_verbose "Skip $filename (watermark=$last_date)"
            continue
        fi

        log_verbose "Processing $filename..."
        [[ "$skip_count" -gt 0 ]] && log_verbose "  Resuming from chunk $skip_count"

        local chunk_index=0
        local file_chunks_sent=0
        local file_failed=false

        while IFS= read -r -d $'\x1e' chunk; do
            [[ -z "$chunk" ]] && continue

            # Skip chunks already sent in a previous partial run
            if [[ $chunk_index -lt $skip_count ]]; then
                log_verbose "  Skip chunk $chunk_index (already sent)"
                chunk_index=$((chunk_index + 1))
                continue
            fi

            if post_chunk "$filename" "$chunk"; then
                file_chunks_sent=$((file_chunks_sent + 1))
                chunks_sent=$((chunks_sent + 1))
            else
                chunks_failed=$((chunks_failed + 1))
                # Save partial progress: record how many chunks are done
                if [[ "$DRY_RUN" != "true" ]]; then
                    save_watermark "$last_date" "$filename" "$chunk_index"
                fi
                file_failed=true
                log "WARN: $filename chunk $chunk_index failed, stopping file"
                break
            fi
            chunk_index=$((chunk_index + 1))
        done < <(chunk_markdown "$file")

        local total_file_chunks=$((skip_count + file_chunks_sent))

        if [[ "$file_failed" == false && $total_file_chunks -gt 0 ]]; then
            files_processed=$((files_processed + 1))
            last_date="$filename"
            if [[ "$DRY_RUN" != "true" ]]; then
                save_watermark "$filename"
            fi
            log "Processed $filename ($total_file_chunks chunks)"
        elif [[ "$file_failed" == false && $total_file_chunks -eq 0 ]]; then
            log "WARN: $filename had no chunks, skipping"
        fi
        # file_failed == true: partial state already saved, move to next file
    done

    echo "$files_processed files, $chunks_sent chunks sent, $chunks_failed failed"
    log "Complete: $files_processed files, $chunks_sent chunks, $chunks_failed failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
