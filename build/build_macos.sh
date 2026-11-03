#!/bin/bash
# Builds dist/ImageAnalyzer-macos-arm64.zip (Apple Silicon). Run on a Mac:  bash build/build_macos.sh
set -euo pipefail
export PYTHONNOUSERSITE=1   # never let packages from the build machine leak into the bundle

PBS_TAG="20261026"
PY_VERSION="3.12.16"
ASSET="cpython-${PY_VERSION}+${PBS_TAG}-aarch64-apple-darwin-install_only_stripped.tar.gz"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${ASSET//+/%2B}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
CACHE="$DIST/.cache"
OUT="$DIST/ImageAnalyzer"
ZIP="$DIST/ImageAnalyzer-macos-arm64.zip"

if [ "$(uname -m)" != "arm64" ]; then
    echo "This script builds the Apple Silicon bundle and must run on an arm64 Mac." >&2
    exit 1
fi

mkdir -p "$CACHE"
rm -rf "$OUT"
mkdir -p "$OUT"

if [ ! -f "$CACHE/$ASSET" ]; then
    echo "Downloading $ASSET ..."
    curl -fL "$URL" -o "$CACHE/$ASSET"
fi

echo "Extracting Python runtime ..."
tar -xzf "$CACHE/$ASSET" -C "$OUT"      # produces $OUT/python
PYTHON="$OUT/python/bin/python3"

echo "Installing packages ..."
"$PYTHON" -m pip install --disable-pip-version-check -r "$ROOT/bundle/requirements.txt"

cp "$ROOT/ImageAnalyzer_App.ipynb" "$ROOT/voila.json" "$ROOT/bundle/README_USER.txt" "$OUT/"
cp "$ROOT/bundle/Start.command" "$OUT/"
chmod +x "$OUT/Start.command"

echo "Smoke test ..."
"$PYTHON" -c "import cv2, numpy, ipywidgets, voila, ipykernel, tkinter; print('imports ok')"

PORT=8899
(cd "$OUT" && PYTHONNOUSERSITE=1 "$PYTHON" -m voila ImageAnalyzer_App.ipynb --no-browser --port=$PORT --Voila.ip=127.0.0.1 >/dev/null 2>&1) &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
ok=0
for _ in $(seq 1 30); do
    sleep 2
    if curl -fs -o /dev/null "http://127.0.0.1:$PORT/"; then ok=1; break; fi
done
kill $SERVER_PID 2>/dev/null || true
[ "$ok" = 1 ] || { echo "Smoke test failed: Voila did not serve the notebook." >&2; exit 1; }

find "$OUT" -type d -name __pycache__ -prune -exec rm -rf {} +

rm -f "$ZIP"
echo "Creating zip ..."
(cd "$DIST" && ditto -c -k --keepParent ImageAnalyzer "$ZIP")
echo "Done: $ZIP ($(du -h "$ZIP" | cut -f1))"
