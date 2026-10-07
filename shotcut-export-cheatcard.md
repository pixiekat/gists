# Shotcut Export Cheat Card — Conference Talks

_Self-hosted, embedded-on-website conference video. Talking-head + slides._
_Validated on Naelaedra (i7-14700HX, 20 cores / 28 threads) — Linux Mint 22.3._

---

## TL;DR — the two-recipe decision

Pick the recipe by **what's on screen**, not a blanket setting.

| Content type            | Resolution  | Quality | ~Size (50 min) | Why                                        |
|-------------------------|-------------|---------|----------------|--------------------------------------------|
| **Panels / talking head** | 1280×720  | 49%     | ~125–165 MB    | Static speaker + simple bg = cheap to encode; 720p plenty at embed width |
| **Keynote / slide-heavy** | 1920×1080 | 52%     | ~300–350 MB    | Slides, fine print, PiP = more detail worth the pixels |

Both stay well clear of the old ~700 MB monsters. Those weren't huge
*because* they were 1080p — they were huge because they had **no quality
target at all**. 1080p _with_ a CRF target is a totally different animal.

---

## The two levers (keep these separate in your head)

### Resolution = how many pixels
- Biggest lever for **file size**.
- Smallest **perceptual cost** when the display is small (embedded player at column width).
- 720p → 1080p ≈ **2.2× the pixels** ≈ roughly **double the size** at the same quality.
- Standard 16:9 tiers: **720p → 1080p**. Nothing useful sits between them (skip 900p).

### Quality (CRF) = how hard it squeezes the pixels it keeps
- This is the one that **"ruins" things** if pushed too far (blocky shadows, smeared motion, mushy slide text).
- Shotcut shows it as a **Quality %** (higher % = better/bigger).
- Rough mapping: `CRF ≈ 51 × (1 − quality%/100)`

| Quality % | ~CRF | Feel                                      |
|-----------|------|-------------------------------------------|
| ~55%      | 23   | Visually transparent (the usual default)  |
| ~52%      | 24   | Slightly cleaner — used for the keynote    |
| ~49%      | 26   | Great for talking heads, noticeably smaller — used for panels |
| ~45%      | 28   | Still fine for static content, smaller again |

**Rule of thumb:** pay for size with *resolution* (cheap), not *quality* (expensive).

---

## Full export settings (Shotcut Export panel → Advanced)

### Codec tab
- **Format:** MP4
- **Codec:** `libx264` (software) — _smallest files at a given quality_
- **Rate control:** Quality-based VBR (this is CRF)
- **Quality:** 49% (panels) / 52% (keynote)
- ❌ **Hardware encoder OFF** — NVENC is fast but makes *bigger* files; defeats the point
- GOP / keyframe interval: leave default

### Video tab
- **Resolution:** 1280×720 (panels) / 1920×1080 (keynote)
- **Frame rate:** 30 (25 also fine for talking heads)
- **Scan mode:** Progressive

### Audio tab
- **Codec:** AAC
- **Bitrate:** 96–128 kbps (it's speech — doesn't need more)
- Mono is an option for single-speaker if you want it even smaller

### Don't bother with
- ❌ `-preset slow` — across a whole day of segments it cooks the machine
  for hours to save a couple MB. Default (medium) is the pragmatic pick.
- ❌ Parallel processing on long single files — small A/V sync drift risk,
  speed gain not worth it.

---

## Workflow (the pipeline that worked)

1. **Add Zoom video** on its own track (V1).
2. **Add Zoom audio** on its own track (A1) — get it audible *first* so you
   can hear what you're editing against. (Solves the perception problem
   before the editing problem.)
3. **Place markers** at segment boundaries; **name** each one.
4. **Save as `.mlt`** ← this is your **source of truth** (plain XML,
   references the Zoom source by path).
5. **Export by marker** — each named range → its own MP4.

### Source-of-truth hygiene
- MLT references the Zoom file **by path** → keep them in one folder so the
  path doesn't rot. Suggested layout:
  ```
  Day1/
  ├── zoom-source.mp4        # raw recording
  ├── day1.mlt               # source of truth
  └── exports/               # derived MP4s (+ .vtt later)
  ```
- Every export is a **reversible guess** — wrong resolution? wrong quality?
  Reopen the MLT, tweak one marker, re-export. Original never touched.
- **Save the MLT _after_ any silence-trims**, or past-you's careful edit is
  gone when you reopen it.

### Cutting out silence (the split-both-cut-both dance)
- Two tracks = two independent timelines. To remove a chunk you split **both**
  V1 and A1 at in-point and out-point, select **both** middle clips, remove.
- Stays in sync because you remove **equal-length** pieces at the **same**
  position on both tracks.
- Optional speed-up: **Ripple All Tracks** toggle (+ **Ripple Markers**) lets
  one ripple-delete (`X`) pull the audio with the video — _only_ turn it on
  for this clean 2-track shape; turn it **off** once you add overlay/title
  tracks, or it'll yank those left too.
- Alternative when silence sits *between* segments: just **bound your markers
  around it** and never export those seconds (non-destructive).

---

## Test smart, don't re-export the whole thing
- Set **in/out points** over a 1–2 min chunk that includes your **hardest
  case** (e.g. the Disclosures slide with the PiP + small print).
- Export just that, check size + legibility at the **real embed width**, then
  fullscreen it too (that's where 1080p shows up, if anywhere).
- If even fullscreen is a wash vs 720p → you've proven 720p is the keeper.

---

## Reading the encode queue (sanity check)
- Encode **time scales with source duration**, not output size.
- Talking-head footage is cheap per-frame → encodes several × faster than real-time.
- Slide/PiP/gradient footage costs more bits *and* more time — bigger file
  there is the encoder working **correctly** (constant quality, variable size).
- Times scaling cleanly with length = consistent, easy-to-compress material. ✅

---

## Next step: captions (whenever videos are all exported)
- Splicing breaks old captions because **VTT/SRT cues are timestamps pinned
  to the original timeline.** Cut the video and they point at the wrong place.
- Fix: **caption each segment _after_ export**, so cues start at zero and
  match that file.
- Tool: **whisper.cpp** — runs **fully local** (no cloud/account), single
  binary, outputs WebVTT/SRT directly. Flies on 20 cores.
  - Rough flow: export MP4 → `ffmpeg` extract WAV → whisper.cpp → `.vtt`
    (starts at zero) → `<track kind="captions" src="...vtt">` in `<video>`.
- ⚠️ Medical/pharma vocab (Medtronic, Sanofi, arrhythmia, FHRS…) is exactly
  what Whisper fumbles. **The slides are your answer key** — caption with the
  video open next to the editor and fix proper nouns against the slide text.
- a11y bonus for self-hosted `<video>`: captions help HoH viewers _and_
  muted-in-an-office viewers. Also check the MP4 **"faststart" / moov atom**
  is at the front so long files start streaming on click instead of after a
  full download.

---

## Learn-more rabbit holes
- FFmpeg **H.264 Video Encoding Guide** (their wiki) — CRF, presets, tunes.
- `x264 --fullhelp` — every knob, including `-tune stillimage` (made for
  screen-share content) and `-preset slow` (smaller at same quality, slow).
- Shotcut's Codec tab **"Other"** field passes extra x264 params if you ever
  want to experiment (e.g. `-tune stillimage` for slide-heavy segments).
- "Intel hybrid architecture" + "ARM big.LITTLE" + Intel **Thread Director**
  — why Naelaedra reports 20 cores but 28 threads. ^_^