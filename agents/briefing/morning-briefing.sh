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

# Load .env if OPENAI_API_KEY not already set
if [[ -z "${OPENAI_API_KEY:-}" && -f "${REPO_ROOT}/.env" ]]; then
    source "${REPO_ROOT}/.env"
fi

DIGEST_DIR="${DIGEST_DIR:-$HOME/.config/alma/memory/digest}"
BRIEFING_MODEL="${BRIEFING_MODEL:-gpt-4o-mini}"
BRIEFING_DAYS="${BRIEFING_DAYS:-3}"
DRY_RUN="${DRY_RUN:-false}"
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
PROMPT_TEMPLATE="${SCRIPT_DIR}/prompt.md"

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
    echo "{\"query\": \"$query\"}" > "$tmpfile"

    local response
    response=$(curl -s --max-time "$CURL_TIMEOUT" \
        -X POST "${ALMA_BASE_URL}/api/memories/search" \
        -H "Content-Type: application/json" \
        -d @"$tmpfile" 2>/dev/null) || { rm -f "$tmpfile"; echo ""; return; }
    rm -f "$tmpfile"

    # Extract top results, format as bullet points
    local results
    results=$(echo "$response" | jq -r '.results[:5][] | "- " + (.content // "" | split("\n") | .[0])' 2>/dev/null) || { echo ""; return; }
    echo "$results"
}

# Run all memory queries and combine results.
gather_memory() {
    local all_results=""
    local queries=("未完成事项和待办" "重要决策和变更" "跨领域联系和模式")

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

# Build the full prompt by substituting context into the template.
assemble_prompt() {
    local digest_content="$1"
    local memory_results="$2"
    local n_days="$BRIEFING_DAYS"

    if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
        echo "ERROR: Prompt template not found at $PROMPT_TEMPLATE" >&2
        return 1
    fi

    local template
    template=$(cat "$PROMPT_TEMPLATE")

    # Substitute placeholders
    template="${template//\{n_days\}/$n_days}"
    template="${template//\{digest_content\}/$digest_content}"

    if [[ -n "$memory_results" ]]; then
        template="${template//\{memory_results\}/$memory_results}"
    else
        template="${template//\{memory_results\}/(No semantic memory results available — synthesize from digests only)}"
    fi

    echo "$template"
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
        --argjson temperature 0.7 \
        '{
            model: $model,
            messages: [
                {role: "system", content: $prompt}
            ],
            max_tokens: $max_tokens,
            temperature: $temperature
        }'
}

# Extract the briefing text from OpenAI's response. Returns empty on error.
parse_response() {
    local response="$1"
    echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo ""
}

# Call OpenAI API. Returns the briefing text or empty string on failure.
call_openai() {
    local prompt="$1"

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "ERROR: OPENAI_API_KEY not set. Source .env or export it." >&2
        return 1
    fi

    local payload
    payload=$(build_openai_payload "$prompt")

    local tmpfile
    tmpfile=$(mktemp)
    echo "$payload" > "$tmpfile"

    local raw_response http_code response_body
    raw_response=$(curl -s -w '\n%{http_code}' --max-time "$CURL_TIMEOUT" \
        -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @"$tmpfile" 2>&1)
    local curl_exit=$?
    rm -f "$tmpfile"

    if [[ $curl_exit -ne 0 ]]; then
        echo "ERROR: OpenAI API call failed (curl exit $curl_exit)" >&2
        return 1
    fi

    http_code=$(echo "$raw_response" | tail -1)
    response_body=$(echo "$raw_response" | sed '$d')

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]] 2>/dev/null; then
        local err_msg
        err_msg=$(echo "$response_body" | jq -r '.error.message // empty' 2>/dev/null)
        echo "ERROR: OpenAI API returned HTTP $http_code: ${err_msg:-unknown error}" >&2
        return 1
    fi

    parse_response "$response_body"
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
        memory_results=$(gather_memory 2>/dev/null) || true
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
