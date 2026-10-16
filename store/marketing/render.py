"""Render the store marketing screenshots (store/marketing/shot.html) with headless Chrome.

  python3 store/marketing/render.py [iphone|iphone65|ipad|android|tab7|tab10|all]

Output: store/marketing/out/<set>/NN-name.png (no alpha).
"""
import os, subprocess, sys, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.dirname(HERE)
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

# Order: the 1.5 story first (Board, then Map), then the features riders use most. Eight slides,
# Google Play's limit for phone screenshots. Every set uses the same file names in its source dir.
SLIDES = [
    ('01-board', '01-board', 'blue', 'Your stop\'s buses,<br>no map needed', 'The Board tab: live times for your stops,<br>with Follow on every live bus'),
    ('02-map', '02-map', 'blue', 'Every bus,<br>live on the map', 'Where to? and your next bus sit in<br>a slim bar that tucks away as you pan'),
    ('03-stop', '03-stop', 'blue', 'Tap any stop<br>for its next buses', 'Live times and detours for that stop,<br>right on the map'),
    ('04-plan', '04-plan', 'blue', 'Plan a trip,<br>any minute', 'Leave now, leave by or arrive by,<br>with live bus times'),
    ('05-follow', '05-follow', 'blue', 'Follow your bus<br>to your stop', 'See the stops left, the minutes away,<br>and when it arrives'),
    ('06-picker', '06-picker', 'blue', 'Plan for later<br>in a few taps', 'Pick the day and time, or tap<br>In 15 min, In 1 hr and more'),
    ('07-alert', '07-alert', 'blue', 'Know when<br>to head out', 'Get a heads-up when your bus is<br>3, 5 or 10 minutes away'),
    ('08-dark', '08-dark', 'night', 'Easy on the eyes<br>after dark', 'A dark mode for early mornings<br>and late buses'),
]

# Tablets have no slim bar: the map's panel sits beside the map instead.
TABLET_SLIDES = [
    (slug, shot, bg, title, 'Where to? and your stop\'s next buses<br>sit in a panel beside the map') if slug == '02-map'
    else (slug, shot, bg, title, sub)
    for slug, shot, bg, title, sub in SLIDES
]

SETS = {
    # name: (device, width, height, source dir, slides)
    'iphone': ('iphone', 1320, 2868, 'app-store/screenshots/APP_IPHONE_69', SLIDES),
    # 6.5" renders from the 6.9" captures at the 6.5" size.
    'iphone65': ('iphone', 1284, 2778, 'app-store/screenshots/APP_IPHONE_69', SLIDES),
    'ipad': ('ipad', 2064, 2752, 'app-store/screenshots/APP_IPAD_PRO_3GEN_129', TABLET_SLIDES),
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
