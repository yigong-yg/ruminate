#!/bin/bash
# tests/test-youtube-chew.sh — Tests for YouTube chew-short derived view
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/pipelines/youtube/youtube-chew.sh"

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
trap 'rm -rf "$TEST_DIR"' EXIT

create_fixtures() {
    mkdir -p "$TEST_DIR/youtube"

    # Fixture A: long Chinese interview (matches Saining Xie shape)
    cat > "$TEST_DIR/youtube/zhinterview1.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: youtube_canonical
video_id: zhinterview1
title: "谢赛宁七小时对话：世界模型、AMI Labs、Yann LeCun"
channel: 张小珺Podcast
duration_seconds: 24278
upload_date: 2026-03-16
ingested_at: 2026-03-30T12:00:00-06:00
transcript_source: official
subtitle_language: zh
chapters: 3
word_count: 600
---

## Source Description

2026年春天，谢赛宁与图灵奖得主Yann LeCun一起创立了AMI Labs。

## 创业起点

谢赛宁在纽约大学的办公室里和Yann LeCun讨论了世界模型的核心概念
他们认为当前的大语言模型缺乏对物理世界的真正理解
AMI Labs的目标是建造能够理解三维世界的智能系统
团队目前有25人来自FAIR和Meta AI Research

## 世界模型的核心观点

LeCun认为自回归模型有根本性缺陷
他提出的JEPA架构试图在潜在空间而非像素空间做预测
谢赛宁解释了为什么视觉理解比语言理解更难
他们团队在做的是让机器像婴儿一样学习物理规律

## 关于OpenAI和竞争格局

谢赛宁评价了OpenAI的路线选择
他认为scaling law不是万能的
AMI Labs选择了一条完全不同的技术路径
他坦言自己对行业的泡沫化趋势感到担忧
FIXTURE

    # Fixture B: short English tutorial (different shape)
    cat > "$TEST_DIR/youtube/entutorial1.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: youtube_canonical
video_id: entutorial1
title: React in 100 Seconds
channel: Fireship
duration_seconds: 128
upload_date: 2020-09-08
ingested_at: 2026-03-30T12:00:00-06:00
transcript_source: auto
subtitle_language: en
chapters: 2
word_count: 120
---

## Source Description

React is a JavaScript library for building user interfaces.

## What is React

React is a JavaScript library created at Facebook
It uses a virtual DOM to efficiently update the UI
Components are the building blocks of React applications
JSX lets you write HTML-like syntax in JavaScript

## Hooks and State

React hooks like useState and useEffect replaced class components
The useState hook manages local component state
useEffect handles side effects like API calls
Custom hooks let you extract reusable stateful logic
FIXTURE
}

create_fixtures

echo "=== Frontmatter Parsing ==="

export CHEW_OUTPUT_DIR="$TEST_DIR/chew_out"
source "$SCRIPT"

# Test: parse_canonical_frontmatter on Chinese interview
eval "$(parse_canonical_frontmatter "$TEST_DIR/youtube/zhinterview1.md")"
assert_eq "zh: video_id" "zhinterview1" "$VIDEO_ID"
assert_contains "zh: title has Chinese" "谢赛宁" "$TITLE"
assert_eq "zh: channel" "张小珺Podcast" "$CHANNEL"
assert_eq "zh: subtitle_language" "zh" "$SUBTITLE_LANGUAGE"
assert_eq "zh: transcript_source" "official" "$TRANSCRIPT_SOURCE"

# Test: parse_canonical_frontmatter on English tutorial
eval "$(parse_canonical_frontmatter "$TEST_DIR/youtube/entutorial1.md")"
assert_eq "en: video_id" "entutorial1" "$VIDEO_ID"
assert_eq "en: title" "React in 100 Seconds" "$TITLE"
assert_eq "en: channel" "Fireship" "$CHANNEL"
assert_eq "en: subtitle_language" "en" "$SUBTITLE_LANGUAGE"
assert_eq "en: transcript_source" "auto" "$TRANSCRIPT_SOURCE"

echo ""
echo "=== Body Extraction ==="

# Test: extract_body returns content after frontmatter
body_zh=$(extract_body "$TEST_DIR/youtube/zhinterview1.md")
assert_contains "zh body has chapter" "创业起点" "$body_zh"
assert_contains "zh body has content" "谢赛宁" "$body_zh"
TOTAL=$((TOTAL + 1))
if [[ "$body_zh" != *"schema_version"* ]]; then
    echo "  PASS: zh body excludes frontmatter"; PASS=$((PASS + 1))
else
    echo "  FAIL: zh body contains frontmatter"; FAIL=$((FAIL + 1))
fi

body_en=$(extract_body "$TEST_DIR/youtube/entutorial1.md")
assert_contains "en body has chapter" "What is React" "$body_en"
assert_contains "en body has content" "virtual DOM" "$body_en"

echo ""
echo "=== Prompt Assembly ==="

prompt=$(build_chew_prompt "$body_zh" "Test Title" "Test Channel")
assert_contains "prompt has system instructions" "high-density summary" "$prompt"
assert_contains "prompt has title" "Test Title" "$prompt"
assert_contains "prompt has body content" "谢赛宁" "$prompt"
assert_contains "prompt has output structure" "Key Takeaways" "$prompt"
assert_contains "prompt has output structure" "Per-Chapter Summaries" "$prompt"
assert_contains "prompt has output structure" "Notable Quotes" "$prompt"

echo ""
echo "=== Chew Frontmatter ==="

fm=$(build_chew_frontmatter "vid1" "Test: Title" "Chan" "zh" "official" "vid1.md" "gpt-4o-mini" "500")
assert_contains "fm has schema_version" "schema_version: 1" "$fm"
assert_contains "fm has artifact_type" "artifact_type: youtube_chew_short" "$fm"
assert_contains "fm has source_artifact" "source_artifact: vid1.md" "$fm"
assert_contains "fm has video_id" "video_id: vid1" "$fm"
assert_contains "fm has quoted title" '"Test: Title"' "$fm"
assert_contains "fm has subtitle_language" "subtitle_language: zh" "$fm"
assert_contains "fm has transcript_source" "transcript_source: official" "$fm"
assert_contains "fm has model" "model: gpt-4o-mini" "$fm"

echo ""
echo "=== Dry-Run ==="

# Test: dry-run prints prompt, writes nothing
output=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/zhinterview1.md" --dry-run 2>&1)
assert_contains "dry-run has DRY-RUN header" "DRY-RUN" "$output"
assert_contains "dry-run has video_id" "zhinterview1" "$output"
assert_contains "dry-run has Chinese content" "谢赛宁" "$output"
assert_contains "dry-run has prompt structure" "Key Takeaways" "$output"

TOTAL=$((TOTAL + 1))
if [[ $(find "$TEST_DIR/chew_out" -name '*.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: dry-run writes no artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: dry-run wrote artifact"; FAIL=$((FAIL + 1))
fi

# Test: dry-run works on English fixture too
output_en=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/entutorial1.md" --dry-run 2>&1)
assert_contains "en dry-run has content" "virtual DOM" "$output_en"

echo ""
echo "=== Mocked Synthesis ==="

# Mock node to return a known chew response
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "## Key Takeaways
- Mock takeaway about world models
## Per-Chapter Summaries
### Chapter 1
Mock chapter summary
## Notable Quotes & Specifics
- Mock quote from chapter 1"
MOCKSCRIPT
chmod +x "$MOCK_DIR/node"

# Test: normal run writes artifact to chew/ subdir
(
    export CHEW_OUTPUT_DIR=""
    export OPENAI_API_KEY="test-key"
    export PATH="$MOCK_DIR:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    INPUT_FILE="$TEST_DIR/youtube/zhinterview1.md"
    main "$INPUT_FILE" 2>/dev/null
)

TOTAL=$((TOTAL + 1))
if [[ -f "$TEST_DIR/youtube/chew/zhinterview1-short.md" ]]; then
    echo "  PASS: artifact at chew/{video-id}-short.md"; PASS=$((PASS + 1))
else
    echo "  FAIL: no artifact at $TEST_DIR/youtube/chew/zhinterview1-short.md"; FAIL=$((FAIL + 1))
fi

# Verify frontmatter passthrough
art=$(cat "$TEST_DIR/youtube/chew/zhinterview1-short.md" 2>/dev/null || echo "")
assert_contains "artifact has chew_short type" "artifact_type: youtube_chew_short" "$art"
assert_contains "artifact has source_artifact" "source_artifact: zhinterview1.md" "$art"
assert_contains "artifact has video_id" "video_id: zhinterview1" "$art"
assert_contains "artifact has subtitle_language" "subtitle_language: zh" "$art"
assert_contains "artifact has transcript_source" "transcript_source: official" "$art"
assert_contains "artifact has chew content" "Mock takeaway" "$art"

rm -rf "$TEST_DIR/youtube/chew"

# Test: CHEW_OUTPUT_DIR override
custom_dir="$TEST_DIR/custom_chew"
(
    export CHEW_OUTPUT_DIR="$custom_dir"
    export OPENAI_API_KEY="test-key"
    export PATH="$MOCK_DIR:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main "$TEST_DIR/youtube/entutorial1.md" 2>/dev/null
)

TOTAL=$((TOTAL + 1))
if [[ -f "$custom_dir/entutorial1-short.md" ]]; then
    echo "  PASS: CHEW_OUTPUT_DIR override works"; PASS=$((PASS + 1))
else
    echo "  FAIL: no artifact in custom dir"; FAIL=$((FAIL + 1))
fi

# Verify English fixture frontmatter
art_en=$(cat "$custom_dir/entutorial1-short.md" 2>/dev/null || echo "")
assert_contains "en artifact has subtitle_language" "subtitle_language: en" "$art_en"
assert_contains "en artifact has transcript_source" "transcript_source: auto" "$art_en"

rm -rf "$custom_dir"

echo ""
echo "=== Error Handling ==="

# Test: missing input file
missing_output=$(bash "$SCRIPT" "/nonexistent/file.md" 2>&1) || true
assert_contains "missing file error" "not found" "$missing_output"

# Test: missing API key (non-dry-run)
# Must prevent .env reload — point REPO_ROOT at empty dir
nokey_dir=$(mktemp -d)
(
    export OPENAI_API_KEY=""
    export REPO_ROOT="$nokey_dir"
    export PATH="$MOCK_DIR:$PATH"
    source "$SCRIPT"
    OPENAI_API_KEY=""
    cygpath() { echo "$2"; }
    export -f cygpath
    call_openai "test" 2>/dev/null && echo "SHOULD_FAIL" || echo "CORRECTLY_FAILED"
) > "$TEST_DIR/nokey.txt" 2>&1
rmdir "$nokey_dir"
nokey=$(cat "$TEST_DIR/nokey.txt")
assert_contains "missing key fails" "CORRECTLY_FAILED" "$nokey"

# Test: no partial file on API failure
fail_dir="$TEST_DIR/fail_chew"
cat > "$MOCK_DIR/node" << 'MOCKSCRIPT'
#!/bin/bash
exit 1
MOCKSCRIPT
chmod +x "$MOCK_DIR/node"

(
    export CHEW_OUTPUT_DIR="$fail_dir"
    export OPENAI_API_KEY="test-key"
    export PATH="$MOCK_DIR:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main "$TEST_DIR/youtube/zhinterview1.md" 2>/dev/null
) || true

TOTAL=$((TOTAL + 1))
if [[ $(find "$fail_dir" -name '*.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: no partial file on API failure"; PASS=$((PASS + 1))
else
    echo "  FAIL: partial file left after API failure"; FAIL=$((FAIL + 1))
fi

rm -rf "$MOCK_DIR" "$fail_dir"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
