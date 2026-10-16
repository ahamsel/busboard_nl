# Store marketing art

Framed store screenshots and the App Store universal creative asset, rendered from the
raw captures in `store/app-store/screenshots/` and `store/google-play/media/en-US/images/`.

    python3 store/marketing/render.py all        # framed screenshots -> out/<set>/
    chrome --headless=new --window-size=5244,2950 --allow-file-access-from-files \
      --screenshot=out.png store/marketing/universal.html   # header + search results asset

`shot.html` is the screenshot template, `render.py` holds the slide order and copy.

The Android sets render from `clean/`: Play-sized captures with nothing under the rounded
corners or the punch-hole camera of the frame. From 1.5.0 they come from the iPhone 6.9" simulator
run (no Android device needed): scaled to 1344 wide, the iOS status bar cropped off, and a blurred
66 px band added on top where Android's status bar sits. The 7" and 10" tablet captures are the
iPad 13" captures cropped to 10:16 (the Board's centred column, or the Map's side panel and map)
and scaled. Until 1.4.1 they were emulator captures with the status bar removed by ffmpeg `delogo`.
The iPhone and iPad status bars clear their corners and stay as captured.

Colours follow the 1.5 brand: blue `#1272C9`, ink `#16181C` frames, and the night background
`#121316` for the dark-mode slide (`bg` = `night` in `render.py`).
