#!/bin/bash
# Extract accent color from a wallpaper image
# Usage: extract-accent.sh /path/to/wallpaper.jpg [monitor-name]
#
# If monitor-name is "All" or omitted, writes to ~/.cache/quickshell/accent
# If monitor-name is specific (e.g. "DP-2"), writes to ~/.cache/quickshell/accent-DP-2
# Then notifies Quickshell via IPC to pick up the change

IMG="$1"
MONITOR="$2"
[ -z "$IMG" ] || [ ! -f "$IMG" ] && exit 1

CACHE_DIR="$HOME/.cache/quickshell"
mkdir -p "$CACHE_DIR"

# Determine output file
if [ -z "$MONITOR" ] || [ "$MONITOR" = "All" ]; then
    ACCENT_FILE="$CACHE_DIR/accent"
else
    ACCENT_FILE="$CACHE_DIR/accent-$MONITOR"
fi

write_accent() {
    echo "$1" > "$ACCENT_FILE"

    # Generate dynamic hyprlock.conf with accent color
    local HEX="$1"
    local R=$((16#${HEX:1:2}))
    local G=$((16#${HEX:3:2}))
    local B=$((16#${HEX:5:2}))

    cat > "$HOME/.config/hypr/hyprlock.conf" << HYPREOF
background {
    monitor =
    path = screenshot
    blur_passes = 3
    blur_size = 8
}

input-field {
    monitor =
    size = 280, 50
    outline_thickness = 2
    dots_size = 0.25
    dots_spacing = 0.15
    outer_color = rgba(${R}, ${G}, ${B}, 0.6)
    inner_color = rgba(15, 12, 20, 0.9)
    font_color = rgb(205, 214, 244)
    fade_on_empty = true
    placeholder_text = <i>Password...</i>
    position = 0, -40
    halign = center
    valign = center
}

label {
    monitor =
    text = \$TIME
    font_size = 72
    font_family = JetBrainsMono Nerd Font
    color = rgba(${R}, ${G}, ${B}, 0.9)
    position = 0, 80
    halign = center
    valign = center
}

label {
    monitor =
    text = cmd[update:60000] date '+%A, %d %B'
    font_size = 14
    font_family = JetBrainsMono Nerd Font
    color = rgba(205, 214, 244, 0.6)
    position = 0, 30
    halign = center
    valign = center
}
HYPREOF

    command -v qs &>/dev/null && qs msg accent update 2>/dev/null
    exit 0
}

# Boost a hex color to neon-level saturation (s >= 0.75, v in 0.7–0.92)
boost_color() {
    python3 -c "
import colorsys, sys
h = sys.argv[1].strip().lstrip('#')
r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
hue, s, v = colorsys.rgb_to_hsv(r, g, b)
s = max(s, 0.75)
v = min(max(v, 0.7), 0.92)
r2, g2, b2 = colorsys.hsv_to_rgb(hue, s, v)
print(f'#{int(r2*255):02x}{int(g2*255):02x}{int(b2*255):02x}')
" "$1" 2>/dev/null
}

# ── Method 1: matugen (Material You — best results) ───────────
if command -v matugen &>/dev/null; then
    JSON=$(matugen image "$IMG" -j hex --dry-run --source-color-index 0 \
           --type scheme-vibrant -m dark 2>/dev/null)

    if [ -n "$JSON" ]; then
        BEST=$(python3 -c "
import json, colorsys, sys
data = json.loads(sys.stdin.read())
colors = data.get('colors', {}).get('dark', data.get('colors', {}))
keys = ['tertiary', 'primary', 'secondary']
best, best_sat = None, 0
for k in keys:
    hx = colors.get(k, '')
    if not hx or len(hx) != 7: continue
    r, g, b = int(hx[1:3],16)/255, int(hx[3:5],16)/255, int(hx[5:7],16)/255
    _, s, v = colorsys.rgb_to_hsv(r, g, b)
    if s * v > best_sat:
        best_sat = s * v
        best = hx
if best: print(best)
" <<< "$JSON" 2>/dev/null)

        if [ -n "$BEST" ]; then
            BOOSTED=$(boost_color "$BEST")
            [ -n "$BOOSTED" ] && write_accent "$BOOSTED"
            write_accent "$BEST"
        fi
    fi
fi

# ── Method 2: ImageMagick + Python (vibrant color picker) ──────
if command -v magick &>/dev/null && command -v python3 &>/dev/null; then
    HIST=$(magick "$IMG" -resize 100x100! +dither -colors 16 \
           -format '%c' histogram:info:- 2>/dev/null)

    if [ -n "$HIST" ]; then
        RAW=$(python3 -c "
import colorsys, sys, re
best, score = None, 0
for line in sys.stdin:
    m = re.search(r'(\d+):.*#([0-9A-Fa-f]{6})', line)
    if not m: continue
    count = int(m.group(1))
    hx = m.group(2)
    r, g, b = int(hx[0:2],16)/255, int(hx[2:4],16)/255, int(hx[4:6],16)/255
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if s < 0.15 or v < 0.15 or v > 0.95: continue
    sc = (s * 0.7 + v * 0.3) * (count ** 0.2)
    if sc > score: score, best = sc, '#' + hx.lower()
if best: print(best)
" <<< "$HIST" 2>/dev/null)

        if [ -n "$RAW" ]; then
            BOOSTED=$(boost_color "$RAW")
            [ -n "$BOOSTED" ] && write_accent "$BOOSTED"
            write_accent "$RAW"
        fi
    fi
fi

exit 1
