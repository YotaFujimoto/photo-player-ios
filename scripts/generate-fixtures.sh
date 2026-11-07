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
  -c:a aac -b:a 64k -metadata creation_time=2024-02-01T00:00:00Z -movflags +faststart build/fixtures/synthetic-video.mov \
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

# Unique dimensions + solid colors provide an independent visible-image/asset oracle.
# Together with the 30-second landscape clip: 12 videos, 6 rows on the pinned iPhone.
sizes=(180x320 202x202 340x180 182x340 204x204 360x180 184x360 206x206 380x180 186x380 208x208)
colors=(red lime blue yellow magenta cyan orange purple teal pink gray)
for index in "${!sizes[@]}"; do
  day=$(printf '%02d' "$((31 - index))")
  ffmpeg -hide_banner -loglevel warning -y \
    -f lavfi -i "color=c=${colors[$index]}:s=${sizes[$index]}:r=10" \
    -t 3 -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p -threads 2 \
    -metadata "creation_time=2024-01-${day}T00:00:00Z" -movflags +faststart \
    "build/fixtures/selection-${day}.mov" 2>&1 | tee -a build/fixtures.log
done
python3 - <<'PY' | tee -a build/fixtures.log
import json, pathlib, subprocess
items = []
for path in sorted(pathlib.Path('build/fixtures').glob('selection-*.mov')):
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
        'format=duration:stream=codec_name,width,height', '-of', 'json', str(path)]))
    assert len(info['streams']) == 1 and info['streams'][0]['codec_name'] == 'h264', info
    assert 2.9 <= float(info['format']['duration']) <= 3.1, info
    items.append(info['streams'][0])
assert len(items) == 11
assert all(any((s['width'] > s['height']) if shape == 'wide' else
               (s['width'] < s['height']) if shape == 'tall' else
               (s['width'] == s['height']) for s in items) for shape in ['wide', 'tall', 'square'])
print('Verified eleven additional mixed-aspect selection fixtures:', items)
PY
