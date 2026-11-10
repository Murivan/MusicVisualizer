# Apple Silicon Core Audio handoff

## Purpose and starting point

This handoff is for an agent continuing MusicVisualizer development on an
Apple Silicon Mac. The user wants lower-latency live audio input, preferably
below 25 ms and definitely below 50 ms **end to end**, without an external
helper process. WASAPI is available on Windows; ASIO is useful but optional.
The next agreed direction is to evaluate Core Audio on macOS through
PortAudio, starting with a small spike before integrating it into the main
application.

The original Windows machine was on branch `dev` at commit `c3991dd`
(`Portaudio for Windows first implementation`) when this handoff was written.
Confirm the actual checkout and working-tree state on both machines; do not
assume a clone contains uncommitted changes or ignored local dependencies.
Do not overwrite existing user changes.

## Existing implementation

- [Visualizer/Visualizer.pde](Visualizer/Visualizer.pde) is the Processing
  sketch. Minim provides file playback, FFT and Java Sound live input.
- [Visualizer/audio-src/WasapiInput.java](Visualizer/audio-src/WasapiInput.java)
  implements JNA/PortAudio live capture. It enumerates PortAudio host APIs
  and devices, supports WASAPI shared/exclusive on Windows, and deliberately
  rejects non-Windows platforms today.
- [Visualizer/audio-src/RollingAudioBuffer.java](Visualizer/audio-src/RollingAudioBuffer.java)
  maintains a synchronized rolling mono FFT window. Capture reads and FFT
  window sizes are independent; up to two input channels are averaged.
- `WasapiCapture` in the main sketch loads the backend jar, JNA and
  `portaudio.dll` from `data/wasapi` through a separate class loader. Both
  names and paths are Windows-specific. The existing chooser groups devices
  by driver/host API and provides WASAPI mode and power-of-two buffer
  dropdowns. The PortAudio capture dropdown is disabled for Java Sound;
  mode selection is effective only for WASAPI. Changes apply per run.
- [Visualizer/setup-wasapi.ps1](Visualizer/setup-wasapi.ps1) compiles and
  stages the Windows backend. [Visualizer/export-windows.ps1](Visualizer/export-windows.ps1)
  produces and checks a new Windows export. The generated `data/wasapi`
  directory is ignored by Git; do not assume it travels with the repository.
- [Spikes/PortAudioSpike](Spikes/PortAudioSpike) is the earlier Windows spike.
  Its native binaries and setup are Windows-specific; use it for design
  reference, not as a ready-made macOS solution.
- [build/build_macos.sh](build/build_macos.sh) builds the **separate Image
  Analyzer**, not the visualizer. It is not a macOS visualizer export script.

The user's current file defaults are in
[Visualizer/data/parameters.txt](Visualizer/data/parameters.txt). The
`liveInputBackend=wasapi` setting controls only the initial preference; it
must not prevent the user from selecting other available drivers. Preserve
existing defaults and behavior unless the user approves a change.

The Windows implementation has been built and tested locally, including
shared WASAPI and ASIO capture and the startup chooser. The user previously
reported that the application worked. Windows exclusive WASAPI worked with
some hardware but stalled or performed poorly on another device; do not
remove or silently disable it because of device-specific issues. No physical
end-to-end latency target has been verified, and ASIO redistribution rights
have not been established.

## First phase: Mac spike

1. Verify the checkout, `uname -m`, macOS version, Processing version and
   Processing JVM architecture on the Mac. Install Minim through Processing
   if it is missing. Identify the built-in microphone and any external
   interface available for testing; use the actual Processing JVM where
   practical.
2. Obtain or build a **trusted, compatible arm64 PortAudio dynamic library
   with Core Audio support**, plus a JNA jar with working macOS arm64 native
   support. Record versions, sources, build options, architecture and license
   information. Check the actual binary and dependent libraries using
   macOS tools such as `file`, `lipo` and `otool -L`. A Homebrew or locally
   built library is useful for a spike but is not automatically a portable
   redistributable bundle. Do not copy Windows binaries as macOS dependencies.
3. Implement a small, isolated in-process spike that lists host APIs and input
   devices, selects a Core Audio input and captures audio. Exercise the
   existing blocking-read/rolling-buffer approach, independent read and FFT
   sizes, proper cleanup, and an actual non-silent input signal. Report
   sample rate, channel count, read size, reported input latency, block
   progress and overflows. Do not treat successful enumeration or stream open
   alone as successful capture.
4. Investigate microphone authorization in the actual context used for the
   test. Processing, a terminal-launched JVM and an exported `.app` may have
   different responsible application identities and permission behavior.
   Record granted and denied outcomes and which process appears in macOS
   privacy settings; don't assume that launching from a terminal validates
   the exported app.
5. Test at least the built-in input and the available external interface if
   possible. Compare practical capture sizes, run sustained capture under
   representative load, and report stalls, errors and overflows. If blocking
   capture is unsuitable, investigate a callback-based alternative before
   deciding on integration; do not claim a particular design meets latency
   targets without measurements.

Report the spike results and any blockers before treating Core Audio support
as proven. The user has an Apple Silicon machine; whether this agent can
directly access it must be established in the new session.

## Integration after a successful spike

- Generalize the existing backend and loader instead of duplicating the audio
  pipeline. Keep Windows WASAPI-specific structures and exclusive handling
  conditional on Windows/WASAPI. Core Audio must not inherit a misleading
  shared/exclusive setting or silently fall back to another device or driver.
- Audit the **PortAudio C ABI on each platform** before reusing the JNA
  declarations: Windows x64 and macOS arm64 differ in C `long` size and may
  differ in structure layout/alignment. Verify argument widths, field
  offsets, sizes and calling conventions against the actual PortAudio headers
  and binary; add native-layout tests for each supported platform.
- Select native artifacts by OS and architecture, and provide clear errors
  for missing, incompatible or unloadable libraries. Avoid requiring a
  system-installed library in the distributable. Retain the Java Sound
  option if PortAudio is unavailable, without silently changing a requested
  input. Preserve device grouping, per-run buffer selections, file playback,
  FFT behavior, capture diagnostics and explicit error reporting.
- Supply a reproducible macOS setup and non-destructive export workflow
  analogous in intent to the Windows scripts. Verify Processing's actual
  macOS export layout, arm64 JVM, app resources, native dependencies,
  `Info.plist` microphone usage description and permission prompt in the
  exported application. Validate code signing and hardened-runtime
  requirements as applicable; modifying a signed app may invalidate its
  signature. Signing, notarization, redistribution rights and clean-machine
  operation must be verified, not assumed.
- Update [README.md](README.md) with setup, limitations, licensing and
  tested steps. Do not conflate Core Audio support with WASAPI or claim that
  macOS supports Windows exclusive mode.

## Verification and acceptance

- Run existing rolling-buffer, FFT/audio-analysis and chooser tests, adapting
  names or class paths if the backend is generalized. Cover Core Audio
  enumeration and selection; exact buffer dropdown values and defaults;
  Java Sound and file playback; cancellation; missing dependencies; denied
  permissions; error/stall handling; stream shutdown; and actual audio data.
  The existing
  [PortAudioInputTest.java](Visualizer/audio-src/PortAudioInputTest.java)
  tests the sketch loader and buffer sizes but currently depends on
  Windows-named classes and waits only five seconds: adapt or extend it
  rather than treating it as a complete sustained or audible-signal test.
- Run the exported macOS app interactively on the Apple Silicon Mac, then on
  a separate clean machine when available, including audio input, controls,
  shaders and file playback. Record macOS, hardware, JVM and dependency
  versions, permissions and exact buffer settings.
- Re-run Windows export, chooser, Minim/file playback, shared and exclusive
  WASAPI, and ASIO where licensed hardware and libraries are available.
  If Windows is unavailable from the Mac, explicitly report regression
  verification as outstanding rather than asserting it passed.
- Measure **audio-to-display** latency using the procedure in
  [README.md](README.md#measuring-audio-to-display-latency), including
  misses and uncertainty. Compare representative Minim and Core Audio
  configurations; PortAudio's reported input latency, capture block duration
  and FFT-window duration are not interchangeable with end-to-end latency.
  The existing [Visualizer/analyze-latency.ps1](Visualizer/analyze-latency.ps1)
  is PowerShell; check that PowerShell is available on the Mac or run the
  analysis on Windows. Do not claim either latency target is met until the
  measurement supports it.

## Related but separate work

The analyzer's Apple Silicon bundle and Windows clean-machine bundle still
need testing. That is separate from Core Audio and should not block an audio
spike. There is no request to replace Minim file playback, implement a helper
process, or resolve ASIO redistribution as part of the Mac spike.
