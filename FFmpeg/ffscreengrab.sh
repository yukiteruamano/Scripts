#!/usr/bin/env bash

# Cross-platform Screen Recording with FFmpeg
# Supports: OpenBSD, FreeBSD, Linux (X11)

OS=$(uname -s)

# Default values
DEFAULT_FRAMERATE="30"
DEFAULT_CODEC="libx264"
DEFAULT_CRF="23"
DEFAULT_PRESET="veryfast"
DEFAULT_SCALE="1.0" # 1.0 = 100% (original), 0.5 = 50%, 2.0 = 200%, etc.

USAGE="USAGE: ffscreengrab [audio_device] [framerate] [codec] [crf] [preset] [scale]
    Options:
        -h, --help        Show this help message and exit

    Defaults:
        audio_device: auto-detected per OS
        framerate:    $DEFAULT_FRAMERATE
        codec:        $DEFAULT_CODEC
        crf:          $DEFAULT_CRF
        preset:       $DEFAULT_PRESET
        scale:        $DEFAULT_SCALE (e.g., 0.5 for half size, 1920x1080 for fixed)

    Examples:
        ffscreengrab              # use defaults
        ffscreengrab auto 30 libx264 23 medium 0.5  # record at 50% scale"

# 0. Help Flag Check
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "$USAGE"
    exit 0
fi

# 1. Environment Detection
echo "Detecting environment ($OS)..."

case "$OS" in
OpenBSD)
    # Using sndio for OpenBSD
    AUDIO_INPUT="-f sndio -i ${1:-default}"
    SCREEN_INPUT="-f x11grab"
    ;;
FreeBSD)
    # Using OSS for FreeBSD
    AUDIO_INPUT="-f oss -i ${1:-/dev/dsp}"
    SCREEN_INPUT="-f x11grab"
    ;;
Linux)
    # Prefer PulseAudio/PipeWire for Linux
    if command -v pactl >/dev/null; then
        AUDIO_INPUT="-f pulse -i ${1:-default}"
    else
        AUDIO_INPUT="-f alsa -i ${1:-default}"
    fi
    SCREEN_INPUT="-f x11grab"
    ;;
*)
    echo "Error: Unsupported OS '$OS'"
    exit 1
    ;;
esac

# 2. Parameters
FRAMERATE="${2:-$DEFAULT_FRAMERATE}"
VIDEO_CODEC="${3:-$DEFAULT_CODEC}"
CRF_VALUE="${4:-$DEFAULT_CRF}"
CODEC_PRESET="${5:-$DEFAULT_PRESET}"
SCALE="${6:-$DEFAULT_SCALE}"

# 3. Output Resolution (X11)
if command -v xdpyinfo >/dev/null; then
    RES=$(xdpyinfo | grep dimensions | awk '{print $2}')
else
    echo "Warning: xdpyinfo not found. Cannot auto-detect resolution."
    exit 1
fi

# 4. Save Location (XDG)
if command -v xdg-user-dir >/dev/null; then
    VIDEO_DIR="$(xdg-user-dir VIDEOS)"
else
    VIDEO_DIR="$HOME/Videos"
fi
mkdir -p "$VIDEO_DIR"

# 5. File Naming
TODAY=$(date +"%Y-%m-%d")
COUNTER=0
while [[ -f "$VIDEO_DIR/screengrab-$TODAY-$COUNTER.mkv" ]]; do
    ((COUNTER++))
done
OUT_FILE="$VIDEO_DIR/screengrab-$TODAY-$COUNTER.mkv"

# 6. Hardware Acceleration Check (VAAPI)
VAAPI_OPTS=""
if [ -e /dev/dri/renderD128 ] && [[ "$VIDEO_CODEC" == *"vaapi"* ]]; then
    VAAPI_OPTS="-hwaccel vaapi -vaapi_device /dev/dri/renderD128 -hwaccel_output_format vaapi"
    echo "Hardware acceleration (VAAPI) enabled."
fi

# 7. Scaling and Filter Logic
FILTER_OPTS=""
if [ "$SCALE" != "1.0" ]; then
    if [[ "$SCALE" =~ ^[0-9]+x[0-9]+$ ]]; then
        # Fixed resolution (e.g., 1280x720)
        FILTER_OPTS="-vf scale=$SCALE:flags=bicubic"
    else
        # Relative scale (e.g., 0.5)
        FILTER_OPTS="-vf scale=iw*$SCALE:ih*$SCALE:flags=bicubic"
    fi
    echo "Scaling enabled: $SCALE"
fi

# 8. Multi-threading Logic
if [[ "$OS" == "Linux" ]]; then
    THREADS=$(nproc 2>/dev/null || echo "0")
else
    THREADS=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
fi
THREAD_OPTS="-threads $THREADS"

# 9. Confirmation
echo "********************************************"
echo "Recording Start Details:"
echo "  OS:           $OS"
echo "  Resolution:   $RES"
echo "  Scale:        $SCALE"
echo "  Threads:      $THREADS"
echo "  Framerate:    $FRAMERATE fps"
echo "  Audio:        $AUDIO_INPUT"
echo "  Codec:        $VIDEO_CODEC"
echo "  Output:       $OUT_FILE"
echo ""
echo "Press CTRL+C to finish recording."
echo "Starting in 5 seconds..."
echo "********************************************"

sleep 5

# 10. Main Execution
# Using a single ffmpeg instance to keep audio/video in sync
ffmpeg -y \
    $VAAPI_OPTS \
    -thread_queue_size 2048 \
    $SCREEN_INPUT -r "$FRAMERATE" -s "$RES" -i :0.0 \
    -thread_queue_size 2048 \
    $AUDIO_INPUT \
    $FILTER_OPTS \
    $THREAD_OPTS \
    -vf "format=nv12,hwupload" \
    -c:v "$VIDEO_CODEC" -crf "$CRF_VALUE" -preset "$CODEC_PRESET" \
    -c:a aac -b:a 192k \
    "$OUT_FILE"
