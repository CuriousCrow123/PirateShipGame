# docs/media/

Hero media for the repo README lives here.

## Status

- [x] `hero.gif` — middle 10s slice of a 36s gameplay capture,
  480×270, 12 fps, 128-color palette, 8.0 MB. Embedded in the root
  README at native width.
- [ ] `hero.png` — static screenshot fallback. **Not yet captured.**

The root [README.md](../../README.md) embeds `docs/media/hero.gif` via
an `<img width="480">` tag (native 1:1 — no browser rescale).

## Capture recipe

1. Launch the game in windowed mode at 1280×720.
2. Record the gameplay segment you want (cannons firing, mine
   explosion, water displacement visible).
3. Two-pass palette encode. Use `-ss` / `-t` to trim to the best
   slice (the water shader dirties most pixels every frame, so the
   full clip rarely fits ≤8 MB at 480p — trim rather than downsize):

   ```bash
   ffmpeg -ss 13 -t 10 -i input.mov \
     -vf "fps=12,scale=480:-1:flags=lanczos,palettegen=max_colors=128" \
     -update 1 -frames:v 1 palette.png

   ffmpeg -ss 13 -t 10 -i input.mov -i palette.png \
     -lavfi "fps=12,scale=480:-1:flags=lanczos [x]; \
             [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
     hero.gif
   ```

4. File-size levers, in order of impact: **duration** (linear),
   **width** (quadratic), **fps** (linear), **palette colors**
   (modest). At 480p/12fps on this game, budget roughly **~0.8 MB
   per second** — so a 10-second slice lands near 8 MB.
5. Commit to `docs/media/hero.gif`.

**Target**: ≤8 MB for fast README loading; GitHub's hard cap for
embedded images is 10 MB.

**Visibility flip gate**: real hero media must exist before the
repository is flipped from private to public.
