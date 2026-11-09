"""Cut a demo-tour recording into the Reddit video: framed screen, captions, end card.

  python3 tool/demo_edit_tour.py <recording.mov> <steps.txt> <captions dir> <mask.png> <out.mp4>

<steps.txt> is the run's log: a "REC_START <iso time>" line written when the
recording began, then the "DEMO <iso time> <step>" lines from
integration_test/demo_tour_15_test.dart. Clips are placed against those steps,
so a new take needs no re-timing. <captions dir> holds c1..c6.png (1080×200,
transparent) and end.png (1080×1920).

Clips play at real speed. Clips that follow on
in the recording are joined with a plain cut, so the take reads as one; a jump in
time gets a crossfade.
"""
import datetime as dt
import subprocess
import sys

SRC, LOG, CAP, MASK, OUT = sys.argv[1:6]
OFF = 1.9      # the recording starts about this much before REC_START is logged (60 Hz iPhone 16 sim)
FADE = 0.6     # crossfade between clips that jump in time
END = 3.5      # end card, seconds
CARDS = 6

steps = {}
for line in open(LOG):
    parts = line.split()
    if len(parts) >= 2 and parts[0] == 'REC_START':
        start = dt.datetime.fromisoformat(parts[1])
    elif len(parts) >= 3 and parts[0] == 'DEMO':
        steps.setdefault(parts[2], dt.datetime.fromisoformat(parts[1]))


def at(name, plus=0.0):
    return (steps[name] - start).total_seconds() + plus


clips = [  # (from, to, speed, caption) in log seconds
    (at('overview', 4.0), at('zoom-in'), 1.0, 1),            # every bus, moving
    (at('zoom-in'), at('board-tab', -3.0), 1.0, 1),          # into the busy part of town
    (at('board-tab'), at('open-board', 1.8), 1.0, 2),        # Board tab, MUN Centre
    (at('board-ready', -0.4), at('bell'), 1.0, 2),           # the board, a look down it
    (at('bell'), at('notif-prompt', 2.2), 1.0, 3),           # bell, lead, Set alert, iOS asks
    (at('alert-set', -1.6), at('follow'), 1.0, 3),           # Allow, alert set
    (at('follow', 1.2), at('following', 5.0), 1.0, 4),      # follow it
    (at('see-all', -0.3), at('back-to-bus', 1.5), 1.0, 4),   # all its stops
    (at('alert-due', -2.5), at('alert-due', 6.0), 1.0, 6),   # the banner
    (at('stop-follow', -0.6), at('stop-follow', 2.0), 1.0, 6),  # done following
    (at('plan'), at('show-on-map', -4.0), 1.0, 5),           # planner, journey
    (at('show-on-map', -1.8), at('end', -1.0), 1.0, 5),      # on the map (the test's scroll down to the button is cut)
]

# A gap under 1.5 s is kept, so the clips join without a cut.
joined = [list(clips[0])]
for a, b, sp, c in clips[1:]:
    prev = joined[-1]
    if a - prev[1] < 1.5 and sp == prev[2]:
        if c == prev[3]:
            prev[1] = b
            continue
        a = prev[1]
    joined.append([a, b, sp, c])

# Runs of clips that follow on in the recording; crossfades go between runs.
runs = []
for clip in joined:
    if runs and abs(clip[0] - runs[-1][-1][1]) < 0.05:
        runs[-1].append(clip)
    else:
        runs.append([clip])

f = []
spans = []  # (from, to, caption) in output seconds
t = 0.0
lengths = []
for r, run in enumerate(runs):
    run_start = t
    names = []
    for i, (a, b, sp, c) in enumerate(run):
        n = f"r{r}c{i}"
        f.append(f"[0:v]trim={a + OFF:.3f}:{b + OFF:.3f},setpts=(PTS-STARTPTS)/{sp},fps=30[{n}]")
        names.append(f"[{n}]")
        d = (b - a) / sp
        if spans and spans[-1][2] == c:
            spans[-1] = (spans[-1][0], t + d, c)
        else:
            spans.append((t, t + d, c))
        t += d
    f.append("".join(names) + f"concat=n={len(run)}:v=1:a=0,settb=1/30[run{r}]")
    lengths.append(t - run_start)
    t -= FADE  # the next run starts under this one's fade

last, acc = "run0", lengths[0]
for r in range(1, len(runs)):
    f.append(f"[{last}][run{r}]xfade=transition=fade:duration={FADE}:offset={acc - FADE:.3f}[x{r}]")
    last, acc = f"x{r}", acc + lengths[r] - FADE
main = acc

# Captions that meet under a crossfade hand over at its middle instead of overlapping.
for k in range(len(spans) - 1):
    (a, b, c), (a2, b2, c2) = spans[k], spans[k + 1]
    if a2 < b:
        mid = (a2 + b) / 2
        spans[k], spans[k + 1] = (a, mid, c), (mid, b2, c2)

f.append(f"[{last}]scale=736:1600:flags=lanczos,format=rgba[scr]")
f.append("[1:v]format=gray,scale=736:1600[m];[scr][m]alphamerge[rs]")
f.append(f"color=c=0x1272C9:s=1080x1920:d={main:.3f}:r=30[bg];[bg][rs]overlay=(W-w)/2:250[v0]")
v = "v0"
for k, (a, b, c) in enumerate(spans):
    a, b = max(a, 0.0), min(b, main)
    fa = 0.35
    f.append(f"[{1 + c}:v]format=rgba,fade=t=in:st={a:.3f}:d={fa}:alpha=1,fade=t=out:st={b - fa:.3f}:d={fa}:alpha=1[c{k}]")
    f.append(f"[{v}][c{k}]overlay=0:40:enable='between(t,{a:.3f},{b:.3f})'[v{k + 1}]")
    v = f"v{k + 1}"
f.append(f"[{v}]format=yuv420p,settb=1/30[mainv]")
f.append(f"[{2 + CARDS}:v]scale=1080:1920,fps=30,format=yuv420p,settb=1/30[endv]")
f.append(f"[mainv][endv]xfade=transition=fade:duration=0.8:offset={main - 0.8:.3f}[out]")

inputs = ["-i", SRC, "-loop", "1", "-i", MASK]
for n in range(1, CARDS + 1):
    inputs += ["-loop", "1", "-t", f"{main:.3f}", "-i", f"{CAP}/c{n}.png"]
inputs += ["-loop", "1", "-t", f"{END}", "-i", f"{CAP}/end.png"]
total = main + END - 0.8
cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + [
    "-filter_complex", ";".join(f), "-map", "[out]", "-t", f"{total:.3f}",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-movflags", "+faststart", "-an", OUT]
print("main %.1f s, total %.1f s" % (main, total), [(round(a, 1), round(b, 1), c) for a, b, c in spans])
r = subprocess.run(cmd, capture_output=True, text=True)
print(r.returncode, r.stderr[-1200:])
sys.exit(r.returncode)
