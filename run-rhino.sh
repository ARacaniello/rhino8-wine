#!/bin/bash
# Launch Rhino 8 under the patched Wine build.
#
# Usage:
#   ./run-rhino.sh           — normal launch
#   ./run-rhino.sh --fresh   — kill and restart wineserver first
#                              (fixes port 1717 / OAuth licensing failures)

WINE=/opt/wine-rhino8/bin/wine
WINESERVER=/opt/wine-rhino8/bin/wineserver
WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
RHINO="$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"

if [ ! -f "$WINE" ]; then
  echo "ERROR: wine-rhino8 not found at $WINE"
  echo "Build and install with: makepkg -si  (from the repo directory)"
  exit 1
fi

if [ ! -f "$RHINO" ]; then
  echo "ERROR: Rhino 8 not found at $RHINO"
  echo "Set WINEPREFIX to your Rhino 8 wineprefix, or install Rhino first:"
  echo "  WINEPREFIX=$WINEPREFIX $WINE RhinoInstaller.exe"
  exit 1
fi

if [ "$1" = "--fresh" ]; then
  echo "Restarting wineserver for clean http.sys state..."
  WINEPREFIX="$WINEPREFIX" "$WINESERVER" -k 2>/dev/null
  sleep 2
fi

echo "Launching Rhino 8..."
DISPLAY="${DISPLAY:-:0}" \
WINEPREFIX="$WINEPREFIX" \
WINEDEBUG=-all \
  "$WINE" "$RHINO" 2>/tmp/rhino.log
