#!/bin/bash
set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
CORE_AUDIO_DIR="$HERE/data/coreaudio"
JAVA_HOME=${PROCESSING_JAVA_HOME:-/Applications/Processing.app/Contents/app/resources/jdk}
BACKEND_JAR="$CORE_AUDIO_DIR/coreaudio-backend.jar"
JNA_JAR="$CORE_AUDIO_DIR/jna.jar"
PORTAUDIO_LIB="$CORE_AUDIO_DIR/libportaudio.2.dylib"

if [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
  printf 'Usage: %s <host API fragment> <device fragment> [seconds] [read-frames] [FFT-size]\n' "$0" >&2
  exit 2
fi
for required in "$JAVA_HOME/bin/java" "$JAVA_HOME/bin/javac" "$BACKEND_JAR" "$JNA_JAR" "$PORTAUDIO_LIB"; do
  if [ ! -f "$required" ]; then
    printf 'Required dependency not found: %s\n' "$required" >&2
    exit 1
  fi
done

TEST_CLASSES=$(mktemp -d "${TMPDIR:-/tmp}/portaudio-live-test.XXXXXX")
trap 'rm -rf "$TEST_CLASSES"' EXIT
"$JAVA_HOME/bin/javac" -cp "$BACKEND_JAR:$JNA_JAR" -d "$TEST_CLASSES" \
  "$HERE/audio-src/PortAudioLiveInputTest.java"
"$JAVA_HOME/bin/java" -Xmx512m -cp "$TEST_CLASSES:$BACKEND_JAR:$JNA_JAR" \
  PortAudioLiveInputTest "$PORTAUDIO_LIB" "$@"
