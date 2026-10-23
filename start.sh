#!/usr/bin/env bash
# ==============================================================================
# Sony Walkman Studio (macOS Native Apple Silicon & Intel) - Startup Script
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================="
echo "   Sony Walkman Studio - Native macOS (Apple Silicon & Intel)"
echo "   Liquid Glass UI & S-Master HX Hardware Integration"
echo "================================================================="

# Build the native app if not already built or outdated
if [ ! -d "Walkman Studio.app" ] || [ "Sources/WalkmanStudio" -nt "Walkman Studio.app" ]; then
    echo "[*] Building native Swift release bundle..."
    ./build_app.sh
fi

echo "[*] Launching Walkman Studio native app..."
open "Walkman Studio.app"
echo "[✓] Walkman Studio is running natively."
