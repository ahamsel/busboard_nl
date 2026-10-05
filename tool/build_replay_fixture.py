"""Slice a capture_timetrack_snapshots.dart capture into a replay fixture.

Keeps the first N minutes of frames, every vehicle (or --vehicles), and only
the GTFS rows those vehicles' trips need. Metrobus open data.

  python3 tool/build_replay_fixture.py CAPTURE.json GTFS_DIR OUT_DIR [--minutes 10] [--vehicles 2443,2573]
"""
import argparse, csv, json, os
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument('capture'); ap.add_argument('gtfs'); ap.add_argument('out')
ap.add_argument('--minutes', type=float, default=10)
ap.add_argument('--vehicles', default='')
a = ap.parse_args()

d = json.load(open(a.capture))
want = set(filter(None, a.vehicles.split(',')))
t0 = datetime.fromisoformat(d['frames'][0]['fetch_time'].replace('Z', '+00:00'))
end = t0 + timedelta(minutes=a.minutes)
frames, trips = [], set()
for f in d['frames']:
    if datetime.fromisoformat(f['fetch_time'].replace('Z', '+00:00')) > end:
        break
    f['vehicles'] = [v for v in f['vehicles'] if not want or v['vehicle'] in want]
    trips |= {v['gtfsTripId'] for v in f['vehicles'] if v.get('gtfsTripId')}
    frames.append(f)
d['frames'] = frames
d['note'] = f"Metrobus open data. {a.minutes:g} min from {d['frames'][0]['fetch_time']}, vehicles: {a.vehicles or 'all'}."
os.makedirs(f'{a.out}/gtfs', exist_ok=True)
json.dump(d, open(f'{a.out}/capture.json', 'w'), separators=(',', ':'))

def copy(name, keep):
    with open(f'{a.gtfs}/{name}', encoding='utf-8-sig') as f:
        r = csv.DictReader(f); rows = [x for x in r if keep(x)]
        w = csv.DictWriter(open(f'{a.out}/gtfs/{name}', 'w', newline=''), fieldnames=r.fieldnames)
        w.writeheader(); w.writerows(rows)
    return rows

tr = copy('trips.txt', lambda x: x['trip_id'] in trips)
shapes = {t['shape_id'] for t in tr}; routes = {t['route_id'] for t in tr}; svc = {t['service_id'] for t in tr}
st = copy('stop_times.txt', lambda x: x['trip_id'] in trips)
stops = {s['stop_id'] for s in st}
copy('stops.txt', lambda x: x['stop_id'] in stops)
copy('shapes.txt', lambda x: x['shape_id'] in shapes)
copy('routes.txt', lambda x: x['route_id'] in routes)
copy('calendar.txt', lambda x: x['service_id'] in svc)
copy('calendar_dates.txt', lambda x: x['service_id'] in svc)
print(len(frames), 'frames', len(trips), 'trips', len(shapes), 'shapes')
