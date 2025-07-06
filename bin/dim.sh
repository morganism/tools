#!/usr/bin/env bash
# dim.sh – simple brightness controller for Linux systems
# Allows absolute, relative and preset brightness control.
# Requires write access to /sys/class/backlight/*

set -Eeuo pipefail

# Configurable paths and defaults
BRIGHTNESS_FILE=${BRIGHTNESS_FILE:-/sys/class/backlight/intel_backlight/brightness}
MAX_FILE=${MAX_FILE:-/sys/class/backlight/intel_backlight/max_brightness}
STEP=${STEP:-25}       # default +/- step size for dimup/dimdown

# Usage/help menu
print_usage() {
cat <<EOF
Usage:
  dim.sh LEVEL              Set brightness to LEVEL (absolute or relative)
  dim.sh                    Show current brightness
  dim.sh -h | --help        Show this help message

LEVEL:
  N     – absolute integer brightness (0 … MAX)
  +N    – increase brightness by N
  -N    – decrease brightness by N
  +     – increase brightness by \$STEP
  -     – decrease brightness by \$STEP

Environment overrides:
  BRIGHTNESS_FILE    Path to current brightness file
  MAX_FILE           Path to max_brightness file
  STEP               Default step for bare + / - use

Examples:
  dim.sh 0           Turn off backlight
  dim.sh 400         Set brightness to 400
  dim.sh +20         Increase brightness by 20
  dim.sh -           Decrease by default step (\$STEP)
  dim.sh             Show current brightness
EOF
}

# Error if brightness file isn't writable
[[ -w "$BRIGHTNESS_FILE" || -w "$(dirname "$BRIGHTNESS_FILE")" ]] \
  || { echo "❌ Need write access to $BRIGHTNESS_FILE (try sudo)"; exit 2; }

# Get current and max brightness
current=$(<"$BRIGHTNESS_FILE")
max=$(<"$MAX_FILE")

# No arguments → show current brightness
if [[ $# -eq 0 ]]; then
  echo "🔆 Current brightness: $current (max: $max)"
  exit 0
fi

# Help menu
case "$1" in
  -h|--help)
    print_usage
    exit 0
    ;;
esac

level=$1

# Clamp helper to 0–max
clamp() {
  local v=$1
  (( v < 0 )) && v=0
  (( v > max )) && v=$max
  printf '%s' "$v"
}

# Compute target brightness
case $level in
  +|-)
    delta=$([[ $level == "+" ]] && echo "$STEP" || echo "-$STEP")
    target=$(clamp $((current + delta)))
    ;;
  +*|-*)
    delta=${level}
    target=$(clamp $((current + delta)))
    ;;
  ''|*[!0-9]*)
    echo "⚠️  Invalid level: $level"
    print_usage
    exit 1
    ;;
  *)
    target=$(clamp "$level")
    ;;
esac

# Apply new brightness
printf '%s\n' "$target" | sudo tee "$BRIGHTNESS_FILE" >/dev/null
echo "✅ Brightness set to $target (max: $max)"

