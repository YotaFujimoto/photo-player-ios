#!/bin/bash
set -euo pipefail
mkdir -p build/frame-fixtures
# Large binary blocks identify actual decoded frames independently of timestamps.
pattern="geq=lum='if(lt(Y,32),if(mod(floor(N/pow(2,floor(X/20))),2),235,16),64)':cb=128:cr=128,drawtext=text='%{n}':x=10:y=55:fontsize=24:fontcolor=white"
for rate in 30 30000/1001; do
  label=30
  if [[ "$rate" != 30 ]]; then label=2997; fi
  ffmpeg -hide_banner -loglevel warning -y \
    -f lavfi -i "nullsrc=size=160x96:rate=$rate,$pattern" -frames:v 151 \
    -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -g 30 -threads 2 \
    -metadata creation_time=2026-02-01T00:00:00Z -movflags +faststart \
    "build/frame-fixtures/frames-$label.mov"
done
# A longer copy of the same pixel-number pattern keeps UI setup independent of
# reaching the end while accessibility queries are being processed.
ffmpeg -hide_banner -loglevel warning -y \
  -f lavfi -i "nullsrc=size=160x96:rate=30,$pattern" -frames:v 901 \
  -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -g 30 -threads 2 \
  -metadata creation_time=2026-02-01T00:00:00Z -movflags +faststart build/frame-fixtures/frames-ui.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-30.mov \
  -map 0:v -c copy -metadata:s:v:0 rotate=90 build/frame-fixtures/frames-rotated.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-30.mov \
  -vf "setpts='if(lt(N,45),N,45+(N-45)*2)/(30*TB)'" -fps_mode vfr \
  -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -threads 2 build/frame-fixtures/frames-variable.mov
ffprobe -v error -show_streams -of json build/frame-fixtures/frames-rotated.mov > build/frame-fixtures/rotation.json
python3 - <<'PY'
import json
data=json.load(open('build/frame-fixtures/rotation.json'))
assert abs(data['streams'][0]['side_data_list'][0]['rotation']) == 90
print('Generated frame-number fixtures: 30, 29.97, rotated and variable rate.')
PY
