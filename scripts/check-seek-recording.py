"""Inspect the actual simulator presentation, not AVPlayer buffers/callbacks.
Only the synthetic testsrc2 clip is used: it has no entirely black frames.
The green on-screen marker excludes startup and intentional teardown.
"""
import json, os, re, subprocess, sys
video, log = sys.argv[1:]
width, height = map(int, re.findall(r"CI_DISPLAY_CANVAS (\d+) (\d+)", open(log).read())[-1])
filters = f"scale={width}:{height},crop=320:220:20:120,scale=32:22"
process = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-vf", filters,
                            "-enc_time_base", "demux", "-fps_mode", "passthrough",
                            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
count = active = changed = 0
black = []
marked = []
previous = None
while True:
    frame = process.stdout.read(32*22*3)
    if not frame: break
    if len(frame) != 32*22*3: raise SystemExit("Incomplete screen frame")
    count += 1
    def marker_pixel(x, y):
        offset = (y*32+x)*3
        r, g, b = frame[offset:offset+3]
        return g > 130 and r < 40 and b < 40
    # Check the marker's interior area, not one green pixel that could occur
    # in a Home-screen icon after teardown. Avoid its resampled outer edge.
    if all(marker_pixel(x, y) for x in [0, 1] for y in [0, 1]):
        active += 1
        marked.append(count)
        picture = frame[32*4*3:]
        if sum(picture)/len(picture) < 10: black.append(count)
        if previous and sum(abs(a-b) for a,b in zip(picture, previous))/len(picture) > 4: changed += 1
        previous = picture
status = process.wait()
report = dict(screenFrames=count, markedFrames=active, changedFrames=changed, blackFrames=black)
print("CI_SEEK_SCREEN", json.dumps(report))
with open(video + ".json", "w") as stream: json.dump(report, stream, indent=2)
if marked:
    selected = sorted(set([marked[0], marked[len(marked)//3], marked[2*len(marked)//3], marked[-1]] + black[:2]))
    selection = "+".join(f"eq(n\\,{index-1})" for index in selected)
    subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vf", f"select={selection},scale={width}:{height}",
                    "-fps_mode", "vfr", "-frames:v", str(len(selected)),
                    os.path.join(os.path.dirname(video), "seek-screen-%02d.png")], check=True)
if status or active < 30 or changed < 8 or black:
    raise SystemExit("Actual screen continuity/change check failed")
