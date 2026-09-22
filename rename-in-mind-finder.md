# Renaming in Mint Finder

These are just common rules for bulk renaming in Mint's finder.

## Episode renaming, per season

Check regular expression.

From: `Link to Season 1, Episode (\d+)`

To: `<Show Name> - S01E%n`

Alternative:

Scan for 3 digit episode number and rename:

From: `S(\d{2})E(\d{2})` or `(\d{1})(\d{2})`

To: `S\1E\2`

Subs quick convert:

Takes something like `3_dan,Danish.srt` and outputs `<filename>.dan.srt`. Modify to the correct format.

From: `(\d{1,2})_(\w{3}),(\w+)`

To: `<filename>.\2{.srt}`

To match the start of a filename exactly:

Find: `^(\d{2})\s`
Replace: `Saturday Night Live - S20E\1 -`
