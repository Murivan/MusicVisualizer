#!/bin/bash
set -eu

SPIKE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$SPIKE_DIR/../.." && pwd)
JAVA_HOME=${PROCESSING_JAVA_HOME:-/Applications/Processing.app/Contents/app/resources/jdk}
JNA_JAR=${JNA_JAR:-/Applications/Processing.app/Contents/app/resources/modes/java/mode/jna-5.19.1.jar}
PORTAUDIO_LIB=${PORTAUDIO_LIB:-/opt/homebrew/opt/portaudio/lib/libportaudio.2.dylib}

for required in "$JAVA_HOME/bin/java" "$JAVA_HOME/bin/javac" "$JNA_JAR" "$PORTAUDIO_LIB"; do
  if [ ! -e "$required" ]; then
    printf 'Required dependency not found: %s\n' "$required" >&2
    exit 1
  fi
done

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/core-audio-spike.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

"$JAVA_HOME/bin/javac" -cp "$JNA_JAR" -d "$BUILD_DIR" \
  "$SPIKE_DIR/CoreAudioSpike.java" \
  "$REPO_ROOT/Visualizer/audio-src/RollingAudioBuffer.java"
"$JAVA_HOME/bin/java" -Djna.library.path="$(dirname -- "$PORTAUDIO_LIB")" \
  -cp "$BUILD_DIR:$JNA_JAR" CoreAudioSpike "$PORTAUDIO_LIB" "$@"
