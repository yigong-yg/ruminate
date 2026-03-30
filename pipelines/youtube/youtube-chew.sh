#!/bin/bash
# pipelines/youtube/youtube-chew.sh — Canonical artifact → chew-short derived view
#
# Usage: ./youtube-chew.sh <canonical-artifact-path> [--dry-run] [--model MODEL]
# Env:   CHEW_OUTPUT_DIR  — output dir (default: sibling chew/ dir of input)
#        CHEW_MODEL        — OpenAI model (default: gpt-4o-mini)
#        OPENAI_API_KEY    — required (reads from .env via grep)
#        DRY_RUN           — "true" to print prompt, skip synthesis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load OPENAI_API_KEY from .env via grep — never source .env
if [[ -z "${OPENAI_API_KEY:-}" && -f "${REPO_ROOT}/.env" ]]; then
    OPENAI_API_KEY=$(grep -E '^OPENAI_API_KEY=' "${REPO_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
    OPENAI_API_KEY="${OPENAI_API_KEY%\"}"
    OPENAI_API_KEY="${OPENAI_API_KEY#\"}"
    export OPENAI_API_KEY
fi

CHEW_OUTPUT_DIR="${CHEW_OUTPUT_DIR:-}"
CHEW_MODEL="${CHEW_MODEL:-gpt-4o}"
DRY_RUN="${DRY_RUN:-false}"
CURL_TIMEOUT="${CURL_TIMEOUT:-120}"
MAX_INPUT_CHARS="${MAX_INPUT_CHARS:-30000}"

# --- Helpers ---

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

# --- Frontmatter Parsing ---
# Reads YAML frontmatter from a canonical artifact. Outputs eval-safe assignments.
parse_canonical_frontmatter() {
    local artifact="$1"

    # Extract frontmatter block (between first and second ---)
    local fm
    fm=$(sed -n '/^---$/,/^---$/p' "$artifact" | sed '1d;$d')

    local video_id title channel subtitle_language transcript_source

    video_id=$(echo "$fm" | grep '^video_id:' | head -1 | sed 's/^video_id:[[:space:]]*//')
    title=$(echo "$fm" | grep '^title:' | head -1 | sed 's/^title:[[:space:]]*//')
    channel=$(echo "$fm" | grep '^channel:' | head -1 | sed 's/^channel:[[:space:]]*//')
    subtitle_language=$(echo "$fm" | grep '^subtitle_language:' | head -1 | sed 's/^subtitle_language:[[:space:]]*//')
    transcript_source=$(echo "$fm" | grep '^transcript_source:' | head -1 | sed 's/^transcript_source:[[:space:]]*//')

    # Strip surrounding quotes if present
    video_id="${video_id%\"}"; video_id="${video_id#\"}"
    title="${title%\"}"; title="${title#\"}"
    channel="${channel%\"}"; channel="${channel#\"}"
    subtitle_language="${subtitle_language%\"}"; subtitle_language="${subtitle_language#\"}"
    transcript_source="${transcript_source%\"}"; transcript_source="${transcript_source#\"}"

    printf 'VIDEO_ID=%q\n' "$video_id"
    printf 'TITLE=%q\n' "$title"
    printf 'CHANNEL=%q\n' "$channel"
    printf 'SUBTITLE_LANGUAGE=%q\n' "$subtitle_language"
    printf 'TRANSCRIPT_SOURCE=%q\n' "$transcript_source"
}

# --- Body Extraction ---
# Returns everything after the closing --- of frontmatter.
extract_body() {
    local artifact="$1"
    # Skip lines until the second ---
    awk 'BEGIN{n=0} /^---$/{n++; if(n==2){found=1; next}} found{print}' "$artifact"
}

# --- Prompt Assembly ---
build_chew_prompt() {
    local body="$1"
    local title="$2"
    local channel="$3"

    local system_prompt='You are extracting the skeletal structure of a narrative, not compressing it into opinions.

Core directives:
- Preserve the story arc: who did what, when, why, and what changed as a result
- Preserve named entities exactly (people, orgs, places, papers, projects)
- Preserve specific numbers, years, and concrete details
- If the source language is Chinese, include short original-language fragments (5-20 chars) as grounding anchors in the Narrative Arc section. These prove you actually read that part of the transcript
- NEVER invent quotes. Do not output anything in quotation marks. There is no quotes section
- NEVER output generic statements like "X emphasizes the importance of Y" or "X reflects on his journey." If you cannot say something specific, say nothing
- Prioritize coherence (can someone reconstruct the story arc?) over coverage (did every chapter get mentioned?)
- It is acceptable to skip chapters that are low-density filler (greetings, tangents, repeated content). Not every chapter deserves space
- The target audience already has access to the full canonical artifact. Your job is to give them reasons to read it and a map for navigating it, not to replace it
- Match the source language. Density over length. 1000 sharp words > 2000 vague ones

Output structure (1000-2000 words total):

## Core Throughline
What this content is actually about and why it matters. 2-4 paragraphs.
Not "X discusses Y" — instead, the actual thesis and its stakes.

## Narrative Arc
5-8 key turning points that define the story of this content.
Each point MUST include at least one concrete anchor: a specific person, organization, year, decision, event, or scene.
If the source language is Chinese, each point MUST include at least one short original-language fragment (5-20 characters) from the transcript to prove grounding.
These are not opinions — they are plot points.

## Precision Anchors
10-20 specific information nodes that should not be lost.
Categories: people, organizations, years, papers/projects, key judgments, specific story beats.
Format as a flat list. Each item is one line, max two sentences.
No paraphrasing into generic statements. If you cannot be specific, omit.

## Tensions & Contrarian Claims
The genuinely provocative or non-obvious positions expressed in this content.
Do not smooth them out. Do not hedge. Preserve the sharp edges.
3-5 items, each 1-2 sentences.'

    printf '%s\n\n---\n\nVideo: %s\nChannel: %s\n\n%s' \
        "$system_prompt" "$title" "$channel" "$body"
}

# --- OpenAI Payload ---
build_chew_payload() {
    local prompt="$1"
    local model="${2:-$CHEW_MODEL}"

    # Use stdin for prompt to avoid jq --arg CJK crash on Windows
    printf '%s' "$prompt" | jq -Rs --arg model "$model" \
        '{
            model: $model,
            messages: [
                {role: "system", content: .}
            ],
            max_tokens: 6000,
            temperature: 0.3
        }'
}

# --- OpenAI Call (Node.js — curl/Schannel broken for large POST on Windows) ---
call_openai() {
    local prompt="$1"

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "ERROR: OPENAI_API_KEY not set. Set it in .env or export it." >&2
        return 1
    fi

    local payload
    payload=$(build_chew_payload "$prompt")

    local payloadfile
    payloadfile=$(mktemp --suffix=.json)
    printf '%s' "$payload" > "$payloadfile"
    local winpath
    winpath=$(cygpath -w "$payloadfile" 2>/dev/null || echo "$payloadfile")

    local result
    result=$(BRIEFING_API_KEY="$OPENAI_API_KEY" node -e "
const fs = require('fs');
const https = require('https');
const payload = fs.readFileSync(String.raw\`${winpath}\`, 'utf8');
const apiKey = process.env.BRIEFING_API_KEY;
if (!apiKey) { console.error('No API key in env'); process.exit(1); }
const req = https.request({
    hostname: 'api.openai.com',
    path: '/v1/chat/completions',
    method: 'POST',
    headers: {
        'Authorization': 'Bearer ' + apiKey,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
    },
    timeout: ${CURL_TIMEOUT}000
}, (res) => {
    let data = '';
    res.on('data', (c) => data += c);
    res.on('end', () => {
        try {
            const j = JSON.parse(data);
            if (j.choices) process.stdout.write(j.choices[0].message.content);
            else { console.error('API error:', j.error?.message || 'unknown'); process.exit(1); }
        } catch(e) { console.error('Parse error:', e.message); process.exit(1); }
    });
});
req.on('error', (e) => { console.error('Request error:', e.message); process.exit(1); });
req.on('timeout', () => { req.destroy(); console.error('Timeout'); process.exit(1); });
req.write(payload);
req.end();
" 2>&1)
    local node_exit=$?
    rm -f "$payloadfile"

    if [[ $node_exit -ne 0 ]]; then
        echo "ERROR: OpenAI API call failed: $result" >&2
        return 1
    fi

    echo "$result"
}

# --- Chew Frontmatter ---
build_chew_frontmatter() {
    local video_id="$1" title="$2" channel="$3"
    local subtitle_language="$4" transcript_source="$5"
    local source_artifact="$6" model="$7" word_count="$8"

    printf '%s\n' "---"
    printf 'schema_version: 1\n'
    printf 'artifact_type: youtube_chew_short\n'
    printf 'source_artifact: %s\n' "$source_artifact"
    printf 'video_id: %s\n' "$video_id"
    printf 'title: %s\n' "$(yaml_quote "$title")"
    printf 'channel: %s\n' "$(yaml_quote "$channel")"
    printf 'generated_at: %s\n' "$(date -Iseconds)"
    printf 'model: %s\n' "$model"
    printf 'word_count: %s\n' "$word_count"
    printf 'subtitle_language: %s\n' "$subtitle_language"
    printf 'transcript_source: %s\n' "$transcript_source"
    printf '%s\n' "---"
}

# --- Atomic Artifact Write ---
write_chew_artifact() {
    local content="$1"
    local output_path="$2"
    local output_dir
    output_dir=$(dirname "$output_path")

    mkdir -p "$output_dir" || { echo "ERROR: Cannot create $output_dir" >&2; return 1; }

    local tmpfile
    tmpfile=$(mktemp "${output_dir}/.yt-chew-XXXXXX") || { echo "ERROR: Cannot create temp file" >&2; return 1; }

    printf '%s\n' "$content" > "$tmpfile" || { rm -f "$tmpfile"; echo "ERROR: Write failed" >&2; return 1; }
    mv "$tmpfile" "$output_path" || { rm -f "$tmpfile"; echo "ERROR: Rename failed" >&2; return 1; }
}

# --- Main ---
main() {
    local input_file=""
    local shift_next=""
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --model) shift_next=model ;;
            *)
                if [[ "$shift_next" == "model" ]]; then
                    CHEW_MODEL="$arg"; shift_next=""
                elif [[ -z "$input_file" ]]; then
                    input_file="$arg"
                fi
                ;;
        esac
    done

    if [[ -z "$input_file" ]]; then
        echo "Usage: youtube-chew.sh <canonical-artifact-path> [--dry-run] [--model MODEL]" >&2
        exit 1
    fi

    if [[ ! -f "$input_file" ]]; then
        echo "ERROR: Input file not found: $input_file" >&2
        exit 1
    fi

    # Parse frontmatter
    eval "$(parse_canonical_frontmatter "$input_file")"
    if [[ -z "$VIDEO_ID" ]]; then
        echo "ERROR: Could not parse video_id from frontmatter in $input_file" >&2
        exit 1
    fi

    echo "Chew: $TITLE ($VIDEO_ID)" >&2

    # Extract body
    local body
    body=$(extract_body "$input_file")
    if [[ -z "$body" ]]; then
        echo "ERROR: No body content found in $input_file" >&2
        exit 1
    fi

    # Truncate if body exceeds MAX_INPUT_CHARS (avoids TPM/context limits)
    local body_len=${#body}
    if [[ $body_len -gt $MAX_INPUT_CHARS ]]; then
        echo "Input body is ${body_len} chars, truncating to ${MAX_INPUT_CHARS} chars" >&2
        body="${body:0:$MAX_INPUT_CHARS}

[... transcript truncated at ${MAX_INPUT_CHARS} chars for token budget. Distill from what is available.]"
    fi

    # Build prompt
    local prompt
    prompt=$(build_chew_prompt "$body" "$TITLE" "$CHANNEL")

    # Dry-run
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "--- DRY-RUN: chew-short prompt (model=$CHEW_MODEL, video=$VIDEO_ID) ---"
        echo ""
        echo "$prompt"
        return 0
    fi

    # Synthesize
    echo "Synthesizing chew-short (model=$CHEW_MODEL)..." >&2
    local chew_content
    chew_content=$(call_openai "$prompt") || {
        echo "ERROR: Synthesis failed" >&2
        exit 1
    }

    if [[ -z "$chew_content" ]]; then
        echo "ERROR: Empty response from OpenAI" >&2
        exit 1
    fi

    # Build frontmatter
    local word_count
    word_count=$(echo "$chew_content" | wc -w | tr -d '[:space:]')
    local source_basename
    source_basename=$(basename "$input_file")

    local frontmatter
    frontmatter=$(build_chew_frontmatter "$VIDEO_ID" "$TITLE" "$CHANNEL" \
        "$SUBTITLE_LANGUAGE" "$TRANSCRIPT_SOURCE" "$source_basename" "$CHEW_MODEL" "$word_count")

    local full_artifact="${frontmatter}
${chew_content}"

    # Determine output path
    local output_dir
    if [[ -n "$CHEW_OUTPUT_DIR" ]]; then
        output_dir="$CHEW_OUTPUT_DIR"
    else
        output_dir="$(dirname "$input_file")/chew"
    fi
    local output_path="${output_dir}/${VIDEO_ID}-short.md"

    write_chew_artifact "$full_artifact" "$output_path" || exit 1
    echo "Chew-short written to $output_path" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
