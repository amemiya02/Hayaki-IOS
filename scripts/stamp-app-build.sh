#!/bin/bash
# Record facts about this app binary without rebuilding the core.
set -euo pipefail

lockfile="${SCRIPT_INPUT_FILE_0:?Missing Cargo.lock}"
destination="${SCRIPT_OUTPUT_FILE_0:?Missing build metadata destination}"
fsrs_version="$(awk '
    /^name = "fsrs"$/ { found = 1; next }
    found && /^version = "/ { split($0, fields, "\""); print fields[2]; exit }
' "$lockfile")"
[[ "$fsrs_version" =~ ^[0-9A-Za-z.+-]+$ ]]

mkdir -p "$(dirname "$destination")"
cat > "$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BuildDate</key><date>$(date -u +'%Y-%m-%dT%H:%M:%SZ')</date>
    <key>FSRSVersion</key><string>$fsrs_version</string>
</dict>
</plist>
PLIST
