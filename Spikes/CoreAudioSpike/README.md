# macOS Core Audio spike

This isolated probe checks the macOS arm64 PortAudio/JNA ABI, lists PortAudio
host APIs and input devices, and exercises blocking capture with the existing
`RollingAudioBuffer`. It does not modify or replace the Windows backend.

## Local dependencies verified

| Dependency | Version / architecture | Source and license |
|---|---|---|
| PortAudio | 19.7.0 (runtime: V19.7.0-devel, revision `147dd722548358763a8b649b3e4b41dfffbcfbb6`), arm64 | Homebrew Core formula, bottle at `/opt/homebrew/opt/portaudio`; upstream source archive `https://files.portaudio.com/archives/pa_stable_v190700_20210406.tgz`, SHA-256 `47efbf42c77c19a05d22e627d42873e991ec0c1357219c0d74ce6a2948cb2def`; MIT |
| JNA | 5.19.1, embedded `darwin-aarch64` native library | Bundled with Processing 4.5.7; JNA license `Apache-2.0 OR LGPL-2.1-or-later` |
| Java | Processing-bundled Eclipse Temurin 17.0.20.1, aarch64 | `/Applications/Processing.app/Contents/app/resources/jdk` |

The Homebrew PortAudio formula configures `--enable-mac-universal=no` and
`--enable-cxx` plus Homebrew's standard configure arguments. The installed
`libportaudio.2.dylib` is arm64-only and links CoreAudio, AudioToolbox,
AudioUnit, CoreFoundation and system libraries. This local Homebrew library is
for development only; it is not a portable app bundle or a redistribution
decision.

The `--abi` probe passed on the Processing JVM: pointers and C `long` are
8 bytes, and JNA reports the expected LP64 sizes and offsets for the PortAudio
host, device, stream-parameter, and stream-info structures. `--list` reports
the Core Audio host API (type 5), plus the MacBook Pro microphone (44.1 kHz,
1 channel) and M4 (44.1 kHz, up to 8 channels). The listed default latency is
the device's PortAudio default, not a measured live stream latency.

## Run

The defaults below target the verified local installation. Override
`PROCESSING_JAVA_HOME`, `JNA_JAR`, or `PORTAUDIO_LIB` to test other locations.
The script compiles into a temporary directory and removes it when finished.

```sh
./Spikes/CoreAudioSpike/run-macos.sh --abi
./Spikes/CoreAudioSpike/run-macos.sh --list
```

For live capture, make sure microphone access is allowed for the responsible
app (for example Terminal or VS Code, depending on how the command is
launched). macOS may display a microphone permission prompt. Speak or make a
brief sound during capture so the signal statistics can distinguish actual
audio from silence:

```sh
./Spikes/CoreAudioSpike/run-macos.sh --capture "MacBook Pro Microphone" 10 128 512
./Spikes/CoreAudioSpike/run-macos.sh --capture "M4" 10 128 512
```

Capture arguments are a unique Core Audio input-name fragment, duration in
seconds, capture frames per blocking read, and rolling FFT-window frames.
The probe reports actual stream sample rate, channels, PortAudio input latency,
block count and cadence, overflow count, and signal/window RMS and peak. A
successful device listing or stream open alone is not evidence of capture.

## Initial live-capture results

Both devices completed 10-second captures on the Processing-bundled arm64 JVM
at 64, 128, and 256 read frames, with a 512-frame rolling window:

| Input | Read frames (block time) | Reported input latency | Blocks / mean interval | Overflows | Signal RMS / peak |
|---|---:|---:|---:|---:|---:|
| MacBook Pro Microphone | 64 (1.45 ms) | 126.12 ms | 6891 / 1.45 ms | 0 | 0.001561 / 0.011905 |
| MacBook Pro Microphone | 128 (2.90 ms) | 127.57 ms | 3440 / 2.90 ms | 0 | 0.003267 / 0.085301 |
| MacBook Pro Microphone | 256 (5.80 ms) | 130.48 ms | 1722 / 5.81 ms | 0 | 0.003085 / 0.050519 |
| MOTU M4 (first two channels) | 64 (1.45 ms) | 57.14 ms | 6889 / 1.45 ms | 0 | 0.000678 / 0.002099 |
| MOTU M4 (first two channels) | 128 (2.90 ms) | 58.59 ms | 3445 / 2.90 ms | 0 | 0.070216 / 1.000000 |
| MOTU M4 (first two channels) | 256 (5.80 ms) | 58.59 ms | 1721 / 5.81 ms | 0 | 0.000680 / 0.002144 |

Non-silent activity was detected on both inputs. The M4 peak reached full
scale; confirm its input gain/signal source before treating those levels as
representative. PortAudio's reported input latency is much higher than the
read-block duration and is not end-to-end audio-to-display latency. These
short, separate runs do not establish that the latency goal is met or
characterize sustained-load behavior. Reported input latency changed little
with read size and remained high compared with block duration.

Capture succeeded (microphone access was therefore granted in the command-run
context) without a permission prompt appearing during these runs. The macOS
privacy-settings responsible app identity has not been confirmed. Denial
behavior, other launch contexts, and the exported-app permission prompt
remain untested.
