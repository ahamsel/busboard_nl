"""Render the store marketing screenshots (store/marketing/shot.html) with headless Chrome.

  python3 store/marketing/render.py [iphone|iphone65|ipad|android|tab7|tab10|all]

Output: store/marketing/out/<set>/NN-name.png (no alpha).
"""
import os, subprocess, sys, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.dirname(HERE)
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

# Order: the strongest feature first. Eight slides, Google Play's limit for phone screenshots.
SLIDES = [
    ('01-plan', '07-plan-a-trip', 'blue', 'Plan a trip,<br>any minute', 'Leave now, leave by or arrive by,<br>with live bus times'),
    ('02-follow', '03-follow-a-bus', 'blue', 'Follow your bus<br>to your stop', 'See the stops left, the minutes away,<br>and when it arrives'),
    ('03-arrival-alert', '09-arrival-alert', 'blue', 'Know when<br>to head out', 'Get a heads-up when your bus is<br>3, 5 or 10 minutes away'),
    ('04-arrivals', '01-mun-centre-1150', 'blue', 'Live arrivals<br>at your stop', 'Metrobus predictions next to the schedule,<br>early or late at a glance'),
    ('05-trip-detail', '08-trip-detail', 'blue', 'Save the trips<br>you take often', 'Your next buses, one tap away,<br>worked out on your phone'),
    ('06-map', '02-live-map', 'blue', 'Every bus,<br>live on the map', 'Route colours and smooth movement<br>between position updates'),
    ('07-nearby', '05-nearby-stops', 'blue', 'Stops near you,<br>in a tap', 'Nearby stops with their routes,<br>or enter any stop number'),
    ('08-service-alerts', '04-service-alerts', 'blue', 'Detours and alerts<br>for your routes', 'Official Metrobus service alerts,<br>matched to your stop'),
]

# The 1.2.0 set, still used by the Android tablets (no 1.3/1.4 captures for them yet).
TABLET_SLIDES = [
    ('01-follow', '03-follow-a-bus', 'blue', 'Follow your bus<br>to your stop', 'See the stops left, the minutes away,<br>and when it arrives'),
    ('02-arrivals', '01-mun-centre-1150', 'blue', 'Live arrivals<br>at your stop', 'Metrobus predictions next to the schedule,<br>early or late at a glance'),
    ('03-map', '02-live-map', 'blue', 'Every bus,<br>live on the map', 'Route colours and smooth movement<br>between position updates'),
    ('04-nearby', '05-nearby-stops', 'blue', 'Stops near you,<br>in a tap', 'Nearby stops with their routes,<br>or enter any stop number'),
    ('05-alerts', '04-service-alerts', 'blue', 'Detours and alerts<br>for your routes', 'Official Metrobus service alerts,<br>matched to your stop'),
    ('06-dark', '06-avalon-mall-1600', 'navy', 'Easy on the eyes,<br>day or night', 'Light and dark themes, larger text<br>and screen-reader support'),
]

SETS = {
    # name: (device, width, height, source dir, slides)
    'iphone': ('iphone', 1320, 2868, 'app-store/screenshots/APP_IPHONE_69', SLIDES),
    # 6.5" renders from the 6.9" captures at the 6.5" size.
    'iphone65': ('iphone', 1284, 2778, 'app-store/screenshots/APP_IPHONE_69', SLIDES),
    'ipad': ('ipad', 2064, 2752, 'app-store/screenshots/APP_IPAD_PRO_3GEN_129', SLIDES),
    'android': ('android', 1080, 2160, 'marketing/clean/phoneScreenshots', SLIDES),
    'tab7': ('tablet', 1200, 1920, 'marketing/clean/sevenInchScreenshots', TABLET_SLIDES),
    'tab10': ('tablet', 1600, 2560, 'marketing/clean/tenInchScreenshots', TABLET_SLIDES),
}

def render(name):
    device, w, h, src, slides = SETS[name]
    out = os.path.join(HERE, 'out', name)
    os.makedirs(out, exist_ok=True)
    keep = {slug + '.png' for slug, *_ in slides}
    for f in os.listdir(out):  # drop slides that left the order
        if f.endswith('.png') and f not in keep:
            os.remove(os.path.join(out, f))
    for slug, shot, bg, title, sub in slides:
        img = os.path.join(STORE, src, shot + '.png')
        qs = urllib.parse.urlencode({'w': w, 'h': h, 'device': device, 'bg': bg, 't': title, 'sub': sub, 'img': 'file://' + img})
        tmp = os.path.join(out, slug + '.rgba.png')
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
                        '--force-device-scale-factor=1', f'--window-size={w},{h}', '--virtual-time-budget=4000',
                        f'--screenshot={tmp}', 'file://' + os.path.join(HERE, 'shot.html') + '?' + qs],
                       check=True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', tmp, '-pix_fmt', 'rgb24', os.path.join(out, slug + '.png')], check=True)
        os.remove(tmp)
        print(name, slug)

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    for n in (SETS if which == 'all' else [which]):
        render(n)
