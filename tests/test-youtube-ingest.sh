#!/bin/bash
# tests/test-youtube-ingest.sh — Tests for YouTube ingestion pipeline
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/pipelines/youtube/youtube-ingest.sh"

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

# --- Mock yt-dlp data ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

create_mock_data() {
    # Mock yt-dlp JSON metadata (what --dump-json produces) — with chapters
    cat > "$TEST_DIR/metadata.json" << 'MOCK_META'
{
    "id": "dQw4w9WgXcQ",
    "title": "Rick Astley - Never Gonna Give You Up (Official Video)",
    "channel": "Rick Astley",
    "duration": 212,
    "upload_date": "20091025",
    "description": "The official video for Never Gonna Give You Up by Rick Astley.\n\nTaken from the album Whenever You Need Somebody.",
    "chapters": [
        {"start_time": 0, "end_time": 60, "title": "Intro"},
        {"start_time": 60, "end_time": 150, "title": "Verse & Chorus"},
        {"start_time": 150, "end_time": 212, "title": "Outro"}
    ],
    "subtitles": {"en": [{"ext": "vtt", "url": "https://example.com/subs.vtt"}]},
    "automatic_captions": {}
}
MOCK_META

    # Mock metadata WITHOUT chapters (12 min video)
    cat > "$TEST_DIR/metadata_no_chapters.json" << 'MOCK_META'
{
    "id": "abc123test",
    "title": "Test Video Without Chapters",
    "channel": "Test Channel",
    "duration": 720,
    "upload_date": "20260315",
    "description": "A 12-minute test video with no chapter markers.",
    "chapters": null,
    "subtitles": {"en": [{"ext": "vtt", "url": "https://example.com/subs2.vtt"}]},
    "automatic_captions": {}
}
MOCK_META

    # Mock metadata with NO subtitles at all
    cat > "$TEST_DIR/metadata_no_subs.json" << 'MOCK_META'
{
    "id": "nosubs999",
    "title": "Video Without Subtitles",
    "channel": "Silent Channel",
    "duration": 300,
    "upload_date": "20260101",
    "description": "No captions available.",
    "chapters": null,
    "subtitles": {},
    "automatic_captions": {}
}
MOCK_META

    # Mock metadata with auto captions only
    cat > "$TEST_DIR/metadata_auto_subs.json" << 'MOCK_META'
{
    "id": "autosub456",
    "title": "Video With Auto Captions",
    "channel": "Auto Channel",
    "duration": 180,
    "upload_date": "20260201",
    "description": "Only auto-generated captions.",
    "chapters": null,
    "subtitles": {},
    "automatic_captions": {"en": [{"ext": "vtt", "url": "https://example.com/auto.vtt"}]}
}
MOCK_META

    # Mock VTT subtitle file (for chapters video)
    cat > "$TEST_DIR/subs.vtt" << 'MOCK_VTT'
WEBVTT
Kind: captions
Language: en

00:00:01.000 --> 00:00:04.500
We're no strangers to love

00:00:04.500 --> 00:00:08.000
You know the rules and so do I

00:00:08.000 --> 00:00:12.500
A full commitment's what I'm thinking of

00:00:12.500 --> 00:00:16.000
You wouldn't get this from any other guy

00:01:05.000 --> 00:01:10.000
Never gonna give you up

00:01:10.000 --> 00:01:14.000
Never gonna let you down

00:01:14.000 --> 00:01:18.000
Never gonna run around and desert you

00:02:35.000 --> 00:02:40.000
We've known each other for so long

00:02:40.000 --> 00:02:45.000
Your heart's been aching but you're too shy to say it
MOCK_VTT

    # Mock VTT for no-chapters video (12 min, needs time-based segmenting)
    cat > "$TEST_DIR/subs_long.vtt" << 'MOCK_VTT'
WEBVTT
Kind: captions
Language: en

00:00:01.000 --> 00:00:05.000
Welcome to this twelve minute video

00:00:05.000 --> 00:00:10.000
about software architecture patterns

00:03:00.000 --> 00:03:05.000
The first pattern is event sourcing

00:03:05.000 --> 00:03:10.000
which stores all changes as a sequence of events

00:06:00.000 --> 00:06:05.000
The second pattern is CQRS

00:06:05.000 --> 00:06:10.000
which separates read and write models

00:09:00.000 --> 00:09:05.000
The third pattern is saga

00:09:05.000 --> 00:09:10.000
which manages distributed transactions

00:11:00.000 --> 00:11:05.000
In summary these three patterns work well together
MOCK_VTT
}

create_mock_data

# --- Tests added in subsequent tasks ---

echo "=== Metadata Extraction ==="

export YOUTUBE_OUTPUT_DIR="$TEST_DIR/output"
source "$SCRIPT"

# Test: extract_metadata reads key fields from yt-dlp JSON
eval "$(extract_metadata "$TEST_DIR/metadata.json")"
assert_eq "video_id" "dQw4w9WgXcQ" "$VIDEO_ID"
assert_eq "title" "Rick Astley - Never Gonna Give You Up (Official Video)" "$TITLE"
assert_eq "channel" "Rick Astley" "$CHANNEL"
assert_eq "duration" "212" "$DURATION"
assert_eq "upload_date formatted" "2009-10-25" "$UPLOAD_DATE"

# Test: upload_date format conversion (YYYYMMDD → YYYY-MM-DD)
eval "$(extract_metadata "$TEST_DIR/metadata_no_chapters.json")"
assert_eq "upload_date conversion" "2026-03-15" "$UPLOAD_DATE"

echo ""
echo "=== Transcript Source Detection ==="

# Test: detect_transcript_source finds official subs + language
src=$(detect_transcript_source "$TEST_DIR/metadata.json")
assert_eq "official subs detected" "official en" "$src"

# Test: detect_transcript_source finds auto subs + language
src_auto=$(detect_transcript_source "$TEST_DIR/metadata_auto_subs.json")
assert_eq "auto subs detected" "auto en" "$src_auto"

# Test: detect_transcript_source returns none when no subs
src_none=$(detect_transcript_source "$TEST_DIR/metadata_no_subs.json")
assert_eq "no subs detected" "none" "$src_none"

# Test: zh-only subtitles are detected (not English-only policy)
cat > "$TEST_DIR/metadata_zh_only.json" << 'MOCK_META'
{
    "id": "zhonly123",
    "title": "Chinese Only Video",
    "channel": "Chinese Channel",
    "duration": 120,
    "upload_date": "20260301",
    "description": "Only Chinese subtitles.",
    "chapters": null,
    "subtitles": {"zh-Hans": [{"ext": "vtt", "url": "https://example.com/zh.vtt"}]},
    "automatic_captions": {}
}
MOCK_META
src_zh=$(detect_transcript_source "$TEST_DIR/metadata_zh_only.json")
assert_eq "zh-only official subs detected" "official zh-Hans" "$src_zh"

# Test: SUBTITLE_LANG override prefers specified language
cat > "$TEST_DIR/metadata_multi_lang.json" << 'MOCK_META'
{
    "id": "multilang789",
    "title": "Multi Language Video",
    "channel": "Global Channel",
    "duration": 200,
    "upload_date": "20260301",
    "description": "Multiple subtitle tracks.",
    "chapters": null,
    "subtitles": {"en": [{"ext": "vtt"}], "zh-Hans": [{"ext": "vtt"}], "ja": [{"ext": "vtt"}]},
    "automatic_captions": {}
}
MOCK_META
src_pref=$(SUBTITLE_LANG="zh-Hans" detect_transcript_source "$TEST_DIR/metadata_multi_lang.json")
assert_eq "preferred lang zh-Hans selected" "official zh-Hans" "$src_pref"

echo ""
echo "=== Chapter Detection ==="

# Test: extract_chapters returns chapters from metadata
chapters=$(extract_chapters "$TEST_DIR/metadata.json")
chapter_count=$(echo "$chapters" | jq 'length')
assert_eq "3 chapters from metadata" "3" "$chapter_count"
first_title=$(echo "$chapters" | jq -r '.[0].title')
assert_eq "first chapter title" "Intro" "$first_title"

# Test: extract_chapters generates time segments when no chapters
segments=$(extract_chapters "$TEST_DIR/metadata_no_chapters.json")
seg_count=$(echo "$segments" | jq 'length')
# 720s / 300s = 2.4 → 3 segments (0-300, 300-600, 600-720)
assert_eq "time segments for 12min video" "3" "$seg_count"
first_seg_title=$(echo "$segments" | jq -r '.[0].title')
assert_contains "time segment has range" "00:00" "$first_seg_title"

echo ""
echo "=== Transcript Segmenting ==="

# Test: segment_transcript splits cleaned text by chapter time ranges
chapters_json=$(extract_chapters "$TEST_DIR/metadata.json")
seg_text=$(segment_transcript "$TEST_DIR/subs.vtt" "$chapters_json")
# Should have 3 segments separated by ---SEGMENT---
seg_parts=$(echo "$seg_text" | grep -c -- '---SEGMENT---' || echo "0")
assert_eq "3 chapters = 2 segment delimiters" "2" "$seg_parts"
# First segment (0-60s) should contain "strangers to love"
first_seg=$(echo "$seg_text" | awk '/---SEGMENT---/{exit} {print}')
assert_contains "first segment has intro text" "strangers to love" "$first_seg"

echo ""
echo "=== Transcript Fidelity ==="

# Test: non-consecutive repeated lines are preserved (choruses, refrains)
# Global dedup would kill these; consecutive-only dedup should keep them
cat > "$TEST_DIR/subs_chorus.vtt" << 'MOCK_VTT'
WEBVTT

00:00:01.000 --> 00:00:05.000
Verse one lyrics here

00:01:00.000 --> 00:01:05.000
Never gonna give you up

00:01:05.000 --> 00:01:10.000
Never gonna let you down

00:02:00.000 --> 00:02:05.000
Verse two different lyrics

00:03:00.000 --> 00:03:05.000
Never gonna give you up

00:03:05.000 --> 00:03:10.000
Never gonna let you down
MOCK_VTT

cat > "$TEST_DIR/metadata_chorus.json" << 'MOCK_META'
{"id":"chorus1","title":"Chorus Test","channel":"Test","duration":240,"upload_date":"20260101","description":"Test","chapters":null,"subtitles":{"en":[{"ext":"vtt"}]},"automatic_captions":{}}
MOCK_META

chorus_chapters=$(extract_chapters "$TEST_DIR/metadata_chorus.json")
chorus_seg=$(segment_transcript "$TEST_DIR/subs_chorus.vtt" "$chorus_chapters")
chorus_count=$(echo "$chorus_seg" | grep -c 'Never gonna give you up' || echo "0")
assert_eq "chorus line preserved both times" "2" "$chorus_count"

echo ""
echo "=== YAML Safety ==="

# Test: title with colon produces valid YAML (quoted)
cat > "$TEST_DIR/metadata_colon_title.json" << 'MOCK_META'
{"id":"colon1","title":"Part 1: The Beginning","channel":"Test: Channel","duration":60,"upload_date":"20260101","description":"Test","chapters":null,"subtitles":{"en":[{"ext":"vtt"}]},"automatic_captions":{}}
MOCK_META
colon_artifact=$(build_artifact "$TEST_DIR/metadata_colon_title.json" "$TEST_DIR/subs.vtt" "official")
assert_contains "colon title is quoted" '"Part 1: The Beginning"' "$colon_artifact"
assert_contains "colon channel is quoted" '"Test: Channel"' "$colon_artifact"

echo ""
echo "=== Canonical Artifact ==="

# Test: build_artifact produces correct frontmatter
artifact=$(build_artifact "$TEST_DIR/metadata.json" "$TEST_DIR/subs.vtt" "official")
assert_contains "frontmatter has schema_version" "schema_version: 1" "$artifact"
assert_contains "frontmatter has artifact_type" "artifact_type: youtube_canonical" "$artifact"
assert_contains "frontmatter has video_id" "video_id: dQw4w9WgXcQ" "$artifact"
assert_contains "frontmatter has title" "title: Rick Astley" "$artifact"
assert_contains "frontmatter has channel" "channel: Rick Astley" "$artifact"
assert_contains "frontmatter has duration" "duration_seconds: 212" "$artifact"
assert_contains "frontmatter has upload_date" "upload_date: 2009-10-25" "$artifact"
assert_contains "frontmatter has transcript_source" "transcript_source: official" "$artifact"
assert_contains "frontmatter has chapters count" "chapters: 3" "$artifact"

# Test: artifact has chapter sections
assert_contains "has chapter heading" "## Intro" "$artifact"
assert_contains "has transcript text" "strangers to love" "$artifact"

# Test: artifact has source description
assert_contains "has source description" "Source Description" "$artifact"

# Test: build_artifact works without chapters (time segments)
artifact2=$(build_artifact "$TEST_DIR/metadata_no_chapters.json" "$TEST_DIR/subs_long.vtt" "official")
assert_contains "no-chapters has time segment" "00:00" "$artifact2"
assert_contains "no-chapters has transcript" "event sourcing" "$artifact2"

echo ""
echo "=== Atomic Write ==="

# Test: write_youtube_artifact creates file
yt_out="$TEST_DIR/yt_output"
write_youtube_artifact "test content" "$yt_out/test123.md"
TOTAL=$((TOTAL + 1))
if [[ -f "$yt_out/test123.md" ]]; then
    echo "  PASS: artifact file created"; PASS=$((PASS + 1))
else
    echo "  FAIL: artifact not created"; FAIL=$((FAIL + 1))
fi
yt_content=$(cat "$yt_out/test123.md")
assert_contains "artifact has content" "test content" "$yt_content"
rm -rf "$yt_out"

echo ""
echo "=== Main Pipeline ==="

# Create mock yt-dlp
MOCK_YTDLP_DIR=$(mktemp -d)
cat > "$MOCK_YTDLP_DIR/yt-dlp" << MOCKSCRIPT
#!/bin/bash
# Detect which mode yt-dlp is being called in
if echo "\$@" | grep -q -- '--dump-json'; then
    cat "$TEST_DIR/metadata.json"
elif echo "\$@" | grep -q -- '--write-subs\|--write-auto-subs'; then
    # Find the -P argument for output directory
    outdir=""
    prev=""
    for arg in "\$@"; do
        if [[ "\$prev" == "-P" ]]; then outdir="\$arg"; fi
        prev="\$arg"
    done
    [[ -z "\$outdir" ]] && outdir="/tmp"
    cp "$TEST_DIR/subs.vtt" "\$outdir/dQw4w9WgXcQ.en.vtt" 2>/dev/null || true
fi
MOCKSCRIPT
chmod +x "$MOCK_YTDLP_DIR/yt-dlp"

# Test: dry-run outputs artifact to stdout
output_dir="$TEST_DIR/dry_output"
output=$(PATH="$MOCK_YTDLP_DIR:$PATH" YOUTUBE_OUTPUT_DIR="$output_dir" DRY_RUN=true \
    bash "$SCRIPT" "https://youtube.com/watch?v=dQw4w9WgXcQ" --dry-run 2>&1)
assert_contains "dry-run shows DRY-RUN" "DRY-RUN" "$output"
assert_contains "dry-run has frontmatter" "schema_version" "$output"
assert_contains "dry-run has video_id" "dQw4w9WgXcQ" "$output"

# Test: dry-run does NOT write artifact
TOTAL=$((TOTAL + 1))
if [[ ! -d "$output_dir" ]] || [[ $(find "$output_dir" -name '*.md' 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "  PASS: dry-run writes no artifact"; PASS=$((PASS + 1))
else
    echo "  FAIL: dry-run wrote artifact"; FAIL=$((FAIL + 1))
fi

# Test: non-dry-run writes artifact at {video-id}.md
output_dir2="$TEST_DIR/real_output"
PATH="$MOCK_YTDLP_DIR:$PATH" YOUTUBE_OUTPUT_DIR="$output_dir2" \
    bash "$SCRIPT" "https://youtube.com/watch?v=dQw4w9WgXcQ" 2>/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$output_dir2/dQw4w9WgXcQ.md" ]]; then
    echo "  PASS: artifact created at video-id.md"; PASS=$((PASS + 1))
else
    echo "  FAIL: no artifact at $output_dir2/dQw4w9WgXcQ.md"; FAIL=$((FAIL + 1))
fi
art=$(cat "$output_dir2/dQw4w9WgXcQ.md" 2>/dev/null || echo "")
assert_contains "artifact has transcript" "strangers to love" "$art"
assert_contains "artifact has frontmatter" "youtube_canonical" "$art"

# Test: no subs → fail with message
cat > "$MOCK_YTDLP_DIR/yt-dlp" << MOCKSCRIPT_NOSUB
#!/bin/bash
if echo "\$@" | grep -q -- '--dump-json'; then
    cat "$TEST_DIR/metadata_no_subs.json"
fi
MOCKSCRIPT_NOSUB
chmod +x "$MOCK_YTDLP_DIR/yt-dlp"

nosub_output=$(PATH="$MOCK_YTDLP_DIR:$PATH" YOUTUBE_OUTPUT_DIR="$TEST_DIR/nosub_out" \
    bash "$SCRIPT" "https://youtube.com/watch?v=nosubs999" 2>&1) || true
assert_contains "no subs error" "No subtitles" "$nosub_output"

# Test: idempotency — run twice, second overwrites
# Restore working mock first
cat > "$MOCK_YTDLP_DIR/yt-dlp" << MOCKSCRIPT_OK
#!/bin/bash
if echo "\$@" | grep -q -- '--dump-json'; then
    cat "$TEST_DIR/metadata.json"
elif echo "\$@" | grep -q -- '--write-subs\|--write-auto-subs'; then
    outdir=""
    prev=""
    for arg in "\$@"; do
        if [[ "\$prev" == "-P" ]]; then outdir="\$arg"; fi
        prev="\$arg"
    done
    [[ -z "\$outdir" ]] && outdir="/tmp"
    cp "$TEST_DIR/subs.vtt" "\$outdir/dQw4w9WgXcQ.en.vtt" 2>/dev/null || true
fi
MOCKSCRIPT_OK
chmod +x "$MOCK_YTDLP_DIR/yt-dlp"

PATH="$MOCK_YTDLP_DIR:$PATH" YOUTUBE_OUTPUT_DIR="$output_dir2" \
    bash "$SCRIPT" "https://youtube.com/watch?v=dQw4w9WgXcQ" 2>/dev/null
TOTAL=$((TOTAL + 1))
if [[ -f "$output_dir2/dQw4w9WgXcQ.md" ]]; then
    echo "  PASS: idempotent overwrite works"; PASS=$((PASS + 1))
else
    echo "  FAIL: idempotent overwrite failed"; FAIL=$((FAIL + 1))
fi

rm -rf "$MOCK_YTDLP_DIR" "$output_dir" "$output_dir2"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
