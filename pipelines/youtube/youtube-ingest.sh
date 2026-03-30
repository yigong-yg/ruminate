#!/bin/bash
# pipelines/youtube/youtube-ingest.sh — YouTube → canonical artifact
#
# Usage: ./youtube-ingest.sh <youtube-url> [--dry-run]
# Env:   YOUTUBE_OUTPUT_DIR  — output dir (default: ~/.config/alma/memory/ingested/youtube)
#        SUBTITLE_LANG       — preferred subtitle language (default: auto-detect best available)
#        DRY_RUN             — "true" to print artifact instead of writing
#        SEGMENT_MINUTES     — fallback segment length (default: 5)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

YOUTUBE_OUTPUT_DIR="${YOUTUBE_OUTPUT_DIR:-$HOME/.config/alma/memory/ingested/youtube}"
SUBTITLE_LANG="${SUBTITLE_LANG:-}"
DRY_RUN="${DRY_RUN:-false}"
SEGMENT_MINUTES="${SEGMENT_MINUTES:-5}"

log_warn() { echo "[WARN] $*" >&2; }

# YAML-safe scalar quoting: wraps in double quotes if value contains
# characters that are significant in YAML (: # " ' [ { ! | >).
yaml_quote() {
    local val="$1"
    if [[ "$val" == *":"* || "$val" == *"#"* || "$val" == *'"'* || "$val" == *"'"* || "$val" == *"["* || "$val" == *"{"* || "$val" == *"!"* || "$val" == *"|"* || "$val" == *">"* ]]; then
        val="${val//\\/\\\\}"
        val="${val//\"/\\\"}"
        printf '"%s"' "$val"
    else
        printf '%s' "$val"
    fi
}

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

# --- Transcript Source Detection ---
# Detects best available subtitle track.
# Returns: "source lang" (e.g. "official en" or "auto zh-Hans") or "none"
#
# Priority within each source (official first, then auto):
#   1. SUBTITLE_LANG explicit override
#   2. Video original language (.language from yt-dlp metadata)
#   3. en fallback
#   4. First available track
detect_transcript_source() {
    local json_file="$1"
    local preferred="$SUBTITLE_LANG"
    local original_lang
    original_lang=$(jq -r '.language // ""' "$json_file" 2>/dev/null || true)

    # Try to pick the best language from a list of available tracks.
    # Returns the chosen language or empty string if no match.
    _pick_lang() {
        local langs="$1"
        # 1. Explicit override
        if [[ -n "$preferred" ]] && echo "$langs" | grep -q "^${preferred}$"; then
            echo "$preferred"; return
        fi
        # 2. Video original language (exact match, then prefix match)
        if [[ -n "$original_lang" ]]; then
            if echo "$langs" | grep -q "^${original_lang}$"; then
                echo "$original_lang"; return
            fi
            # Prefix match for variants like "en-US" matching "en"
            local prefix_match
            prefix_match=$(echo "$langs" | grep "^${original_lang}" | head -1)
            if [[ -n "$prefix_match" ]]; then
                echo "$prefix_match"; return
            fi
        fi
        # 3. en fallback (exact, then prefix)
        if echo "$langs" | grep -q "^en$"; then
            echo "en"; return
        fi
        local en_prefix
        en_prefix=$(echo "$langs" | grep "^en" | head -1)
        if [[ -n "$en_prefix" ]]; then
            echo "$en_prefix"; return
        fi
        # 4. First available
        echo "$langs" | head -1
    }

    # Check official subtitles first
    local official_langs
    official_langs=$(jq -r '.subtitles // {} | keys_unsorted[]' "$json_file" 2>/dev/null || true)
    if [[ -n "$official_langs" ]]; then
        local chosen
        chosen=$(_pick_lang "$official_langs")
        if [[ -n "$chosen" ]]; then
            echo "official $chosen"
            return
        fi
    fi

    # Then auto-generated captions
    local auto_langs
    auto_langs=$(jq -r '.automatic_captions // {} | keys_unsorted[]' "$json_file" 2>/dev/null || true)
    if [[ -n "$auto_langs" ]]; then
        local chosen
        chosen=$(_pick_lang "$auto_langs")
        if [[ -n "$chosen" ]]; then
            echo "auto $chosen"
            return
        fi
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

    local segments="[]"
    local start=0
    while [[ $start -lt $duration ]]; do
        local end=$((start + seg_seconds))
        [[ $end -gt $duration ]] && end=$duration

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
# Uses consecutive-only dedup (not global) to preserve legitimate repeats
# like choruses and refrains while removing VTT scrolling duplicates.
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

    # Consecutive-only dedup: removes VTT scrolling duplicates (same text in
    # adjacent cues) but preserves legitimate non-consecutive repeats (choruses,
    # refrains, callbacks). Global dedup would violate the ~90% low-loss contract.
    timed_lines=$(echo "$timed_lines" | awk -F'|' 'prev != $2 {print} {prev = $2}')

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

# --- Canonical Artifact Builder ---
build_artifact() {
    local json_file="$1"
    local vtt_file="$2"
    local transcript_source="$3"
    local subtitle_language="${4:-unknown}"

    eval "$(extract_metadata "$json_file")"

    local chapters_json
    chapters_json=$(extract_chapters "$json_file")
    local chapter_count
    chapter_count=$(echo "$chapters_json" | jq 'length')

    local segmented
    segmented=$(segment_transcript "$vtt_file" "$chapters_json")

    local word_count
    word_count=$(echo "$segmented" | sed 's/---SEGMENT---//g' | wc -w | tr -d '[:space:]')

    # Build YAML frontmatter with yaml_quote for safe scalar escaping
    printf '%s\n' "---"
    printf 'schema_version: 1\n'
    printf 'artifact_type: youtube_canonical\n'
    printf 'video_id: %s\n' "$VIDEO_ID"
    printf 'title: %s\n' "$(yaml_quote "$TITLE")"
    printf 'channel: %s\n' "$(yaml_quote "$CHANNEL")"
    printf 'duration_seconds: %s\n' "$DURATION"
    printf 'upload_date: %s\n' "$UPLOAD_DATE"
    printf 'ingested_at: %s\n' "$(date -Iseconds)"
    printf 'transcript_source: %s\n' "$transcript_source"
    printf 'subtitle_language: %s\n' "$subtitle_language"
    printf 'chapters: %s\n' "$chapter_count"
    printf 'word_count: %s\n' "$word_count"
    printf '%s\n' "---"

    # Source description
    printf '\n## Source Description\n\n%s\n' "$DESCRIPTION"

    # Chapter sections
    local i=0
    local segments=()
    local current_seg=""
    while IFS= read -r line; do
        if [[ "$line" == "---SEGMENT---" ]]; then
            segments+=("$current_seg")
            current_seg=""
        else
            [[ -n "$current_seg" ]] && current_seg="${current_seg}
${line}" || current_seg="$line"
        fi
    done <<< "$segmented"
    [[ -n "$current_seg" ]] && segments+=("$current_seg")

    while [[ $i -lt $chapter_count ]]; do
        local ch_title
        ch_title=$(echo "$chapters_json" | jq -r ".[$i].title")
        printf '\n## %s\n\n%s\n' "$ch_title" "${segments[$i]:-}"
        i=$((i + 1))
    done
}

# Atomic artifact write (temp+rename pattern from M3)
write_youtube_artifact() {
    local content="$1"
    local output_path="$2"
    local output_dir
    output_dir=$(dirname "$output_path")

    mkdir -p "$output_dir" || { echo "ERROR: Cannot create $output_dir" >&2; return 1; }

    local tmpfile
    tmpfile=$(mktemp "${output_dir}/.yt-ingest-XXXXXX") || { echo "ERROR: Cannot create temp file" >&2; return 1; }

    printf '%s\n' "$content" > "$tmpfile" || { rm -f "$tmpfile"; echo "ERROR: Write failed" >&2; return 1; }
    mv "$tmpfile" "$output_path" || { rm -f "$tmpfile"; echo "ERROR: Rename failed" >&2; return 1; }
}

# --- Main ---
main() {
    local url=""
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            *) [[ -z "$url" ]] && url="$arg" ;;
        esac
    done

    if [[ -z "$url" ]]; then
        echo "Usage: youtube-ingest.sh <youtube-url> [--dry-run]" >&2
        exit 1
    fi

    # Preflight
    if ! command -v yt-dlp > /dev/null 2>&1; then
        echo "ERROR: yt-dlp not found on PATH. Install with: pip install yt-dlp" >&2
        exit 1
    fi

    # Create temp working directory
    local work_dir
    work_dir=$(mktemp -d)
    trap "rm -rf '$work_dir'" EXIT

    # Step 1: Extract metadata
    echo "Fetching metadata..." >&2
    local json_file="$work_dir/meta.json"
    yt-dlp --dump-json --no-warnings "$url" > "$json_file" 2>/dev/null || {
        echo "ERROR: yt-dlp failed to fetch metadata for $url" >&2
        exit 1
    }

    eval "$(extract_metadata "$json_file")"
    echo "Video: $TITLE ($VIDEO_ID, ${DURATION}s)" >&2

    # Step 2: Detect transcript source + language
    local source_info transcript_source sub_lang
    source_info=$(detect_transcript_source "$json_file")
    transcript_source=$(echo "$source_info" | awk '{print $1}')
    sub_lang=$(echo "$source_info" | awk '{print $2}')

    if [[ "$transcript_source" == "none" ]]; then
        echo "ERROR: No subtitles available for $VIDEO_ID." >&2
        echo "This video has no official or auto-generated captions." >&2
        echo "Whisper transcription is out of scope for MVP." >&2
        exit 1
    fi

    echo "Subtitle: $transcript_source ($sub_lang)" >&2

    # Step 3: Download subtitles for the detected language
    echo "Downloading $transcript_source subtitles ($sub_lang)..." >&2
    local sub_args=("--skip-download" "-P" "$work_dir" "--no-warnings" "-o" "%(id)s")
    if [[ "$transcript_source" == "official" ]]; then
        sub_args=("--write-subs" "--sub-langs" "$sub_lang" "${sub_args[@]}")
    else
        sub_args=("--write-auto-subs" "--sub-langs" "$sub_lang" "${sub_args[@]}")
    fi

    local ytdlp_log="$work_dir/ytdlp-subs.log"
    if ! yt-dlp "${sub_args[@]}" "$url" > "$ytdlp_log" 2>&1; then
        echo "ERROR: yt-dlp failed to download subtitles for $VIDEO_ID" >&2
        echo "yt-dlp output:" >&2
        cat "$ytdlp_log" >&2
        exit 1
    fi

    # Find the VTT file deterministically: look for {video-id}.{lang}.vtt
    local vtt_file="$work_dir/${VIDEO_ID}.${sub_lang}.vtt"
    if [[ ! -f "$vtt_file" ]]; then
        # Fallback: try any VTT with the video ID
        vtt_file=$(find "$work_dir" -name "${VIDEO_ID}*.vtt" -type f | head -1)
    fi
    if [[ -z "$vtt_file" || ! -f "$vtt_file" ]]; then
        echo "ERROR: No VTT file found for $VIDEO_ID after download" >&2
        echo "Expected: $work_dir/${VIDEO_ID}.${sub_lang}.vtt" >&2
        echo "Available files:" >&2
        ls -la "$work_dir"/*.vtt 2>/dev/null >&2 || echo "  (none)" >&2
        exit 1
    fi

    # Step 4: Build canonical artifact
    echo "Building canonical artifact..." >&2
    local artifact
    artifact=$(build_artifact "$json_file" "$vtt_file" "$transcript_source" "$sub_lang")

    # Step 5: Output
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "--- DRY-RUN: canonical artifact for $VIDEO_ID ---"
        echo ""
        echo "$artifact"
        return 0
    fi

    local output_path="${YOUTUBE_OUTPUT_DIR}/${VIDEO_ID}.md"
    write_youtube_artifact "$artifact" "$output_path" || exit 1
    echo "Artifact written to $output_path" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
