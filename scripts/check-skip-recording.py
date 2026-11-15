"""Check the actual 0.28s SF-arrow presentation without blocking its UI thread.
Markers identify three replacement pulses, Reduce Motion, and removal. No test
changes the product animation clock or slows down its turn for easier capture.
"""
import json, math, os, re, subprocess, sys
video, log = sys.argv[1:]
width, height = map(int, re.findall(r"CI_SKIP_CANVAS (\d+) (\d+)", open(log).read())[-1])
times = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
    "-show_frames", "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", video]))["frames"]
process = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-vf",
    f"scale={width}:{height},crop=140:180:20:120", "-enc_time_base", "demux", "-fps_mode", "passthrough",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
colors = [(0,255,0), (0,255,255), (255,0,255), (255,255,0), (0,0,255)]
groups = [[] for _ in colors]
count = 0
while True:
    raw = process.stdout.read(140*180*3)
    if not raw: break
    if len(raw) != 140*180*3: raise SystemExit("Incomplete recorded screen frame")
    def marker_matches(color):
        return all(abs(raw[(y*140+x)*3+c]-color[c]) < 40
                   for y in [4, 10] for x in [4, 10] for c in range(3))
    for group, color in enumerate(colors):
        if marker_matches(color):
            picture = [sum(raw[(y*140+x)*3:(y*140+x)*3+3])/3
                       for y in range(60,180) for x in range(20,140)]
            groups[group].append((float(times[count]["best_effort_timestamp_time"]), picture, count))
            break
    count += 1
if process.wait() or count != len(times): raise SystemExit("Screen decoder/timestamp mismatch")
def difference(a,b): return sum(abs(x-y) for x,y in zip(a,b))/len(a)
def core(p): return [p[y*120+x] for y in range(38,82) for x in range(38,82) if math.hypot(x-60,y-60)<22]
def profile(p):
    return [sum(p[round(60+r*math.sin(d*math.pi/180))*120+round(60+r*math.cos(d*math.pi/180))]
                for r in [40,43,46]) for d in range(360)]
def shift(a,b):
    return min(range(-160,161), key=lambda s: sum(abs(a[d]-b[(d+s)%360]) for d in range(360)))
report = {"screenFrames": count, "pulses": []}
failures = []
for index, frames in enumerate(groups):
    if len(frames)<3:
        failures.append(f"Marker {index+1}: insufficient actual screen frames ({len(frames)})")
        continue
    start = frames[0][0]
    if index < 4:
        if sum(core(frames[0][1])) < 1000: failures.append(f"Marker {index+1}: numeral not visible")
        drift = max(difference(core(frames[0][1]), core(f[1])) for f in frames)
        # H.264 recording can perturb even unchanged edges. Three luma levels
        # allow codec noise, not the large change from moving/rotating the 10.
        if drift > 3: failures.append(f"Marker {index+1}: numeral changed ({drift})")
    if index < 3:
        pairs = [(a,b) for a,b in zip(frames,frames[1:]) if b[0]-start<0.28 and b[0]-a[0]<0.14]
        shifts = [shift(profile(a[1]),profile(b[1])) for a,b in pairs]
        forward = index != 1
        if not any(s>5 if forward else s < -5 for s in shifts): failures.append(f"Pulse {index+1}: no observed turn {shifts}")
        if any(s < -5 if forward else s>5 for s in shifts): failures.append(f"Pulse {index+1}: reversed turn {shifts}")
        settled = [f for f in frames if f[0]-start > 0.32]
        if index != 1 and len(settled)<2: failures.append(f"Pulse {index+1}: no settled frames")
        if settled and any(difference(f[1],settled[-1][1])>3 for f in settled): failures.append(f"Pulse {index+1}: queued/late turn")
        report["pulses"].append({"pulse":index+1,"frames":len(frames),"duration":frames[-1][0]-start,"shifts":shifts,"numeralDrift":drift})
    elif index == 3:
        if any(difference(f[1],frames[0][1])>3 for f in frames): failures.append("Reduce Motion changed the arrow")
    elif any(sum(f[1])/len(f[1])>1 for f in frames): failures.append("Removal left a visible arrow")
report["failures"] = failures
print("CI_SKIP_SCREEN", json.dumps(report))
with open(video+".json","w") as stream: json.dump(report,stream,indent=2)
selected = sorted(set(f[2] for frames in groups for f in frames[:3]))
if selected:
    selection = "+".join(f"eq(n\\,{i})" for i in selected)
    subprocess.run(["ffmpeg","-v","error","-i",video,"-vf",f"select={selection},scale={width}:{height},crop=120:120:40:180",
                    "-fps_mode","vfr","-frames:v",str(len(selected)),os.path.join(os.path.dirname(video),"skip-screen-%02d.png")],check=True)
if failures: raise SystemExit("Actual arrow presentation check failed")
