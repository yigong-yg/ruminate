#!/bin/bash
# pipelines/youtube/youtube-ingest.sh — YouTube → canonical artifact
#
# Usage: ./youtube-ingest.sh <youtube-url> [--dry-run]
# Env:   YOUTUBE_OUTPUT_DIR  — output dir (default: ~/.config/alma/memory/ingested/youtube)
#        DRY_RUN             — "true" to print artifact instead of writing
#        SEGMENT_MINUTES     — fallback segment length (default: 5)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

YOUTUBE_OUTPUT_DIR="${YOUTUBE_OUTPUT_DIR:-$HOME/.config/alma/memory/ingested/youtube}"
DRY_RUN="${DRY_RUN:-false}"
SEGMENT_MINUTES="${SEGMENT_MINUTES:-5}"

log_warn() { echo "[WARN] $*" >&2; }

# --- Metadata Extraction ---
# Reads yt-dlp JSON, outputs shell variable assignments to eval.
extract_metadata() {
    local json_file="$1"
    local id title channel duration upload_raw upload_date description

    id=$(jq -r '.id // ""' "$json_file")
    title=$(jq -r '.title // ""' "$json_file")
    channel=$(jq -r '.channel // ""' "$json_file")
    duration=$(jq -r '.duration // 0' "$json_file")
    upload_raw=$(jq -r '.upload_date // ""' "$json_file")
    description=$(jq -r '.description // ""' "$json_file" | head -c 500)

    # Convert YYYYMMDD → YYYY-MM-DD
    if [[ ${#upload_raw} -eq 8 ]]; then
        upload_date="${upload_raw:0:4}-${upload_raw:4:2}-${upload_raw:6:2}"
    else
        upload_date="$upload_raw"
    fi

    printf 'VIDEO_ID=%q\n' "$id"
    printf 'TITLE=%q\n' "$title"
    printf 'CHANNEL=%q\n' "$channel"
    printf 'DURATION=%q\n' "$duration"
    printf 'UPLOAD_DATE=%q\n' "$upload_date"
    printf 'DESCRIPTION=%q\n' "$description"
}

# --- Transcript Cleaning ---
# Strips VTT headers, timestamps, and duplicate lines. Returns plain text with timestamps preserved as metadata.
clean_vtt() {
    local vtt_file="$1"
    # Remove VTT headers, timestamp lines (HH:MM:SS.mmm --> ...), blank lines, and NOTE blocks
    # Keep only the caption text lines, deduplicate
    sed '/^WEBVTT/d; /^Kind:/d; /^Language:/d; /^NOTE/d; /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/d; /^$/d' "$vtt_file" \
        | awk '!seen[$0]++' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# --- Transcript Source Detection ---
# Returns: "official", "auto", or "none"
detect_transcript_source() {
    local json_file="$1"

    local official_count
    official_count=$(jq -r '.subtitles | to_entries | map(select(.key | test("^en"))) | length' "$json_file" 2>/dev/null || echo "0")
    if [[ "$official_count" -gt 0 ]]; then
        echo "official"
        return
    fi

    local auto_count
    auto_count=$(jq -r '.automatic_captions | to_entries | map(select(.key | test("^en"))) | length' "$json_file" 2>/dev/null || echo "0")
    if [[ "$auto_count" -gt 0 ]]; then
        echo "auto"
        return
    fi

    echo "none"
}

# Only run main when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "youtube-ingest: not yet fully implemented"
fi
