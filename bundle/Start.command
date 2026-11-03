#!/bin/bash
cd "$(dirname "$0")" || exit 1

export IMAGE_ANALYZER_OUTPUT="$PWD/output"
export PYTHONNOUSERSITE=1

# Pick the first free port starting at 8866
PORT=8866
while lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
    PORT=$((PORT + 1))
done

echo "Starting the Image Analyzer. Your browser will open in a moment."
echo "Keep this window open while you work. Close it to quit the application."
echo
./python/bin/python3 -m voila ImageAnalyzer_App.ipynb --port="$PORT" --Voila.ip=127.0.0.1 || {
    echo
    echo "The application stopped unexpectedly. See the messages above."
    read -r -p "Press Enter to close."
}
