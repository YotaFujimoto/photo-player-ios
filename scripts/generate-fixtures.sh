#!/bin/bash
set -euo pipefail

# CI-only synthetic media. Software encoding avoids unavailable VM video hardware.
mkdir -p build/fixtures build/fixture-source
if ! command -v ffmpeg >/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg
fi
ffmpeg -version > build/fixtures.log
ffmpeg -hide_banner -loglevel warning -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=10' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
  -t 30 -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -threads 2 \
  -c:a aac -b:a 64k -metadata creation_time=2024-02-01T00:00:00Z -movflags +faststart build/fixture-source/synthetic-video.mov \
  2>&1 | tee -a build/fixtures.log
# Make the UI fixture's decoding workload explicit instead of inheriting x264's
# default GOP at only 10 fps. Keep inter-frame H.264 and the original AAC audio;
# 15s and fractional bar targets still require sample-accurate non-keyframe seeks.
# This is a UI-test input bound, not a change to production seeking or a claim
# about arbitrary media. Retain and measure the original encoding for comparison.
ffmpeg -hide_banner -loglevel warning -y -i build/fixture-source/synthetic-video.mov \
  -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -threads 2 \
  -g 20 -keyint_min 20 -sc_threshold 0 -c:a copy \
  -metadata creation_time=2024-02-01T00:00:00Z -movflags +faststart \
  build/fixtures/synthetic-video.mov 2>&1 | tee -a build/fixtures.log
# Keep the original elementary streams for a separate regression pass after the
# twelve-card UI suite. Only the date changes so Photos sorts this clip first.
ffmpeg -hide_banner -loglevel warning -y -i build/fixture-source/synthetic-video.mov \
  -map 0 -c copy -metadata creation_time=2025-02-01T00:00:00Z -movflags +faststart \
  build/fixture-source/long-gop-regression.mov 2>&1 | tee -a build/fixtures.log
python3 - <<'PY' | tee -a build/fixtures.log
import json, pathlib, subprocess
report = {}
for label, relative in [('original', 'fixture-source/synthetic-video.mov'),
                        ('ui', 'fixtures/synthetic-video.mov'),
                        ('regression', 'fixture-source/long-gop-regression.mov')]:
    path = pathlib.Path('build') / relative
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error',
        '-select_streams', 'v:0', '-show_frames', '-show_entries',
        'frame=key_frame,best_effort_timestamp_time', '-of', 'json', str(path)]))
    frames = info['frames']
    keys = [float(f['best_effort_timestamp_time']) for f in frames if f['key_frame']]
    report[label] = {'frame_count': len(frames), 'keyframe_times': keys,
                     'max_keyframe_gap': max(b-a for a,b in zip(keys, keys[1:]))}
assert report['ui']['frame_count'] == report['original']['frame_count'] == 300, report
assert 0 < report['ui']['max_keyframe_gap'] <= 2.001, report
assert len(report['ui']['keyframe_times']) < 300, 'Keep inter-frame decoding coverage'
assert 15.0 not in report['ui']['keyframe_times'], 'Paused 15s test must remain off-keyframe'
assert report['original'] == report['regression'], 'Keep the original GOP/frame sequence'
def packet_hashes(path):
    data = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_packets',
        '-show_data_hash', 'sha256', '-show_entries', 'packet=stream_index,data_hash',
        '-of', 'json', str(path)]))
    return [[p['data_hash'] for p in data['packets'] if p['stream_index'] == stream] for stream in [0, 1]]
assert packet_hashes('build/fixture-source/synthetic-video.mov') == packet_hashes('build/fixture-source/long-gop-regression.mov'), 'Original video/audio packets must be unchanged'
report['original_packets_preserved'] = True
pathlib.Path('build/fixture-seek-info.json').write_text(json.dumps(report, indent=2))
print('Synthetic seek workload:', report)
PY
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
