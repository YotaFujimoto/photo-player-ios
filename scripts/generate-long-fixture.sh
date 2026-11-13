#!/bin/bash
set -euo pipefail
# Encode a small synthetic segment, then remux continuous timestamps for a real
# two-hour media file. No private media, UI-only duration override or real-time play.
mkdir -p build/fixture-source
ffmpeg -hide_banner -loglevel warning -y -f lavfi -i 'testsrc2=size=96x64:rate=10' \
  -f lavfi -i 'sine=frequency=600:sample_rate=24000' -t 8 \
  -c:v libx264 -preset ultrafast -crf 30 -g 10 -keyint_min 10 -sc_threshold 0 -threads 2 \
  -pix_fmt yuv420p -c:a aac -b:a 24k build/fixture-source/long-segment.mov
# Loop the video independently: AAC packet padding must not lengthen each
# eight-second video cycle and leave timestamp gaps between segments.
ffmpeg -hide_banner -loglevel warning -y -i build/fixture-source/long-segment.mov \
  -map 0:v:0 -c copy build/fixture-source/long-video.mov
ffmpeg -hide_banner -loglevel warning -y -stream_loop 899 -i build/fixture-source/long-video.mov \
  -stream_loop -1 -i build/fixture-source/long-segment.mov -map 0:v:0 -map 1:a:0 \
  -t 7200 -c copy -metadata creation_time=2025-03-01T00:00:00Z -movflags +faststart \
  build/fixture-source/two-hour.mov
ffprobe -v error -show_entries format=duration,size:stream=codec_name,duration,nb_frames \
  -of json build/fixture-source/two-hour.mov | tee build/long-fixture-info.log
python3 - <<'PY'
import json
with open('build/long-fixture-info.log') as f: info=json.load(f)
assert abs(float(info['format']['duration'])-7200)<0.2, info
assert any(s['codec_name']=='h264' and int(s['nb_frames'])>=71990 for s in info['streams']), info
assert any(s['codec_name']=='aac' for s in info['streams']), info
PY
