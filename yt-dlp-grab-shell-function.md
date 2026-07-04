# yt-dlp pixiekat-ytgrab

This simplifies grabbing a video from Youtube using yt-dlp at a set resolution (default 480p because I'm old school).

```bash
# grabs a youtube video by id at a given resolution (default 480p)
pixiekat-ytgrab() {
  local id="$1"
  local res="${2:-480}"   # default ceiling = 480; override as 2nd arg

  # --- help / usage -------------------------------------------------------
  if [[ "$id" == "--help" || "$id" == "--usage" ]]; then
    echo "Usage: pixiekat-ytgrab <youtube_id> [max_height]"
    echo "Example: pixiekat-ytgrab dQw4w9WgXcQ 480"
    echo ""
    echo "Env overrides:"
    echo "  YTGRAB_BROWSER   cookies-from-browser source (default: vivaldi)"
    echo "  YTGRAB_OUTDIR    output directory (default: current dir)"
    echo "  YTGRAB_ARCHIVE   download-archive file (default: ~/.local/share/pixiekat/ytgrab-archive.txt)"
    return 0
  fi

  # --- bail if no id ------------------------------------------------------
  if [ -z "$id" ]; then
    echo "Usage: pixiekat-ytgrab <youtube_id> [max_height]" >&2
    return 1
  fi

  local url="https://www.youtube.com/watch?v=$id"

  # --- configurable bits (env vars, with defaults) ------------------------
  # which browser to pull cookies from. you're on firefox nightly now, so you
  # may want YTGRAB_BROWSER=firefox — left as vivaldi to match your original.
  local browser="${YTGRAB_BROWSER:-vivaldi}"

  # where files land. default to $PWD so single grabs stay where you are,
  # but you can point this at your ISO-8601 tree for batch runs.
  local outdir="${YTGRAB_OUTDIR:-.}"

  # download-archive: yt-dlp records every grabbed id here and SKIPS them on
  # re-runs. this is the "never re-fetch what i already have" instinct, same
  # as your seedbox/backup discipline. safe to share across all your grabs.
  local archive="${YTGRAB_ARCHIVE:-$HOME/.local/share/pixiekat/ytgrab-archive.txt}"
  mkdir -p "$(dirname "$archive")"   # make sure the dir exists first

  # --- format selection (replaces the old -F + awk scraping) --------------
  # yt-dlp's own selector language does what the awk did, but robustly:
  #   bv*[height<=N][ext=mp4]+ba[ext=m4a]  ideal: mp4 video <=ceiling + m4a audio
  #   /bv*[height<=N]+ba                   fallback: any video <=ceiling + any audio
  #   /b[height<=N]                        fallback: best PRE-MUXED stream <=ceiling
  #   /b                                   last resort: best anything (rare/old uploads)
  # the '/' is yt-dlp's "try-left-then-right" operator — graceful degradation
  # expressed as a format string. [height<=480] is ANCHORED so 480 can never
  # accidentally match inside "1080" the way the old substring regex could.
  local fmt="bv*[height<=${res}][ext=mp4]+ba[ext=m4a]/bv*[height<=${res}]+ba/b[height<=${res}]/b"

  # --- the grab -----------------------------------------------------------
  # throttle flags keep us a polite scraper (essential once you loop over many
  # ids): jittered sleeps look less robotic than a fixed delay.
  #   --sleep-requests   pause between metadata/API calls
  #   --sleep-interval / --max-sleep-interval   RANDOM pause between downloads
  # sidecars (--write-info-json / --write-thumbnail) preserve the uploader's
  # description + poster frame — for archive uploads the real date/context
  # often lives in that description, so it's worth keeping their cataloging.
  yt-dlp \
    -f "$fmt" \
    --cookies-from-browser "$browser" \
    --download-archive "$archive" \
    --write-subs --no-write-auto-subs --sub-lang "en.*" \
    --write-info-json --write-thumbnail \
    --sleep-requests 1.5 \
    --sleep-interval 5 --max-sleep-interval 15 \
    -o "$outdir/%(title)s [%(upload_date>%Y-%m-%d)s - %(id)s].%(ext)s" \
    "$url"
}

```
