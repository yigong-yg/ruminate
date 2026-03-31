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

    # Fixture A: long Chinese interview (matches Saining Xie shape, body > 2000 chars)
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
word_count: 15000
---

## Source Description

2026年春天，谢赛宁与图灵奖得主Yann LeCun一起创立了AMI Labs。这是一个关于世界模型和人工智能未来的七小时深度对话。

## 创业起点

谢赛宁在纽约大学的办公室里和Yann LeCun讨论了世界模型的核心概念。他们认为当前的大语言模型缺乏对物理世界的真正理解。AMI Labs的目标是建造能够理解三维世界的智能系统。团队目前有25人来自FAIR和Meta AI Research。谢赛宁回忆了自己在上海交通大学ACM班的经历，以及后来在UCSD跟随导师涂卓文做研究的日子。他在PhD期间实习了五个不同的机构，包括NEC Labs America、Adobe、Meta、Google Research和DeepMind。这些经历拓宽了他的视野，但也让他的研究方向变得碎片化。他与何恺明在Meta的合作是职业生涯的一个转折点，他们一起做了ResNeXt项目。

## 世界模型的核心观点

LeCun认为自回归模型有根本性缺陷。他提出的JEPA架构试图在潜在空间而非像素空间做预测。谢赛宁解释了为什么视觉理解比语言理解更难。他们团队在做的是让机器像婴儿一样学习物理规律。世界模型不仅仅是一个技术路线，而是一个所有人都在追求的目标。好的表征对于AI系统的有效决策至关重要。语言是一种交流工具，但它并不涵盖智能的全部。视觉模型和语言模型的scaling laws有根本性不同。

## 关于OpenAI和竞争格局

谢赛宁评价了OpenAI的路线选择。他认为scaling law不是万能的。AMI Labs选择了一条完全不同的技术路径。他坦言自己对行业的泡沫化趋势感到担忧。PhD毕业后他面临在OpenAI和Meta之间的选择。尽管收到了OpenAI的offer和Ilya Sutskever的亲自电话邀请，他还是选择了Meta，因为可以和何恺明、Piotr Dollar、Ross Girshick这样的顶级研究者合作。研究是一个非线性过程，最有价值的见解往往来自意想不到的失败。谢赛宁在纽约的公寓里接受了这次长达七小时的对话采访。他谈到了自己从上海交大到纽约大学的学术旅程，从计算机视觉到世界模型的研究转变。他相信真正的智能需要对物理世界有深刻的理解，而不仅仅是处理文本。AMI Labs的25人团队正在探索一条不同于主流大语言模型的道路。他们的目标是建造能够像人类婴儿一样通过观察和互动来学习世界规律的系统。LeCun的JEPA架构代表了一种全新的思维方式。谢赛宁说他对未来充满了期待，但也清醒地认识到这条路的艰难。他提到了学术界和工业界在AI研究方法上的根本分歧，以及这种分歧如何影响了整个领域的发展方向。他认为多样化的研究路径是科学进步的关键。在长达数小时的对话中，他分享了很多个人故事和思考。从小时候在家乡的经历，到在上海交大ACM班遇到的同学和老师，再到在美国的求学和工作经历。每一段经历都塑造了他对AI和科学研究的独特理解。他特别提到了在Google Research和DeepMind实习期间学到的不同研究文化。谢赛宁在采访中还详细讨论了世界模型的技术细节。他解释了为什么当前的大语言模型虽然在文本任务上表现出色，但在理解物理世界方面存在根本性局限。他用了一个生动的比喻来说明这一点：语言模型就像一个只通过阅读书籍来学习的人，而世界模型则是通过直接与环境互动来学习的人。两者之间的区别不仅仅是数据类型的不同，而是学习范式的根本差异。他还提到了JEPA架构的核心思想，以及为什么在潜在空间中进行预测比在像素空间中进行预测更有效率。这些技术洞察展示了谢赛宁作为一位年轻科学家的深刻思考能力和创新精神。在对话的最后部分，他谈到了对年轻研究者的建议，强调了好奇心和独立思考的重要性。他说真正的突破往往来自于那些敢于质疑常规智慧的人。
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

    # Fixture C: micro-input (< 2000 chars body → pass_through)
    cat > "$TEST_DIR/youtube/micro1.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: youtube_canonical
video_id: micro1
title: Me at the zoo
channel: jawed
duration_seconds: 19
upload_date: 2005-04-23
ingested_at: 2026-03-30T12:00:00-06:00
transcript_source: official
subtitle_language: en
chapters: 1
word_count: 50
---

## Source Description

First video on YouTube.

## Full Video

All right so here we are in front of the elephants.
FIXTURE

    # Fixture D: music content (body > 2000 chars but low wpm → music strategy)
    # word_count=80, duration=213s → wpm = 80*60/213 = 22 < 30
    # Body padded with repeated lyrics to exceed 2000 chars
    cat > "$TEST_DIR/youtube/music1.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: youtube_canonical
video_id: music1
title: Never Gonna Give You Up
channel: Rick Astley
duration_seconds: 213
upload_date: 2009-10-25
ingested_at: 2026-03-30T12:00:00-06:00
transcript_source: official
subtitle_language: en
chapters: 1
word_count: 80
---

## Source Description

Official music video for Never Gonna Give You Up by Rick Astley. Released in 1987 as the lead single from the album Whenever You Need Somebody. The song was written and produced by Stock Aitken Waterman.

## Full Song

We're no strangers to love
You know the rules and so do I
A full commitment's what I'm thinking of
You wouldn't get this from any other guy

I just wanna tell you how I'm feeling
Gotta make you understand

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you

We've known each other for so long
Your heart's been aching but you're too shy to say it
Inside we both know what's been going on
We know the game and we're gonna play it
And if you ask me how I'm feeling
Don't tell me you're too blind to see

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you

Ooh give you up
Ooh give you up
Never gonna give never gonna give give you up
Never gonna give never gonna give give you up

We've known each other for so long
Your heart's been aching but you're too shy to say it
Inside we both know what's been going on
We know the game and we're gonna play it

I just wanna tell you how I'm feeling
Gotta make you understand

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you

Never gonna give you up
Never gonna let you down
Never gonna run around and desert you
Never gonna make you cry
Never gonna say goodbye
Never gonna tell a lie and hurt you
FIXTURE
    # Pad zhinterview1 body to ensure > 2000 chars for routing
    local pad=""
    for i in $(seq 1 30); do
        pad="${pad}
Additional research discussion point ${i}: exploring novel approaches to understanding visual representations and world models in the context of modern AI systems."
    done
    echo "$pad" >> "$TEST_DIR/youtube/zhinterview1.md"

    # Pad music1 body to ensure > 2000 chars but keep wpm < 30
    local music_pad=""
    for i in $(seq 1 10); do
        music_pad="${music_pad}
Never gonna give you up never gonna let you down repeat ${i}"
    done
    echo "$music_pad" >> "$TEST_DIR/youtube/music1.md"
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
assert_eq "en: word_count" "120" "$SRC_WORD_COUNT"
assert_eq "en: duration" "128" "$SRC_DURATION"

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
assert_contains "prompt has distillation directive" "skeletal structure" "$prompt"
assert_contains "prompt has title" "Test Title" "$prompt"
assert_contains "prompt has body content" "谢赛宁" "$prompt"
assert_contains "prompt has output structure" "Core Throughline" "$prompt"
assert_contains "prompt has output structure" "Narrative Arc" "$prompt"
assert_contains "prompt has output structure" "Precision Anchors" "$prompt"
assert_contains "prompt has output structure" "Tensions" "$prompt"
assert_contains "prompt has anti-hallucination" "NEVER invent quotes" "$prompt"
assert_contains "prompt has zh grounding rule" "original-language fragments" "$prompt"

echo ""
echo "=== Chew Frontmatter ==="

fm=$(build_chew_frontmatter "vid1" "Test: Title" "Chan" "zh" "official" "vid1.md" "gpt-4o-mini" "500" "false" "600" "600")
assert_contains "fm has schema_version" "schema_version: 1" "$fm"
assert_contains "fm has artifact_type" "artifact_type: youtube_chew_short" "$fm"
assert_contains "fm has source_artifact" "source_artifact: vid1.md" "$fm"
assert_contains "fm has video_id" "video_id: vid1" "$fm"
assert_contains "fm has quoted title" '"Test: Title"' "$fm"
assert_contains "fm has subtitle_language" "subtitle_language: zh" "$fm"
assert_contains "fm has transcript_source" "transcript_source: official" "$fm"
assert_contains "fm has model" "model: gpt-4o-mini" "$fm"

echo ""
echo "=== Source Coverage Provenance ==="

# Test: non-truncated input → source_truncated: false
fm_full=$(build_chew_frontmatter "v1" "T" "C" "en" "auto" "v1.md" "gpt-4o" "500" "false" "800" "800")
assert_contains "non-truncated: source_truncated false" "source_truncated: false" "$fm_full"
assert_contains "non-truncated: chars used" "source_chars_used: 800" "$fm_full"
assert_contains "non-truncated: chars total" "source_chars_total: 800" "$fm_full"

# Test: truncated input → source_truncated: true with different used/total
fm_trunc=$(build_chew_frontmatter "v2" "T" "C" "zh" "official" "v2.md" "gpt-4o" "500" "true" "30000" "148000")
assert_contains "truncated: source_truncated true" "source_truncated: true" "$fm_trunc"
assert_contains "truncated: chars used" "source_chars_used: 30000" "$fm_trunc"
assert_contains "truncated: chars total" "source_chars_total: 148000" "$fm_trunc"

# Test: end-to-end — small fixture (under limit) produces source_truncated: false in artifact
# (uses the mocked synthesis path from later in the test)

echo ""
echo "=== Dry-Run ==="

# Test: dry-run prints prompt, writes nothing
output=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/zhinterview1.md" --dry-run 2>&1)
assert_contains "dry-run has DRY-RUN header" "DRY-RUN" "$output"
assert_contains "dry-run has video_id" "zhinterview1" "$output"
assert_contains "dry-run has Chinese content" "谢赛宁" "$output"
assert_contains "dry-run has prompt structure" "Core Throughline" "$output"

TOTAL=$((TOTAL + 1))
if [[ $(find "$TEST_DIR/chew_out" -name '*.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: dry-run writes no artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: dry-run wrote artifact"; FAIL=$((FAIL + 1))
fi

# Test: dry-run works on English fixture (--force: body < 2000 chars)
output_en=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/entutorial1.md" --dry-run --force 2>&1)
assert_contains "en dry-run has content" "virtual DOM" "$output_en"

echo ""
echo "=== Mocked Synthesis ==="

# Mock node to return a known chew response
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/node" << 'MOCKSCRIPT'
#!/bin/bash
echo "## Core Throughline
Mock throughline about world models and AMI Labs.

## Narrative Arc
- 谢赛宁与Yann LeCun在2026年创立AMI Labs（团队25人）
- Mock narrative point with concrete anchor

## Precision Anchors
- AMI Labs: founded 2026, 25-person team from FAIR
- Mock precision anchor

## Tensions & Contrarian Claims
- Mock contrarian claim about scaling laws"
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
assert_contains "artifact has chew content" "Mock throughline" "$art"
assert_contains "e2e non-truncated: source_truncated false" "source_truncated: false" "$art"
assert_contains "e2e non-truncated: chars used = total" "source_chars_used" "$art"

rm -rf "$TEST_DIR/youtube/chew"

# Test: CHEW_OUTPUT_DIR override (--force needed: entutorial1 body < 2000 chars)
custom_dir="$TEST_DIR/custom_chew"
(
    export CHEW_OUTPUT_DIR="$custom_dir"
    export OPENAI_API_KEY="test-key"
    export PATH="$MOCK_DIR:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main "$TEST_DIR/youtube/entutorial1.md" --force 2>/dev/null
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
echo "=== Routing ==="

# Test: pass_through on micro input (< 2000 chars body)
pt_out=$(bash "$SCRIPT" "$TEST_DIR/youtube/micro1.md" 2>&1) || true
assert_contains "pass_through: skipping message" "source too short" "$pt_out"
TOTAL=$((TOTAL + 1))
if [[ $(find "$TEST_DIR/youtube/chew" -name 'micro1-short.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: pass_through writes no artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: pass_through wrote artifact"; FAIL=$((FAIL + 1))
fi

# Test: music on low wpm input
# music1: word_count=80, duration=213s → wpm = 80*60/213 = 22 < 30
music_out=$(bash "$SCRIPT" "$TEST_DIR/youtube/music1.md" 2>&1) || true
assert_contains "music: skipping message" "music content detected" "$music_out"
assert_contains "music: shows wpm" "wpm=" "$music_out"

# Test: long_form routing on normal input
lf_out=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/zhinterview1.md" --dry-run 2>&1)
assert_contains "long_form: strategy shown" "strategy=long_form" "$lf_out"

# Test: --force bypasses pass_through routing
force_out=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/micro1.md" --force --dry-run 2>&1)
assert_contains "force: bypasses routing" "strategy=long_form" "$force_out"
assert_contains "force: shows force=true" "force=true" "$force_out"

# Test: dry-run prints strategy in header
assert_contains "dry-run header has strategy" "strategy=" "$lf_out"

echo ""
echo "=== Contract Validation ==="

# Test: expansion detection (output >= input) → exit 0, no artifact
# Uses --force on entutorial1 (short fixture) to bypass pass_through routing
# and actually reach the contract gate at output_chars >= source_chars_used
MOCK_DIR2=$(mktemp -d)
# Mock node that returns MORE text than the input body (~5000 chars > ~400 chars)
cat > "$MOCK_DIR2/node" << 'MOCKSCRIPT'
#!/bin/bash
for i in $(seq 1 60); do echo "This is a very long expansion line number $i that pads the output significantly beyond the input size."; done
MOCKSCRIPT
chmod +x "$MOCK_DIR2/node"

expansion_dir="$TEST_DIR/expansion_chew"
expansion_stderr=$(
    export CHEW_OUTPUT_DIR="$expansion_dir"
    export OPENAI_API_KEY="test-key"
    export PATH="$MOCK_DIR2:$PATH"
    source "$SCRIPT"
    cygpath() { echo "$2"; }
    export -f cygpath
    main "$TEST_DIR/youtube/entutorial1.md" --force 2>&1
) || true

TOTAL=$((TOTAL + 1))
if [[ $(find "$expansion_dir" -name '*.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: expansion discarded, no artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: expansion artifact was written"; FAIL=$((FAIL + 1))
fi
assert_contains "expansion: contract violation message" "Contract violation" "$expansion_stderr"
rm -rf "$MOCK_DIR2" "$expansion_dir"

echo ""
echo "=== Provenance Frontmatter ==="

# Test: frontmatter contains provenance, strategy, wpm
fm_test=$(build_chew_frontmatter "v1" "T" "C" "en" "auto" "v1.md" "gpt-4o" "500" "false" "5000" "5000" "long_form" "142")
assert_contains "fm has provenance" "provenance: source-only-unverified" "$fm_test"
assert_contains "fm has strategy" "strategy: long_form" "$fm_test"
assert_contains "fm has wpm" "wpm: 142" "$fm_test"

echo ""
echo "=== CJK Routing Safety ==="

# Test: CJK content with low wpm does NOT route to music
# (wc -w undercounts Chinese, making wpm artificially low)
cat > "$TEST_DIR/youtube/zhlow_wpm.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: youtube_canonical
video_id: zhlow1
title: Chinese Low WPM
channel: Test
duration_seconds: 7200
upload_date: 2026-01-01
ingested_at: 2026-03-30T00:00:00-06:00
transcript_source: official
subtitle_language: zh
chapters: 1
word_count: 800
---

## Content

FIXTURE
# Pad body > 2000 chars (each line ~30 chars, need ~70 lines)
for i in $(seq 1 70); do
    echo "这是第${i}段关于人工智能和世界模型的讨论内容，涉及深度学习和计算机视觉的前沿研究。" >> "$TEST_DIR/youtube/zhlow_wpm.md"
done

# wpm = 800*60/7200 = 6.6 → would be "music" without CJK guard
zh_route=$(DRY_RUN=true bash "$SCRIPT" "$TEST_DIR/youtube/zhlow_wpm.md" --dry-run 2>&1)
assert_contains "CJK low-wpm routes to long_form" "strategy=long_form" "$zh_route"

echo ""
echo "=== Input Contract Validation ==="

# Test: non-canonical artifact is rejected
cat > "$TEST_DIR/youtube/fake_artifact.md" << 'FIXTURE'
---
schema_version: 1
artifact_type: briefing
video_id: fake1
title: Not a canonical artifact
channel: Fake
---

## Some Content

This is not a youtube_canonical artifact.
FIXTURE
fake_out=$(bash "$SCRIPT" "$TEST_DIR/youtube/fake_artifact.md" 2>&1) || true
assert_contains "rejects non-canonical" "not a youtube_canonical" "$fake_out"

# Test: missing artifact_type is rejected
cat > "$TEST_DIR/youtube/no_type.md" << 'FIXTURE'
---
video_id: notype1
title: Missing Type
channel: Test
---

## Content

Some body text here.
FIXTURE
notype_out=$(bash "$SCRIPT" "$TEST_DIR/youtube/no_type.md" 2>&1) || true
assert_contains "rejects missing artifact_type" "not a youtube_canonical" "$notype_out"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
