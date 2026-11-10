#!/bin/bash
set -euo pipefail
mkdir -p build/frame-fixtures
# Large binary blocks identify actual decoded frames independently of timestamps.
for rate in 30 30000/1001; do
  label=30
  if [[ "$rate" != 30 ]]; then label=2997; fi
  python3 scripts/numbered_frames.py 151 | ffmpeg -hide_banner -loglevel warning -y \
    -f rawvideo -pixel_format rgb24 -video_size 160x96 -framerate "$rate" -i pipe:0 \
    -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -g 30 -threads 2 \
    -metadata creation_time=2026-02-01T00:00:00Z -movflags +faststart \
    "build/frame-fixtures/frames-$label.mov"
done
# A longer copy of the same pixel-number pattern keeps UI setup independent of
# reaching the end while accessibility queries are being processed.
python3 scripts/numbered_frames.py 901 | ffmpeg -hide_banner -loglevel warning -y \
  -f rawvideo -pixel_format rgb24 -video_size 160x96 -framerate 30 -i pipe:0 \
  -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -g 30 -threads 2 \
  -metadata creation_time=2026-02-01T00:00:00Z -movflags +faststart build/frame-fixtures/frames-ui.mov
ffmpeg -hide_banner -loglevel warning -y -display_rotation:v:0 90 -i build/frame-fixtures/frames-30.mov \
  -map 0:v -c copy build/frame-fixtures/frames-rotated.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-30.mov \
  -c:v libx264 -preset medium -crf 10 -pix_fmt yuv420p -g 30 -bf 2 -threads 2 \
  build/frame-fixtures/frames-reordered.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-30.mov \
  -vf "setpts='if(lt(N,45),N,45+(N-45)*2)/(30*TB)'" -fps_mode vfr \
  -c:v libx264 -preset ultrafast -crf 10 -pix_fmt yuv420p -threads 2 build/frame-fixtures/frames-variable.mov
ffprobe -v error -show_streams -of json build/frame-fixtures/frames-rotated.mov > build/frame-fixtures/rotation.json
# Preserve 29.97 fps with 1/600-second track timestamp quantization.
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-2997.mov \
  -map 0:v -c copy -video_track_timescale 600 build/frame-fixtures/frames-rounded.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-30.mov \
  -c:v libx265 -preset ultrafast -crf 10 -pix_fmt yuv420p10le -tag:v hvc1 \
  -x265-params pools=1:frame-threads=1:log-level=error -threads 2 build/frame-fixtures/frames-hevc.mov
for transfer in hlg pq; do
  tag=arib-std-b67
  hdr_metadata=''
  if [[ "$transfer" == pq ]]; then
    tag=smpte2084
    # BT.2020 / D65 mastering display, 1000 nit peak. The synthetic pattern's
    # maximum average frame luminance is 438.1 nits (rounded upward).
    hdr_metadata=':master-display=G(8500,39850)B(6550,2300)R(35400,14600)WP(15635,16450)L(10000000,1):max-cll=1000,439'
  fi
  python3 scripts/hdr_frames.py "$transfer" 151 | ffmpeg -hide_banner -loglevel warning -y \
    -f rawvideo -pixel_format yuv444p10le -video_size 160x96 -framerate 30 \
    -color_primaries bt2020 -color_trc "$tag" -colorspace bt2020nc -color_range tv -i pipe:0 \
    -c:v libx265 -preset ultrafast -crf 10 -pix_fmt yuv420p10le -tag:v hvc1 \
    -color_primaries bt2020 -color_trc "$tag" -colorspace bt2020nc -color_range tv \
    -x265-params "pools=1:frame-threads=1:log-level=error:colorprim=bt2020:transfer=$tag:colormatrix=bt2020nc:range=limited$hdr_metadata" \
    -threads 2 "build/frame-fixtures/frames-$transfer.mov"
done
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-hlg.mov \
  -vf "setpts='if(lt(N,45),N,45+(N-45)*2)/(30*TB)'" -fps_mode vfr \
  -c:v libx265 -preset ultrafast -crf 10 -pix_fmt yuv420p10le -tag:v hvc1 \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc -color_range tv \
  -x265-params pools=1:frame-threads=1:log-level=error -threads 2 build/frame-fixtures/frames-hlg-variable.mov
ffmpeg -hide_banner -loglevel warning -y -display_rotation:v:0 90 -i build/frame-fixtures/frames-hlg.mov \
  -map 0:v -c copy build/frame-fixtures/frames-hlg-rotated.mov
ffmpeg -hide_banner -loglevel warning -y -i build/frame-fixtures/frames-hlg-variable.mov \
  -vf scale=320:192 -fps_mode vfr -c:v libx265 -preset ultrafast -crf 10 -pix_fmt yuv420p10le -tag:v hvc1 \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc -color_range tv \
  -x265-params pools=1:frame-threads=1:log-level=error -threads 2 \
  -metadata creation_time=2026-03-01T00:00:00Z build/frame-fixtures/frames-hdr-ui.mov
python3 - <<'PY'
import json, subprocess
data=json.load(open('build/frame-fixtures/rotation.json'))
assert abs(data['streams'][0]['side_data_list'][0]['rotation']) == 90
report={}
for name in ('30','2997','rounded','hevc','hlg','pq','variable','hlg-variable','hdr-ui'):
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_streams','-show_frames','-of','json',f'build/frame-fixtures/frames-{name}.mov']))
    stream=probe['streams'][0]
    times=[float(frame['best_effort_timestamp_time']) for frame in probe['frames']]
    side_data=probe['frames'][0].get('side_data_list',[])
    report[name]={'stream':stream,'times':times,'firstFrameSideData':side_data}
    with open('build/frame-fixtures/fixture-report.json','w') as output: json.dump(report,output,indent=2)
    print(name, {key:stream.get(key) for key in ('codec_name','pix_fmt','color_primaries','color_space','color_transfer')}, flush=True)
    assert len(times)==151 and all(b>a for a,b in zip(times,times[1:])), name
    if name in ('hlg','pq','hlg-variable','hdr-ui'):
        assert stream['codec_name']=='hevc' and stream['pix_fmt']=='yuv420p10le', stream
        assert stream.get('color_primaries')=='bt2020' and stream.get('color_space')=='bt2020nc', stream
        assert stream.get('color_transfer')==('smpte2084' if name=='pq' else 'arib-std-b67'), stream
    if name=='pq':
        metadata=stream.get('side_data_list',[])+side_data
        assert any(d.get('side_data_type')=='Mastering display metadata' for d in metadata), metadata
        assert any(d.get('side_data_type')=='Content light level metadata' and d.get('max_content')==1000 and d.get('max_average')==439 for d in metadata), metadata
assert report['rounded']['stream']['time_base']=='1/600'
for name in ('variable','hlg-variable','hdr-ui'):
    times=report[name]['times']
    assert times[46]-times[45] > (times[1]-times[0])*1.8
with open('build/frame-fixtures/fixture-report.json','w') as output: json.dump(report,output,indent=2)
print('Verified numbered SDR/HEVC/HLG/PQ, rotation, 29.97, rounded timestamps and actual variable cadence.')
PY
