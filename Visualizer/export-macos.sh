#!/bin/bash
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'Usage: %s <new-output-directory> [processing-java]\n' "$0" >&2
  exit 2
fi

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_PARENT=$(dirname -- "$1")
OUTPUT_NAME=$(basename -- "$1")
PROCESSING_CLI=${2:-/usr/local/bin/processing-java}
SOURCE_DATA="$HERE/data/coreaudio"

if [ ! -d "$OUTPUT_PARENT" ]; then
  printf 'Export parent directory does not exist: %s\n' "$OUTPUT_PARENT" >&2
  exit 1
fi
OUTPUT="$(cd -- "$OUTPUT_PARENT" && pwd)/$OUTPUT_NAME"
if [ -e "$OUTPUT" ]; then
  printf 'Refusing to overwrite existing export directory: %s\n' "$OUTPUT" >&2
  exit 1
fi
if [ ! -x "$PROCESSING_CLI" ]; then
  printf 'Processing CLI is not executable: %s\n' "$PROCESSING_CLI" >&2
  exit 1
fi
for required in coreaudio-backend.jar jna.jar libportaudio.2.dylib JNA-LICENSE.txt PORTAUDIO-LICENSE.txt; do
  if [ ! -f "$SOURCE_DATA/$required" ]; then
    printf 'Missing %s; run setup-coreaudio.sh first.\n' "$SOURCE_DATA/$required" >&2
    exit 1
  fi
done

set +e
"$PROCESSING_CLI" --sketch="$HERE" --output="$OUTPUT" --variant=macos-aarch64 --export
export_status=$?
set -e
if [ "$export_status" -ne 0 ]; then
  printf 'Processing export failed (%s); inspect the partial output at %s before removing it.\n' \
    "$export_status" "$OUTPUT" >&2
  exit "$export_status"
fi

APP=$(find "$OUTPUT" -maxdepth 4 -type d -name '*.app' -print -quit)
if [ -z "$APP" ]; then
  printf 'Processing did not produce an .app bundle; partial output remains at %s.\n' "$OUTPUT" >&2
  exit 1
fi
INFO="$APP/Contents/Info.plist"
EXECUTABLE=$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -111 -print -quit 2>/dev/null || true)
if [ ! -f "$INFO" ] || [ -z "$EXECUTABLE" ]; then
  printf 'Exported app is incomplete (missing Info.plist or executable); partial output remains at %s.\n' \
    "$OUTPUT" >&2
  exit 1
fi
if ! lipo -archs "$EXECUTABLE" | tr ' ' '\n' | grep -qx arm64; then
  printf 'Exported application executable has no arm64 slice: %s\n' "$EXECUTABLE" >&2
  exit 1
fi

EXPORTED_LIBRARY=$(find "$APP/Contents" -type f -name libportaudio.2.dylib -print -quit)
if [ -z "$EXPORTED_LIBRARY" ]; then
  printf 'Exported app does not contain the staged PortAudio library; partial output remains at %s.\n' \
    "$OUTPUT" >&2
  exit 1
fi
EXPORTED_DATA=$(dirname -- "$(dirname -- "$EXPORTED_LIBRARY")")
for required in coreaudio-backend.jar jna.jar libportaudio.2.dylib JNA-LICENSE.txt PORTAUDIO-LICENSE.txt; do
  if [ ! -f "$EXPORTED_DATA/coreaudio/$required" ]; then
    printf 'Exported app is missing data/coreaudio/%s.\n' "$required" >&2
    exit 1
  fi
  if ! cmp -s "$SOURCE_DATA/$required" "$EXPORTED_DATA/coreaudio/$required"; then
    printf 'Exported dependency differs from the staged file: %s\n' "$required" >&2
    exit 1
  fi
done

if /usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$INFO" >/dev/null 2>&1; then
  :
else
  /usr/libexec/PlistBuddy -c \
    'Add :NSMicrophoneUsageDescription string MusicVisualizer uses the selected audio input to drive its visualization.' \
    "$INFO"
fi
plutil -lint "$INFO"
codesign --verify --strict "$EXPORTED_LIBRARY"
shasum -a 256 "$SOURCE_DATA/coreaudio-backend.jar" "$SOURCE_DATA/jna.jar" \
  "$SOURCE_DATA/libportaudio.2.dylib" > "$OUTPUT/coreaudio-dependencies.sha256"

printf 'Verified macOS arm64 app: %s\n' "$APP"
printf 'Info.plist was modified to request microphone access. Sign/notarize after this step; no latency or clean-machine claim is made.\n'
