# docs/media/

Hero media for the repo README lives here.

## Status

- [ ] `hero.gif` — 3-5 second gameplay loop, ≤8 MB, 480p. **Not yet captured.**
- [ ] `hero.png` — static screenshot fallback. **Not yet captured.**

The root [README.md](../../README.md) embeds `docs/media/hero.gif` (or
`hero.png` if the GIF slot is empty). Until a real capture exists, the
README shows a text placeholder and this directory holds only the note
you are currently reading.

## Capture recipe

1. Launch the game in windowed mode at 1280×720.
2. Record 3-5 seconds mid-wave (cannons firing, mine explosion, water
   displacement visible).
3. For GIF: `ffmpeg -i input.mov -vf "fps=15,scale=480:-1" -c:v gif
   output.gif` then shrink with `gifski --fps 15 --width 480 frames/*.png
   -o hero.gif`.
4. Commit to `docs/media/hero.gif`. Update the root README to remove the
   placeholder notice.

**Visibility flip gate**: real hero media must exist before the
repository is flipped from private to public.
