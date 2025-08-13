#!/bin/bash
set -e

WINDOW_TITLE="Chromium"

# Function to clean up background processes when the script exits
cleanup() {
  echo "Cleaning up processes..."
  pkill -P $$ || true  # Kill all child processes
  exit 0
}

# Set trap to call cleanup function when script receives termination signal
trap cleanup SIGINT SIGTERM EXIT

sleep 10

# Ensure we have proper X11 permissions
if [ -f "/tmp/.Xauthority" ]; then
  echo "Using shared X authority file"
  export XAUTHORITY=/tmp/.Xauthority
fi


# Add this before trying to find the window
echo "Testing X server connection..."
xdpyinfo -display :10 || echo "Cannot connect to X server"

# Use DISPLAY=:10 to match the headful browser container
WINDOW_ID=$(xdotool search --name Chromium | while read id; do
    geom=$(xwininfo -id $id | awk '/geometry/{print $2}')
    if [[ "$geom" == "1919x1079--9--9" ]]; then
        echo $id
        break
    fi
done)
    ffmpeg -f x11grab -framerate 30 -video_size 1919x1079 -draw_mouse 1 -i :10.0 \
      -c:v libvpx -deadline realtime -cpu-used 4 -auto-alt-ref 0 \
      -quality realtime -b:v 1M -maxrate 1M -bufsize 2M \
      -an -f rtp rtp://127.0.0.1:5004 &

# Start Pion WebRTC server
echo "Starting Pion WebRTC server..."
cd /app/pion && ./server
