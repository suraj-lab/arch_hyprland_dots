#!/bin/bash

# This script will randomly go through the files of a directory, setting it
# up as the wallpaper at regular intervals
#
# NOTE: this script uses bash (not POSIX shell) for the RANDOM variable

if [[ $# -lt 1 ]] || [[ ! -d $1 ]]; then
    echo "Usage:
    $0 <dir containing images>"
    exit 1
fi

# Edit below to control the images transition
export AWWW_TRANSITION_FPS=144
export AWWW_TRANSITION_STEP=3

# Transition types matching the wallpaper picker
TRANSITIONS=(fade left right top bottom wipe grow center outer wave)

# This controls (in seconds) when to switch to the next image
INTERVAL=1800

while true; do
    find "$1" \
        | while read -r img; do
            echo "$((RANDOM % 1000)):$img"
        done \
        | sort -n | cut -d':' -f2- \
        | while read -r img; do
            TRANSITION=${TRANSITIONS[$((RANDOM % ${#TRANSITIONS[@]}))]}
            awww img -o HDMI-A-1 "$img" \
                --transition-type "$TRANSITION" \
                --transition-pos center \
                --transition-duration 1
            # Extract accent color from wallpaper (HDMI-A-1 monitor)
            "$HOME/.config/quickshell/scripts/extract-accent.sh" "$img" "HDMI-A-1" &
            sleep $INTERVAL
        done
done
