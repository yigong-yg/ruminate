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

# --- Chapter Detection ---
# Returns JSON array of {start_time, end_time, title}.
# Uses yt-dlp chapters if available, else generates time-based segments.
extract_chapters() {
    local json_file="$1"

    local has_chapters
    has_chapters=$(jq -r 'if .chapters then (.chapters | length) else 0 end' "$json_file")

    if [[ "$has_chapters" -gt 0 ]]; then
        jq '.chapters' "$json_file"
        return
    fi

    # Generate time-based segments
    local duration
    duration=$(jq -r '.duration // 0' "$json_file")
    local seg_seconds=$((SEGMENT_MINUTES * 60))

    # Build segments array with jq
    local segments="[]"
    local start=0
    while [[ $start -lt $duration ]]; do
        local end=$((start + seg_seconds))
        [[ $end -gt $duration ]] && end=$duration

        # Format HH:MM:SS for title
        local sh sm ss eh em es
        sh=$(printf '%02d' $((start / 3600)))
        sm=$(printf '%02d' $(((start % 3600) / 60)))
        ss=$(printf '%02d' $((start % 60)))
        eh=$(printf '%02d' $((end / 3600)))
        em=$(printf '%02d' $(((end % 3600) / 60)))
        es=$(printf '%02d' $((end % 60)))
        local title="${sh}:${sm}:${ss} - ${eh}:${em}:${es}"

        segments=$(echo "$segments" | jq \
            --argjson s "$start" --argjson e "$end" --arg t "$title" \
            '. + [{start_time: $s, end_time: $e, title: $t}]')

        start=$end
    done

    echo "$segments"
}

# --- Transcript Segmenting ---
# Reads VTT, assigns each caption line to a chapter by timestamp.
# Returns text with ---SEGMENT--- delimiters between chapters.
segment_transcript() {
    local vtt_file="$1"
    local chapters_json="$2"
    local chapter_count
    chapter_count=$(echo "$chapters_json" | jq 'length')

    # Parse VTT: extract (timestamp_seconds, text) pairs
    local timed_lines=""
    local current_time=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
            local h="${BASH_REMATCH[1]}" m="${BASH_REMATCH[2]}" s="${BASH_REMATCH[3]}"
            current_time=$(( 10#$h * 3600 + 10#$m * 60 + 10#$s ))
        elif [[ -n "$line" && "$line" != "WEBVTT"* && "$line" != "Kind:"* && "$line" != "Language:"* && "$line" != "NOTE"* && "$line" != *"-->"* ]]; then
            timed_lines="${timed_lines}${current_time}|${line}
"
        fi
    done < "$vtt_file"

    # Deduplicate by text content
    timed_lines=$(echo "$timed_lines" | awk -F'|' '!seen[$2]++')

    # Split into segments by chapter boundaries
    local i=0
    while [[ $i -lt $chapter_count ]]; do
        local ch_start ch_end
        ch_start=$(echo "$chapters_json" | jq -r ".[$i].start_time")
        ch_end=$(echo "$chapters_json" | jq -r ".[$i].end_time")

        [[ $i -gt 0 ]] && echo "---SEGMENT---"

        echo "$timed_lines" | while IFS='|' read -r ts text; do
            [[ -z "$ts" || -z "$text" ]] && continue
            if [[ "$ts" -ge "$ch_start" && "$ts" -lt "$ch_end" ]]; then
                echo "$text"
            fi
        done

        i=$((i + 1))
    done
}

# Only run main when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "youtube-ingest: not yet fully implemented"
fi
