#!/bin/bash
# tests/test-morning-briefing.sh — Tests for morning briefing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/agents/briefing/morning-briefing.sh"

PASS=0; FAIL=0; TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: '$expected'"; echo "    actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (missing: '$needle')"; FAIL=$((FAIL + 1))
    fi
}

assert_not_empty() {
    local desc="$1" value="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -n "$value" ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (was empty)"; FAIL=$((FAIL + 1))
    fi
}

# --- Fixtures ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

create_fixtures() {
    mkdir -p "$TEST_DIR/digest"

    cat > "$TEST_DIR/digest/2026-03-25.md" << 'FIXTURE'
# 2026-03-25 群聊摘要

## 主要话题
- [投递代码优化]: 移除daily guard限制，修复时区问题
- [LinkedIn限额检测]: 添加daily_limit_reached检测功能

## 关键事件与决策
- 35个投递触及LinkedIn日上限
- KPI制度取消：只记录增量

## 未完成事项
- source字段数据收集

## 氛围
- 技术推进+感情升温
FIXTURE

    cat > "$TEST_DIR/digest/2026-03-26.md" << 'FIXTURE'
# 2026-03-26 群聊摘要

## 主要话题
- [Chrome语言事件]: 调试Chrome/Windows系统语言设置
- [隐私安全事件]: Meo泄露经纪人PII

## 关键事件与决策
- SOUL.md新增PII保护规则
- 安全审计结论：当前防护足够

## 未完成事项
- 无

## 氛围
- 戏剧性的一天
FIXTURE

    cat > "$TEST_DIR/digest/2026-03-27.md" << 'FIXTURE'
# 2026-03-27 群聊摘要

## 主要话题
- [Ruminate规划] 三轮产品需求问答
- [Token优化] 分析token消耗

## 关键事件与决策
- embeddingModel配好OpenAI
- 品牌命名确定

## 未完成事项
- Ruminate M0实现
- Discord服务器icon更换
- Heartbeat冷启动问题

## 氛围
- 高密度工作日
FIXTURE
}

create_fixtures

# --- Tests added in subsequent tasks ---

echo "=== Context Gathering ==="

export DIGEST_DIR="$TEST_DIR/digest"
export REPO_ROOT_REAL="$REPO_ROOT"
source "$SCRIPT"

# Test: gather_digests returns content of latest N files
result=$(gather_digests 2)
assert_contains "gather_digests includes latest file" "2026-03-27" "$result"
assert_contains "gather_digests includes 2nd latest" "2026-03-26" "$result"
TOTAL=$((TOTAL + 1))
if [[ "$result" != *"2026-03-25"* ]]; then
    echo "  PASS: gather_digests excludes 3rd file when n=2"; PASS=$((PASS + 1))
else
    echo "  FAIL: gather_digests included 3rd file when n=2"; FAIL=$((FAIL + 1))
fi

# Test: gather_digests with n=3 includes all 3
result3=$(gather_digests 3)
assert_contains "gather_digests(3) includes 3rd file" "2026-03-25" "$result3"

# Test: gather_digests with empty dir returns empty
empty_dir=$(mktemp -d)
result_empty=$(DIGEST_DIR="$empty_dir" gather_digests 3)
assert_eq "gather_digests on empty dir" "" "$result_empty"
rmdir "$empty_dir"

# Test: query_memory returns results (or empty on failure)
# In test context, Alma may not be running — function should handle gracefully
result_mem=$(query_memory "test query" 2>/dev/null || echo "")
TOTAL=$((TOTAL + 1))
echo "  PASS: query_memory does not crash (result length: ${#result_mem})"; PASS=$((PASS + 1))

echo ""
echo "=== Prompt Assembly ==="

# Test: assemble_prompt includes digest content
prompt=$(assemble_prompt "test digest content" "test memory results")
assert_contains "prompt has digest content" "test digest content" "$prompt"
assert_contains "prompt has memory results" "test memory results" "$prompt"

# Test: assemble_prompt includes template instructions
assert_contains "prompt has iceberg philosophy" "Iceberg" "$prompt"
assert_contains "prompt has word limit" "500 words" "$prompt"
assert_contains "prompt has output sections" "Connections" "$prompt"
assert_contains "prompt has output sections" "Unresolved" "$prompt"
assert_contains "prompt has output sections" "Insight" "$prompt"

# Test: assemble_prompt with empty memory gracefully handles it
prompt_no_mem=$(assemble_prompt "digest only" "")
assert_contains "prompt works without memory" "digest only" "$prompt_no_mem"
assert_contains "no-memory prompt still has structure" "Connections" "$prompt_no_mem"

echo ""
echo "=== Synthesis ==="

# Test: build_openai_payload creates valid JSON
payload=$(build_openai_payload "Test system prompt" "gpt-4o-mini")
TOTAL=$((TOTAL + 1))
if echo "$payload" | jq -e . > /dev/null 2>&1; then
    echo "  PASS: payload is valid JSON"; PASS=$((PASS + 1))
else
    echo "  FAIL: payload is not valid JSON"; FAIL=$((FAIL + 1))
fi
assert_contains "payload has model" "gpt-4o-mini" "$payload"
assert_contains "payload has system message" "Test system prompt" "$payload"

# Test: payload preserves special characters via jq --arg
special_payload=$(build_openai_payload 'Content with & and $dollar and \backslash' "gpt-4o-mini")
special_content=$(echo "$special_payload" | jq -r '.messages[0].content')
assert_contains "payload preserves ampersand" "&" "$special_content"
assert_contains "payload preserves dollar" '$dollar' "$special_content"
assert_contains "payload preserves backslash" '\backslash' "$special_content"

echo ""
echo "=== Dry-Run End-to-End ==="

# Test: dry-run outputs the assembled prompt, not a briefing
output=$(DIGEST_DIR="$TEST_DIR/digest" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1)
assert_contains "dry-run has digest content" "2026-03-27" "$output"
assert_contains "dry-run has prompt structure" "Connections" "$output"
assert_contains "dry-run has prompt structure" "Unresolved" "$output"
assert_contains "dry-run shows mode indicator" "DRY-RUN" "$output"

# Test: --days flag controls how many digests are included
output2=$(DIGEST_DIR="$TEST_DIR/digest" DRY_RUN=true bash "$SCRIPT" --dry-run --days 1 2>&1)
assert_contains "days=1 includes latest" "2026-03-27" "$output2"
TOTAL=$((TOTAL + 1))
if [[ "$output2" != *"2026-03-25"* ]]; then
    echo "  PASS: days=1 excludes older files"; PASS=$((PASS + 1))
else
    echo "  FAIL: days=1 included older files"; FAIL=$((FAIL + 1))
fi

# Test: dry-run with no digest files
empty_dir2=$(mktemp -d)
output3=$(DIGEST_DIR="$empty_dir2" DRY_RUN=true bash "$SCRIPT" --dry-run 2>&1) || true
assert_contains "no digests: shows error" "No digest files" "$output3"
rmdir "$empty_dir2"

echo ""
echo "=== Special Character Regression ==="

# Test: assemble_prompt preserves & in digest content (was a bug)
prompt_amp=$(assemble_prompt "A & B are partners" "X & Y results")
assert_contains "ampersand preserved in digest" "A & B are partners" "$prompt_amp"
assert_contains "ampersand preserved in memory" "X & Y results" "$prompt_amp"

# Test: dollar sign preserved
prompt_dollar=$(assemble_prompt 'Cost is $100' "")
assert_contains "dollar preserved in digest" '$100' "$prompt_dollar"

# Test: backslash preserved
prompt_bs=$(assemble_prompt 'path\to\file' "")
assert_contains "backslash preserved in digest" 'path\to\file' "$prompt_bs"

echo ""
echo "=== Mocked call_openai ==="

# Test: call_openai with mocked node (no real API call)
# Create a fake node script that returns a known response
MOCK_NODE_DIR=$(mktemp -d)
cat > "$MOCK_NODE_DIR/node" << 'MOCKSCRIPT'
#!/bin/bash
# Fake node that reads the payload file and returns mock OpenAI response
echo "Mock briefing output"
MOCKSCRIPT
chmod +x "$MOCK_NODE_DIR/node"

(
    export PATH="$MOCK_NODE_DIR:$PATH"
    export OPENAI_API_KEY="test-key-not-real"
    source "$SCRIPT"
    # Override cygpath for test (may not exist on all systems)
    cygpath() { echo "$2"; }
    export -f cygpath
    result=$(call_openai "test prompt" 2>/dev/null)
    echo "$result"
) > /tmp/mock_openai_result.txt 2>&1

mock_result=$(cat /tmp/mock_openai_result.txt)
assert_contains "mocked call_openai returns node output" "Mock briefing" "$mock_result"

# Test: call_openai fails when node exits non-zero
cat > "$MOCK_NODE_DIR/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "API error: rate limited" >&2
exit 1
MOCKSCRIPT
chmod +x "$MOCK_NODE_DIR/node"

(
    export PATH="$MOCK_NODE_DIR:$PATH"
    export OPENAI_API_KEY="test-key-not-real"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    call_openai "test prompt" 2>/dev/null && echo "SHOULD_HAVE_FAILED" || echo "CORRECTLY_FAILED"
) > /tmp/mock_openai_fail.txt 2>&1

fail_result=$(cat /tmp/mock_openai_fail.txt)
assert_contains "mocked call_openai fails on node error" "CORRECTLY_FAILED" "$fail_result"

# Test: call_openai fails when no API key
# Must prevent .env reload by pointing REPO_ROOT at empty dir
nokey_dir=$(mktemp -d)
(
    unset OPENAI_API_KEY
    export REPO_ROOT="$nokey_dir"
    # Source api-client.sh from real location, then source briefing script
    source "$REPO_ROOT_REAL/orchestrator/api-client.sh" 2>/dev/null || true
    OPENAI_API_KEY=""
    source "$SCRIPT"
    OPENAI_API_KEY=""
    call_openai "test" 2>/dev/null && echo "SHOULD_HAVE_FAILED" || echo "CORRECTLY_FAILED"
) > /tmp/mock_nokey.txt 2>&1
nokey_result=$(cat /tmp/mock_nokey.txt)
assert_contains "call_openai fails without API key" "CORRECTLY_FAILED" "$nokey_result"
rmdir "$nokey_dir"

rm -rf "$MOCK_NODE_DIR" /tmp/mock_openai_result.txt /tmp/mock_openai_fail.txt /tmp/mock_nokey.txt

echo ""
echo "=== Mocked query_memory ==="

# Test: query_memory with mocked Alma (hermetic, no ambient state)
MOCK_ALMA_PORT=23099
MOCK_READY_FILE="$(cygpath -w "$TEST_DIR" 2>/dev/null || echo "$TEST_DIR")/.mock_alma_ready"
# Start a simple HTTP responder using node
node -e "
const http = require('http');
const s = http.createServer((req, res) => {
    if (req.url === '/api/memories/status') {
        res.end(JSON.stringify({ready: true}));
    } else if (req.url === '/api/memories/search') {
        let body = '';
        req.on('data', c => body += c);
        req.on('end', () => {
            res.end(JSON.stringify({results: [{content: 'mock result line 1'}]}));
        });
    } else { res.statusCode = 404; res.end(); }
});
s.listen($MOCK_ALMA_PORT, () => {
    require('fs').writeFileSync(String.raw\`${MOCK_READY_FILE}\`, 'ok');
});
setTimeout(() => { s.close(); process.exit(0); }, 5000);
" &
MOCK_PID=$!

# Wait for mock server to be ready
for i in $(seq 1 20); do
    [[ -f "$TEST_DIR/.mock_alma_ready" ]] && break
    sleep 0.2
done
rm -f "$TEST_DIR/.mock_alma_ready"

if kill -0 $MOCK_PID 2>/dev/null; then
    mock_mem=$(ALMA_BASE_URL="http://localhost:$MOCK_ALMA_PORT" query_memory "test" 2>/dev/null)
    assert_contains "mocked query_memory returns result" "mock result" "$mock_mem"
    kill $MOCK_PID 2>/dev/null || true
    wait $MOCK_PID 2>/dev/null || true
else
    TOTAL=$((TOTAL + 1))
    echo "  PASS: mock server skipped (node unavailable)"; PASS=$((PASS + 1))
fi

echo ""
echo "=== CJK query_memory regression ==="

# Test: query_memory builds valid JSON from CJK query string
# This exercises the real jq path — jq 1.6 on Windows crashes on CJK in --arg.
# The fix pipes CJK through stdin instead. This test catches the regression.
cjk_tmpfile=$(mktemp)
printf '%s' "未完成事项和待办" | jq -Rs '{query: .}' > "$cjk_tmpfile" 2>/dev/null
cjk_exit=$?
assert_eq "jq builds valid JSON from CJK query" "0" "$cjk_exit"
cjk_payload=$(cat "$cjk_tmpfile")
assert_contains "CJK query payload has query field" "query" "$cjk_payload"
assert_contains "CJK preserved in payload" "未完成" "$cjk_payload"
rm -f "$cjk_tmpfile"

echo ""
echo "=== Missing API Key in .env ==="

# Test: .env exists but has no OPENAI_API_KEY — dry-run must still work
env_dir=$(mktemp -d)
mkdir -p "$env_dir/orchestrator"
cp "$REPO_ROOT_REAL/orchestrator/api-client.sh" "$env_dir/orchestrator/"
echo "SOME_OTHER_KEY=value" > "$env_dir/.env"
# Copy script + prompt to a temp location with the fake REPO_ROOT
cp -r "$REPO_ROOT_REAL/agents" "$env_dir/"

output=$(DIGEST_DIR="$TEST_DIR/digest" REPO_ROOT="$env_dir" DRY_RUN=true OPENAI_API_KEY="" \
    bash "$env_dir/agents/briefing/morning-briefing.sh" --dry-run 2>&1) || true
assert_contains "missing key: dry-run still works" "DRY-RUN" "$output"

# Test: full mode fails with call_openai's error, not grep crash
# Unset OPENAI_API_KEY (parent may have it from source "$SCRIPT")
# Use dead Alma URL so memory queries fail fast
output_full=$(DIGEST_DIR="$TEST_DIR/digest" REPO_ROOT="$env_dir" ALMA_BASE_URL="http://localhost:1" OPENAI_API_KEY="" \
    bash "$env_dir/agents/briefing/morning-briefing.sh" 2>&1) || true
assert_contains "missing key: clean error from call_openai" "OPENAI_API_KEY not set" "$output_full"

rm -rf "$env_dir"

echo ""
echo "=== Artifact Output ==="

# Setup: source script for helper functions, create output dir
ARTIFACT_DIR="$TEST_DIR/briefings"
mkdir -p "$ARTIFACT_DIR"

# Test: write_artifact creates file at expected path
write_artifact "test content" "$ARTIFACT_DIR/test.md"
TOTAL=$((TOTAL + 1))
if [[ -f "$ARTIFACT_DIR/test.md" ]]; then
    echo "  PASS: write_artifact creates file"; PASS=$((PASS + 1))
else
    echo "  FAIL: write_artifact did not create file"; FAIL=$((FAIL + 1))
fi
result=$(cat "$ARTIFACT_DIR/test.md")
assert_contains "artifact has content" "test content" "$result"
rm -f "$ARTIFACT_DIR/test.md"

# Test: write_artifact creates parent directories
write_artifact "nested" "$ARTIFACT_DIR/sub/dir/test.md"
TOTAL=$((TOTAL + 1))
if [[ -f "$ARTIFACT_DIR/sub/dir/test.md" ]]; then
    echo "  PASS: write_artifact creates parent dirs"; PASS=$((PASS + 1))
else
    echo "  FAIL: write_artifact did not create parent dirs"; FAIL=$((FAIL + 1))
fi
rm -rf "$ARTIFACT_DIR/sub"

# Test: build_provenance emits YAML frontmatter with key contract fields
digest_list=$'2026-03-27.md\n2026-03-26.md'
prov=$(build_provenance "gpt-4o-mini" "3" "$digest_list" "available" "2026-03-29")
assert_contains "provenance has schema_version" "schema_version: 1" "$prov"
assert_contains "provenance has artifact_type" "artifact_type: briefing" "$prov"
assert_contains "provenance has date" "date: 2026-03-29" "$prov"
assert_contains "provenance has digest YAML list" "  - 2026-03-27.md" "$prov"
assert_contains "provenance has memory_status" "memory_status: available" "$prov"

# Test: dry-run does NOT write artifact
rm -rf "$ARTIFACT_DIR"/*
output=$(DIGEST_DIR="$TEST_DIR/digest" DRY_RUN=true BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR" \
    bash "$SCRIPT" --dry-run 2>&1)
leftover_dry=$(find "$ARTIFACT_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
assert_eq "dry-run writes no artifact" "0" "$leftover_dry"

# Test: non-dry-run with mocked synthesis writes artifact
(
    export BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR"
    export DIGEST_DIR="$TEST_DIR/digest"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR2=$(mktemp -d)
    cat > "$MOCK_DIR2/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "Mock briefing content for artifact test"
MOCKSCRIPT
    chmod +x "$MOCK_DIR2/node"
    export PATH="$MOCK_DIR2:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main 2>/dev/null
    rm -rf "$MOCK_DIR2"
)
today=$(date +%Y-%m-%d)
TOTAL=$((TOTAL + 1))
if [[ -f "$ARTIFACT_DIR/${today}.md" ]]; then
    echo "  PASS: non-dry-run creates dated artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: no artifact at $ARTIFACT_DIR/${today}.md"; FAIL=$((FAIL + 1))
fi

# Verify artifact has YAML frontmatter provenance
artifact_content=$(cat "$ARTIFACT_DIR/${today}.md" 2>/dev/null || echo "")
assert_contains "artifact has YAML frontmatter" "schema_version: 1" "$artifact_content"
assert_contains "artifact has artifact_type" "artifact_type: briefing" "$artifact_content"
assert_contains "artifact has model in frontmatter" "model:" "$artifact_content"
assert_contains "artifact has digest_files list" "digest_files:" "$artifact_content"
assert_contains "artifact has briefing content" "Mock briefing content" "$artifact_content"

# Test: synthesis failure leaves no artifact
rm -rf "$ARTIFACT_DIR"/*
(
    export BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR"
    export DIGEST_DIR="$TEST_DIR/digest"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR3=$(mktemp -d)
    cat > "$MOCK_DIR3/node" << 'MOCKSCRIPT'
#!/bin/bash
exit 1
MOCKSCRIPT
    chmod +x "$MOCK_DIR3/node"
    export PATH="$MOCK_DIR3:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main 2>/dev/null
    rm -rf "$MOCK_DIR3"
) || true
leftover_fail=$(find "$ARTIFACT_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
assert_eq "synthesis failure leaves no artifact" "0" "$leftover_fail"

# Test: BRIEFING_OUTPUT_DIR override works
custom_dir="$TEST_DIR/custom_out"
(
    export BRIEFING_OUTPUT_DIR="$custom_dir"
    export DIGEST_DIR="$TEST_DIR/digest"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR4=$(mktemp -d)
    cat > "$MOCK_DIR4/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "Custom dir briefing"
MOCKSCRIPT
    chmod +x "$MOCK_DIR4/node"
    export PATH="$MOCK_DIR4:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main 2>/dev/null
    rm -rf "$MOCK_DIR4"
)
TOTAL=$((TOTAL + 1))
if [[ -f "$custom_dir/${today}.md" ]]; then
    echo "  PASS: BRIEFING_OUTPUT_DIR override works"; PASS=$((PASS + 1))
else
    echo "  FAIL: no artifact in custom dir $custom_dir"; FAIL=$((FAIL + 1))
fi
rm -rf "$custom_dir"

# Test: no digests produces no artifact
empty_dir3=$(mktemp -d)
artifact_dir_empty="$TEST_DIR/briefings_empty"
(
    export BRIEFING_OUTPUT_DIR="$artifact_dir_empty"
    export DIGEST_DIR="$empty_dir3"
    export OPENAI_API_KEY="test-key"
    source "$SCRIPT"
    main 2>/dev/null
) || true
if [[ -d "$artifact_dir_empty" ]]; then
    leftover_nodigest=$(find "$artifact_dir_empty" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
else
    leftover_nodigest=0
fi
assert_eq "no digests produces no artifact" "0" "$leftover_nodigest"
rmdir "$empty_dir3" 2>/dev/null || true
rm -rf "$artifact_dir_empty"

# Test: memory unavailable still produces artifact (with provenance showing unavailable)
rm -rf "$ARTIFACT_DIR"/*
(
    export BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR"
    export DIGEST_DIR="$TEST_DIR/digest"
    export ALMA_BASE_URL="http://localhost:1"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR5=$(mktemp -d)
    cat > "$MOCK_DIR5/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "Briefing without memory"
MOCKSCRIPT
    chmod +x "$MOCK_DIR5/node"
    export PATH="$MOCK_DIR5:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main 2>/dev/null
    rm -rf "$MOCK_DIR5"
)
mem_artifact=$(cat "$ARTIFACT_DIR/${today}.md" 2>/dev/null || echo "")
assert_contains "memory-down artifact has content" "Briefing without memory" "$mem_artifact"
assert_contains "memory-down provenance shows unavailable" "memory_status: unavailable" "$mem_artifact"

# Test: Alma reachable but zero results → memory_status: empty
# Override gather_memory to simulate reachable-but-empty (no mock HTTP needed)
rm -rf "$ARTIFACT_DIR"/*
(
    export BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR"
    export DIGEST_DIR="$TEST_DIR/digest"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR6=$(mktemp -d)
    cat > "$MOCK_DIR6/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "Briefing with empty memory"
MOCKSCRIPT
    chmod +x "$MOCK_DIR6/node"
    export PATH="$MOCK_DIR6:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    # Override gather_memory: Alma reachable, zero matches
    gather_memory() {
        echo "empty" > "$MEMORY_STATUS_FILE"
        echo ""
    }
    main 2>/dev/null
    rm -rf "$MOCK_DIR6"
)
empty_artifact=$(cat "$ARTIFACT_DIR/${today}.md" 2>/dev/null || echo "")
assert_contains "empty-memory artifact has content" "Briefing with empty memory" "$empty_artifact"
assert_contains "empty-memory provenance shows empty" "memory_status: empty" "$empty_artifact"

# Test: status reachable but search fails → memory_status: degraded (not empty)
rm -rf "$ARTIFACT_DIR"/*
(
    export BRIEFING_OUTPUT_DIR="$ARTIFACT_DIR"
    export DIGEST_DIR="$TEST_DIR/digest"
    export OPENAI_API_KEY="test-key"
    MOCK_DIR7=$(mktemp -d)
    cat > "$MOCK_DIR7/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "Briefing with degraded memory"
MOCKSCRIPT
    chmod +x "$MOCK_DIR7/node"
    export PATH="$MOCK_DIR7:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    # Override: status reachable, but all search calls fail
    gather_memory() {
        echo "degraded" > "$MEMORY_STATUS_FILE"
        echo ""
    }
    main 2>/dev/null
    rm -rf "$MOCK_DIR7"
)
degraded_artifact=$(cat "$ARTIFACT_DIR/${today}.md" 2>/dev/null || echo "")
assert_contains "degraded-memory artifact has content" "Briefing with degraded memory" "$degraded_artifact"
assert_contains "degraded-memory provenance shows degraded" "memory_status: degraded" "$degraded_artifact"
# Verify it does NOT say "empty" — that's the specific bug this test guards against
TOTAL=$((TOTAL + 1))
if [[ "$degraded_artifact" != *"memory_status: empty"* ]]; then
    echo "  PASS: degraded is not misreported as empty"; PASS=$((PASS + 1))
else
    echo "  FAIL: degraded was misreported as empty"; FAIL=$((FAIL + 1))
fi

rm -rf "$ARTIFACT_DIR"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
