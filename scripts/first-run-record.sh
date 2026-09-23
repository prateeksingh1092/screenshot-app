#!/bin/sh
set -eu
# Writes host metadata only. Does not launch Frisket, capture, or read the pasteboard.
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
app=${FRISKET_APP:-/Users/16intelmac/Applications/Frisket.app}
permission=${FRISKET_PERMISSION:-granted}
output=${FRISKET_FIRST_RUN_RECORD:-$root/.build/first-run/record.json}
exec /usr/bin/python3 -B "$root/Tools/FirstRun/record.py" header \
  --app "$app" --permission "$permission" --output "$output" --repository "$root"
