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

# Only run main when executed directly (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "digest-to-vector: not yet fully implemented"
fi
