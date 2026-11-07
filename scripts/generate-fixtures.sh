#!/bin/bash
set -euo pipefail

# CI-only synthetic media. Software encoding avoids unavailable VM video hardware.
mkdir -p build/fixtures
if ! command -v ffmpeg >/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg
fi
ffmpeg -version > build/fixtures.log
ffmpeg -hide_banner -loglevel warning -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=10' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
  -t 30 -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -threads 2 \
  -c:a aac -b:a 64k -movflags +faststart build/fixtures/synthetic-video.mov \
  2>&1 | tee -a build/fixtures.log
ffmpeg -hide_banner -loglevel warning -y -i build/fixtures/synthetic-video.mov \
  -frames:v 1 -update 1 build/fixtures/synthetic-still.png 2>&1 | tee -a build/fixtures.log
ffprobe -v error -show_entries format=duration:stream=codec_name,codec_type \
  -of json build/fixtures/synthetic-video.mov > build/fixture-info.json
python3 -c '
import json
with open("build/fixture-info.json") as source:
    info = json.load(source)
assert 29.9 <= float(info["format"]["duration"]) <= 30.1, info
assert {(s["codec_type"], s["codec_name"]) for s in info["streams"]} == {("video", "h264"), ("audio", "aac")}, info
print("Verified 30-second H.264/AAC synthetic video and one still image.")
' | tee -a build/fixtures.log
