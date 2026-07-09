# General Linux Commands

Saves tree output to a dated file.

```bash
tree > ~/music-library-$(date +%Y%m%d).txt
```

*MKVtools*:

Get information about tracks:

```bash
mkvmerge -i <filename>
```

The output will look something like this:

```bash
File 'filename.mkv': container: Matroska
Track ID 0: video (MPEG-1/2)
Track ID 1: audio (AC-3)
Track ID 2: subtitles (VobSub)
Chapters: 6 entries
```

Then extract the subs like this, using the track ID from above:

```bash
# VobSub extraction creates TWO files: filename.en.idx + filename.en.sub — keep them paired
mkvextract tracks "filename.mkv" <ID>:"filename.en.idx"
```

Set default audio tracks:

```bash
mkvpropedit "filename.mkv" --edit track:a1 --set flag-default=1 --edit track:a2 --set flag-default=0 
```

Set name of audio track:

```bash
mkvpropedit "filename.mkv" --edit track:a1 --set name="English"  
```

You can use `mkvtoolnix-gui` for a GUI experience.
