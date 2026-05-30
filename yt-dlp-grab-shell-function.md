# yt-dlp pixiekat-ytgrab

This simplifies grabbing a video from Youtube using yt-dlp at a set resolution (default 480p because I'm old school).

```bash
# grabs a youtube video by id at a given resolution (default 480p)
pixiekat-ytgrab() {
  local id="$1"
  local res="${2:-480}" # default to 480
  local url="https://www.youtube.com/watch?v=$id"

  # provide help for --help and --usage flags
  if [[ "$id" == "--help" || "$id" == "--usage" ]]; then
    echo "Usage: ytgrab <youtube_id> [resolution]"
    echo "Example: ytgrab dQw4w9WgXcQ 720"
    return 0
  fi

  # if we don't have an id, bail out
  if [ -z "$id" ]; then
    echo "Usage: ytgrab <youtube_id> [resolution]"
    return 1
  fi

  # fetch formats
  local fmt
  fmt=$(yt-dlp -F --cookies-from-browser vivaldi "$url")

  # printing the format output
  echo "$fmt"

  # pick video format matching the requested resolution
  local vfmt
  vfmt=$(echo "$fmt" | awk -v r="${res}p" '$0 ~ r && /video/ {print $1}' | head -n1)

  # pick best m4a audio
  local afmt
  afmt=$(echo "$fmt" | awk '/m4a/ && /audio/ {print $1}' | head -n1)

  # safety check
  if [ -z "$vfmt" ] || [ -z "$afmt" ]; then
    echo "Could not find matching formats (video ${res}p or m4a audio)."
    return 1
  fi

  echo fetching: yt-dlp -f ${vfmt}+${afmt} --cookies-from-browser vivaldi --write-subs --no-write-auto-subs --sub-lang "en.*" $url
  yt-dlp -f "${vfmt}+${afmt}" --write-subs --cookies-from-browser vivaldi --no-write-auto-subs --sub-lang "en.*" "$url"
}
```
