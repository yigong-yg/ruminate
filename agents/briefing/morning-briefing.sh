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

# Only run main when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "morning-briefing: not yet fully implemented"
fi
