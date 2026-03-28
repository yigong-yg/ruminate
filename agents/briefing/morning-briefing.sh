#!/bin/bash
# agents/briefing/morning-briefing.sh — Morning briefing: digest + memory → insight
#
# Usage: ./morning-briefing.sh [--dry-run] [--days N] [--model MODEL]
# Env:   DIGEST_DIR      — digest files (default: ~/.config/alma/memory/digest)
#        OPENAI_API_KEY   — required for synthesis (reads from .env if not set)
#        BRIEFING_MODEL   — OpenAI model (default: gpt-4o-mini)
#        ALMA_BASE_URL    — Alma API (default: http://localhost:23001)
#        DRY_RUN          — "true" to output prompt without calling OpenAI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "${REPO_ROOT}/orchestrator/api-client.sh"

# Load OPENAI_API_KEY from .env via grep — never source .env as shell code.
# grep || true prevents set -e crash when key is absent from .env.
if [[ -z "${OPENAI_API_KEY:-}" && -f "${REPO_ROOT}/.env" ]]; then
    OPENAI_API_KEY=$(grep -E '^OPENAI_API_KEY=' "${REPO_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
    OPENAI_API_KEY="${OPENAI_API_KEY%\"}" # strip trailing quote
    OPENAI_API_KEY="${OPENAI_API_KEY#\"}" # strip leading quote
    export OPENAI_API_KEY
fi

DIGEST_DIR="${DIGEST_DIR:-$HOME/.config/alma/memory/digest}"
BRIEFING_MODEL="${BRIEFING_MODEL:-gpt-4o-mini}"
BRIEFING_DAYS="${BRIEFING_DAYS:-3}"
DRY_RUN="${DRY_RUN:-false}"
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
MEMORY_TIMEOUT="${MEMORY_TIMEOUT:-10}"
PROMPT_TEMPLATE="${SCRIPT_DIR}/prompt.md"

# --- Logging ---
log_warn() { echo "[WARN] $*" >&2; }

# --- Context Gathering ---

# Read the latest N digest .md files, newest first. Returns their content concatenated.
gather_digests() {
    local n="${1:-3}"
    local files=()

    for f in "$DIGEST_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        files+=("$f")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    # Sort descending by filename (YYYY-MM-DD sorts lexicographically)
    local sorted
    sorted=$(printf '%s\n' "${files[@]}" | sort -r | head -n "$n")

    local content=""
    while IFS= read -r f; do
        [[ -n "$content" ]] && content="${content}

---

"
        content="${content}$(cat "$f")"
    done <<< "$sorted"

    echo "$content"
}

# Query Alma vector memory. Returns formatted results or empty string on failure.
query_memory() {
    local query="$1"
    local tmpfile
    tmpfile=$(mktemp)
    # Build JSON safely with jq
    jq -n --arg q "$query" '{query: $q}' > "$tmpfile"

    local response
    response=$(curl -s --max-time "$MEMORY_TIMEOUT" \
        -X POST "${ALMA_BASE_URL}/api/memories/search" \
        -H "Content-Type: application/json" \
        -d @"$tmpfile" 2>/dev/null) || {
        rm -f "$tmpfile"
        log_warn "memory query failed (network): $query"
        echo ""
        return
    }
    rm -f "$tmpfile"

    # Extract top results, format as bullet points
    local results
    results=$(echo "$response" | jq -r '.results[:5][] | "- " + (.content // "" | split("\n") | .[0])' 2>/dev/null) || {
        log_warn "memory query failed (parse): $query"
        echo ""
        return
    }
    echo "$results"
}

# Run all memory queries and combine results.
gather_memory() {
    # Quick connectivity check before running all queries
    if ! curl -s --max-time 2 "${ALMA_BASE_URL}/api/memories/status" > /dev/null 2>&1; then
        log_warn "Alma not reachable at $ALMA_BASE_URL, skipping memory queries"
        echo ""
        return
    fi

    local all_results=""
    local queries=("未完成事项和待办" "重要决策和变更" "风险和阻塞和异常")

    for q in "${queries[@]}"; do
        local result
        result=$(query_memory "$q")
        if [[ -n "$result" ]]; then
            all_results="${all_results}
Query: ${q}
${result}
"
        fi
    done

    echo "$all_results"
}

# --- Prompt Assembly ---

# Build the full prompt by concatenating template instructions with dynamic content.
# Uses concatenation (not substitution) to avoid bash replacement bugs with &, \, $.
assemble_prompt() {
    local digest_content="$1"
    local memory_results="$2"
    local n_days="$BRIEFING_DAYS"

    if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
        echo "ERROR: Prompt template not found at $PROMPT_TEMPLATE" >&2
        return 1
    fi

    local instructions
    instructions=$(cat "$PROMPT_TEMPLATE")

    local memory_section
    if [[ -n "$memory_results" ]]; then
        memory_section="$memory_results"
    else
        memory_section="(No semantic memory results available — synthesize from digests only)"
    fi

    # Concatenate — no placeholder substitution
    printf '%s\n\n### Recent Activity (last %s days)\n\n%s\n\n### Semantic Memory Matches\n\n%s\n' \
        "$instructions" "$n_days" "$digest_content" "$memory_section"
}

# --- Synthesis ---

# Build the OpenAI API request payload. Returns JSON string.
build_openai_payload() {
    local prompt="$1"
    local model="${2:-$BRIEFING_MODEL}"

    jq -n \
        --arg model "$model" \
        --arg prompt "$prompt" \
        --argjson max_tokens 1000 \
        --argjson temperature 0.4 \
        '{
            model: $model,
            messages: [
                {role: "system", content: $prompt}
            ],
            max_tokens: $max_tokens,
            temperature: $temperature
        }'
}

# Call OpenAI API. Returns the briefing text or empty string on failure.
# Uses Node.js instead of curl — curl 8.8.0/Schannel on Windows fails on
# POST bodies >~2KB (exit 43, HTTP 000). Node.js handles this correctly.
# API key is passed via environment variable, never interpolated into source.
call_openai() {
    local prompt="$1"

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "ERROR: OPENAI_API_KEY not set. Set it in .env or export it." >&2
        return 1
    fi

    local payload
    payload=$(build_openai_payload "$prompt")

    local payloadfile
    payloadfile=$(mktemp --suffix=.json)
    echo "$payload" > "$payloadfile"
    local winpath
    winpath=$(cygpath -w "$payloadfile")

    # Pass API key via env var (BRIEFING_API_KEY), not interpolated into source
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

# --- Main ---
main() {
    local shift_next=""
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --days) shift_next=days ;;
            --model) shift_next=model ;;
            *)
                if [[ "${shift_next}" == "days" ]]; then
                    BRIEFING_DAYS="$arg"; shift_next=""
                elif [[ "${shift_next}" == "model" ]]; then
                    BRIEFING_MODEL="$arg"; shift_next=""
                fi
                ;;
        esac
    done

    # 1. Gather context
    local digests
    digests=$(gather_digests "$BRIEFING_DAYS")
    if [[ -z "$digests" ]]; then
        echo "ERROR: No digest files found in $DIGEST_DIR" >&2
        exit 1
    fi

    local memory_results=""
    if [[ "$DRY_RUN" != "true" ]]; then
        memory_results=$(gather_memory) || true
    fi

    # 2. Assemble prompt
    local prompt
    prompt=$(assemble_prompt "$digests" "$memory_results")

    # 3. Synthesize or dry-run
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "--- DRY-RUN: assembled prompt (model=$BRIEFING_MODEL, days=$BRIEFING_DAYS) ---"
        echo ""
        echo "$prompt"
        return 0
    fi

    local briefing
    briefing=$(call_openai "$prompt") || {
        echo "ERROR: Synthesis failed" >&2
        exit 1
    }

    if [[ -z "$briefing" ]]; then
        echo "ERROR: Empty response from OpenAI" >&2
        exit 1
    fi

    echo "$briefing"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
