# Store marketing art

Framed store screenshots and the App Store universal creative asset, rendered from the
raw captures in `store/app-store/screenshots/` and `store/google-play/media/en-US/images/`.

    python3 store/marketing/render.py all        # framed screenshots -> out/<set>/
    chrome --headless=new --window-size=5244,2950 --allow-file-access-from-files \
      --screenshot=out.png store/marketing/universal.html   # header + search results asset

`shot.html` is the screenshot template, `render.py` holds the slide order and copy.
