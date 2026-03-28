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

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
