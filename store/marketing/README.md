# Store marketing art

Framed store screenshots and the App Store universal creative asset, rendered from the
raw captures in `store/app-store/screenshots/` and `store/google-play/media/en-US/images/`.

    python3 store/marketing/render.py all        # framed screenshots -> out/<set>/
    chrome --headless=new --window-size=5244,2950 --allow-file-access-from-files \
      --screenshot=out.png store/marketing/universal.html   # header + search results asset

`shot.html` is the screenshot template, `render.py` holds the slide order and copy.

Captures come from the iOS simulators during service, with the status bar set to 9:41 and a
full battery (`xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging
--batteryLevel 100 --cellularBars 4 --wifiBars 3`). Saved trips on the Plan slides were made in
the app itself (plan a trip, then Save trip). `06-avalon-mall-1600` is the dark-mode capture.

The Android sets render from `clean/` (the same files sit in `google-play/media/en-US/images/`).
From 1.5.0 they are derived from the simulator run, no Android device needed: phones are the
iPhone 6.9" captures scaled to 1344 wide, the iOS status bar cropped off (y 160, 2622 tall) and a
blurred 66 px band added on top where Android's status bar sits; 7" and 10" tablets are the
iPad 13" captures with the status bar cropped off, scaled to 1200 and 1600 wide. Until 1.4.1 they
were emulator captures with the status bar removed by ffmpeg `delogo`. The iPhone and iPad status
bars clear their corners and stay as captured.

Colours follow the 1.5 brand: blue `#1272C9`, ink `#16181C` frames.
