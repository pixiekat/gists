# Renaming in Mint Finder

These are just common rules for bulk renaming in Mint's finder.

## Episode renaming, per season

Check regular expression.

From: `Link to Season 1, Episode (\d+)`

To: `<Show Name> - S01E%n`

Alternative:

Scan for 3 digit episode number and rename:

From: `S(\d{2})E(\d{2})`

To: `S\1E\2`
