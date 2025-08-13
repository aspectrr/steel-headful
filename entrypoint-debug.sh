#!/bin/bash
set -e

WINDOW_TITLE="Steel Browser"

# Function to clean up background processes when the script exits
cleanup() {
  echo "Cleaning up processes..."
  pkill -P $$ || true  # Kill all child processes
  exit 0
}

# Set trap to call cleanup function when script receives termination signal
trap cleanup SIGINT SIGTERM EXIT

echo "Waiting for browser container and API to be ready..."
# Wait 10 seconds as requested
echo "Waiting 10 seconds for API to start up..."
sleep 10

# Test X server connection
echo "Testing X server connection..."
xdpyinfo -display :10 || echo "Cannot connect to X server"

# List all windows and their properties for debugging
echo "Listing all available windows:"
xwininfo -root -tree -display :10 | grep -v "has no name" || echo "No windows found"

echo "Listing all window IDs and titles using xdotool:"
xdotool search --all --onlyvisible --name ".*" | while read id; do
  echo "Window ID: $id, Title: $(xdotool getwindowname $id 2>/dev/null || echo 'No title')"
done

# Try different search approaches
echo "Trying different search approaches..."

# 1. Try with exact match
WINDOW_ID=$(xdotool search --name "^${WINDOW_TITLE}$" | head -n 1)
if [ -n "$WINDOW_ID" ]; then
  echo "Found window with exact title match: $WINDOW_ID"
else
  echo "No exact title match found"

  # 2. Try with partial match
  WINDOW_ID=$(xdotool search --name "${WINDOW_TITLE}" | head -n 1)
  if [ -n "$WINDOW_ID" ]; then
    echo "Found window with partial title match: $WINDOW_ID"
  else
    echo "No partial match found either"

    # 3. Try with Chrome/Chromium specific window
    WINDOW_ID=$(xdotool search --class "chromium|chrome" | head -n 1)
    if [ -n "$WINDOW_ID" ]; then
      echo "Found Chrome/Chromium window: $WINDOW_ID"
    else
      echo "No Chrome/Chromium windows found"
    fi
  fi
fi

# If we found any window, proceed with it
if [ -z "$WINDOW_ID" ]; then
  echo "ERROR: No suitable window found to capture"
  echo "Using root window as fallback"
  # Use the root window as fallback
  WINDOW_ID=$(xwininfo -root -display :10 | grep "Window id" | awk '{print $4}')
fi

echo "Using window ID: $WINDOW_ID"
# Start ffmpeg screen capture streaming RTP
ffmpeg -f x11grab -framerate 60 -video_size 1280x720 -i :10.0 -c:v libvpx -an -f rtp rtp://127.0.0.1:5004 &

# Start Pion WebRTC server
echo "Starting Pion WebRTC server..."
cd /app/pion && ./server
