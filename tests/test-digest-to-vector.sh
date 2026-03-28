#!/bin/bash
# tests/test-digest-to-vector.sh — Tests for digest-to-vector glue layer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/pipelines/digest/digest-to-vector.sh"

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

# --- Fixtures ---
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

create_fixtures() {
    cat > "$TEST_DIR/2026-03-23.md" << 'FIXTURE'
# 2026-03-23 群聊摘要

## 主要话题
- [服务器初建]: Fireflow Discord 服务器正式启用

## 关键事件与决策
- Fireflow服务器创建，仅两人

## 氛围
- 新手村开荒气氛
FIXTURE

    cat > "$TEST_DIR/2026-03-24.md" << 'FIXTURE'
# 2026-03-24 群聊摘要

## 主要话题
- [Agent Voice上线]: 语音播报系统搭建完成
- [频道架构]: 创建了#agent-internal频道

## 关键事件与决策
- Agent Voice成功上线
- 语音播报系统完整闭环

## 人物动态
- @karlamo: 展现强执行力

## 氛围
- 高产出日
FIXTURE
}

create_fixtures

# --- Tests go here (added in subsequent tasks) ---

echo "=== Chunking ==="

# Source script (loads functions, does not run main)
export DIGEST_DIR="$TEST_DIR"
source "$SCRIPT"

# Test: 3-section file produces 3 chunks
chunks=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-23.md")
assert_eq "3-section file produces 3 chunks" "3" "${#chunks[@]}"

# Test: first chunk starts with ## heading
assert_contains "chunk 1 starts with heading" "## 主要话题" "${chunks[0]}"

# Test: first chunk contains body text
assert_contains "chunk 1 contains body" "服务器初建" "${chunks[0]}"

# Test: top-level title not in any chunk
all_chunks="${chunks[*]}"
TOTAL=$((TOTAL + 1))
if [[ "$all_chunks" != *"# 2026-03-23 群聊摘要"* ]]; then
    echo "  PASS: top-level title excluded from chunks"
    PASS=$((PASS + 1))
else
    echo "  FAIL: top-level title found in chunks"
    FAIL=$((FAIL + 1))
fi

# Test: 4-section file produces 4 chunks
chunks2=()
while IFS= read -r -d $'\x1e' chunk; do
    chunks2+=("$chunk")
done < <(chunk_markdown "$TEST_DIR/2026-03-24.md")
assert_eq "4-section file produces 4 chunks" "4" "${#chunks2[@]}"

# Test: last chunk of 4-section file
assert_contains "last chunk is atmosphere" "高产出日" "${chunks2[3]}"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
