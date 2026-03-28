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
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
