"""Slice a capture_timetrack_snapshots.dart capture into a replay fixture.

Keeps the frames from START to START + N minutes after the first frame, every
vehicle (or --vehicles), and only the GTFS rows those vehicles' trips need.
calendar.txt and calendar_dates.txt are copied when the feed has them.
Metrobus open data.

  python3 tool/build_replay_fixture.py CAPTURE.json GTFS_DIR OUT_DIR [--start 0] [--minutes 10] [--vehicles 2443,2573]
"""
import argparse, csv, json, os
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument('capture'); ap.add_argument('gtfs'); ap.add_argument('out')
ap.add_argument('--start', type=float, default=0, help='minutes from the first frame to start at')
ap.add_argument('--minutes', type=float, default=10)
ap.add_argument('--vehicles', default='')
a = ap.parse_args()

with open(a.capture) as f:
    d = json.load(f)
want = set(filter(None, a.vehicles.split(',')))
t0 = datetime.fromisoformat(d['frames'][0]['fetch_time'].replace('Z', '+00:00'))
begin = t0 + timedelta(minutes=a.start)
end = begin + timedelta(minutes=a.minutes)
frames, trips = [], set()
for f in d['frames']:
    t = datetime.fromisoformat(f['fetch_time'].replace('Z', '+00:00'))
    if t < begin:
        continue
    if t > end:
        break
    f['vehicles'] = [v for v in f['vehicles'] if not want or v['vehicle'] in want]
    trips |= {v['gtfsTripId'] for v in f['vehicles'] if v.get('gtfsTripId')}
    frames.append(f)
if not frames:
    raise SystemExit('no frames in that window')
d['frames'] = frames
note = f"Metrobus open data. {a.minutes:g} min from {frames[0]['fetch_time']}, vehicles: {a.vehicles or 'all'}."
d['note'] = f"{note} {d['note']}" if d.get('note') else note
os.makedirs(f'{a.out}/gtfs', exist_ok=True)
with open(f'{a.out}/capture.json', 'w') as f:
    json.dump(d, f, separators=(',', ':'))

def copy(name, keep, optional=False):
    src = f'{a.gtfs}/{name}'
    if optional and not os.path.exists(src):
        return []
    with open(src, encoding='utf-8-sig') as f:
        r = csv.DictReader(f)
        rows = [x for x in r if keep(x)]
        fields = r.fieldnames
    with open(f'{a.out}/gtfs/{name}', 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    return rows

tr = copy('trips.txt', lambda x: x['trip_id'] in trips)
shapes = {t['shape_id'] for t in tr}; routes = {t['route_id'] for t in tr}; svc = {t['service_id'] for t in tr}
st = copy('stop_times.txt', lambda x: x['trip_id'] in trips)
stops = {s['stop_id'] for s in st}
copy('stops.txt', lambda x: x['stop_id'] in stops)
copy('shapes.txt', lambda x: x['shape_id'] in shapes)
copy('routes.txt', lambda x: x['route_id'] in routes)
copy('calendar.txt', lambda x: x['service_id'] in svc, optional=True)
copy('calendar_dates.txt', lambda x: x['service_id'] in svc, optional=True)
print(len(frames), 'frames', len(trips), 'trips', len(shapes), 'shapes')
