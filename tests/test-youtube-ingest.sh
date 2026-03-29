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

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
