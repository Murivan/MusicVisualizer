#!/bin/bash
set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
DATA_DIR="$HERE/data"
TARGET="$DATA_DIR/coreaudio"
JAVA_HOME=${PROCESSING_JAVA_HOME:-/Applications/Processing.app/Contents/app/resources/jdk}
JNA_JAR=${JNA_JAR:-/Applications/Processing.app/Contents/app/resources/modes/java/mode/jna-5.19.1.jar}
PORTAUDIO_LIB=${PORTAUDIO_LIB:-/opt/homebrew/opt/portaudio/lib/libportaudio.2.dylib}
PORTAUDIO_LICENSE=${PORTAUDIO_LICENSE:-/opt/homebrew/opt/portaudio/LICENSE.txt}

verify_signature() {
  if codesign -dv "$1" >/dev/null 2>&1; then
    codesign --verify --strict "$1"
  else
    printf 'No embedded code signature; verify library provenance before use: %s\n' "$1" >&2
  fi
}

for required in "$JAVA_HOME/bin/java" "$JAVA_HOME/bin/javac" "$JAVA_HOME/bin/jar" \
  "$JNA_JAR" "$PORTAUDIO_LIB" "$PORTAUDIO_LICENSE"; do
  if [ ! -f "$required" ]; then
    printf 'Required dependency not found: %s\n' "$required" >&2
    exit 1
  fi
done
if [ -e "$TARGET" ]; then
  printf 'Refusing to overwrite existing dependency directory: %s\n' "$TARGET" >&2
  exit 1
fi

if ! lipo -archs "$PORTAUDIO_LIB" | tr ' ' '\n' | grep -qx arm64; then
  printf 'PortAudio library does not contain an arm64 slice: %s\n' "$PORTAUDIO_LIB" >&2
  exit 1
fi
if ! unzip -l "$JNA_JAR" | grep -q 'com/sun/jna/darwin-aarch64/libjnidispatch.jnilib'; then
  printf 'JNA jar has no macOS arm64 native library: %s\n' "$JNA_JAR" >&2
  exit 1
fi
if ! otool -L "$PORTAUDIO_LIB" | grep -q '/System/Library/Frameworks/CoreAudio.framework/'; then
  printf 'PortAudio library does not link CoreAudio: %s\n' "$PORTAUDIO_LIB" >&2
  exit 1
fi
verify_signature "$PORTAUDIO_LIB"

STAGE=$(mktemp -d "$DATA_DIR/.coreaudio-stage.XXXXXX")
cleanup() {
  if [ -d "$STAGE" ]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT

JNA_NATIVE="$STAGE/jnidispatch.jnilib"
unzip -p "$JNA_JAR" com/sun/jna/darwin-aarch64/libjnidispatch.jnilib > "$JNA_NATIVE"
if ! lipo -archs "$JNA_NATIVE" | tr ' ' '\n' | grep -qx arm64; then
  printf 'JNA native library does not contain an arm64 slice: %s\n' "$JNA_JAR" >&2
  exit 1
fi
rm -f "$JNA_NATIVE"

CLASSES="$STAGE/classes"
mkdir "$CLASSES"
"$JAVA_HOME/bin/javac" -cp "$JNA_JAR" -d "$CLASSES" \
  "$HERE/audio-src/RollingAudioBuffer.java" \
  "$HERE/audio-src/PortAudioInput.java" \
  "$HERE/audio-src/WasapiInput.java" \
  "$HERE/audio-src/PortAudioInputLayoutTest.java" \
  "$HERE/audio-src/PortAudioLiveInputTest.java" \
  "$HERE/audio-src/RollingAudioBufferTest.java"
"$JAVA_HOME/bin/java" -cp "$CLASSES" RollingAudioBufferTest
"$JAVA_HOME/bin/java" -cp "$CLASSES:$JNA_JAR" PortAudioInputLayoutTest

rm -f "$CLASSES/RollingAudioBufferTest.class" "$CLASSES/PortAudioInputLayoutTest.class" \
  "$CLASSES/PortAudioLiveInputTest.class"
"$JAVA_HOME/bin/jar" cf "$STAGE/coreaudio-backend.jar" -C "$CLASSES" .
rm -rf "$CLASSES"
cp "$JNA_JAR" "$STAGE/jna.jar"
unzip -p "$JNA_JAR" META-INF/LICENSE > "$STAGE/JNA-LICENSE.txt"
cp "$PORTAUDIO_LIB" "$STAGE/libportaudio.2.dylib"
cp "$PORTAUDIO_LICENSE" "$STAGE/PORTAUDIO-LICENSE.txt"
cmp -s "$PORTAUDIO_LIB" "$STAGE/libportaudio.2.dylib"
verify_signature "$STAGE/libportaudio.2.dylib"

if otool -L "$STAGE/libportaudio.2.dylib" | awk 'NR > 2 { print $1 }' \
  | grep -E '^/opt/homebrew/|^/usr/local/'; then
  printf 'PortAudio library retains a non-system dependency path.\n' >&2
  exit 1
fi
mv "$STAGE" "$TARGET"
printf 'Core Audio dependencies staged in %s\n' "$TARGET"
printf 'Review licenses and codesign the exported app after editing Info.plist.\n'
