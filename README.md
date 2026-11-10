# Music Visualizer

A Processing sketch that visualizes an audio file or live audio input over a
window-image composition. The visualizer renders the output fullscreen and
opens a separate, resizable control window for live tuning.

## Features

- Audio-file or live-input selection at startup.
- FFT band analysis mapped to configurable coloured masks.
- Independent solid and bloom layers with additive blending.
- Fullscreen output display selection.
- Touch-friendly live controls with sliders, editable numeric values, mode
  buttons, and Area-style buttons.
- Three reveal modes: `FULL`, `SPOTLIGHT`, and `AREA`.

## Project layout

```text
Visualizer/
  Visualizer.pde                 Main Processing sketch
  data/
    parameters.txt               Startup configuration
    window_base.png              Base image
    mask_*_solid.png             Colour-mask solid layers
    mask_*_bloom.png             Colour-mask bloom layers
    mask_area_ids.png            Per-tile IDs for AREA mode
    spotlight_reveal.glsl        Coloured-mask Spotlight shader
    spotlight_base_reveal.glsl   Base-image Spotlight shader
    area_reveal.glsl             AREA tile shader
ImageAnalyzer.ipynb              Optional image/mask analysis notebook (Jupyter)
ImageAnalyzer_App.ipynb          Same analysis as a Voila app (used by the standalone bundle)
voila.json                       Voila settings (large uploads, hidden code)
bundle/                          Launchers, requirements and user guide for the standalone bundle
build/                           Bundle build scripts (Windows, macOS)
```

## Standalone Image Analyzer bundle

Users without Python can run the analyzer from a zip containing a private
Python runtime. Build it on the target OS (runtimes cannot be cross-built):

- **Windows:** `powershell -ExecutionPolicy Bypass -File build\build_windows.ps1`
  produces `dist\ImageAnalyzer-windows-x64.zip`.
- **macOS (Apple Silicon):** `bash build/build_macos.sh` produces
  `dist/ImageAnalyzer-macos-arm64.zip`.

Users unzip and double-click `Start.bat` / `Start.command`; results go to the
`output` folder next to the launcher unless another folder is chosen. To run
from source instead: `pip install -r bundle/requirements.txt`, then
`python -m voila ImageAnalyzer_App.ipynb`.

## Requirements and startup

1. Install [Processing](https://processing.org/download/) with the Java mode.
2. Install the **Minim** library through Processing's Contribution Manager.
3. Open [`Visualizer/Visualizer.pde`](./Visualizer/Visualizer.pde) in
   Processing.
4. Run the sketch.
5. When fullscreen output is enabled, select the target display in the startup
   dialog.
6. Select either an audio file or an audio input device.

The sketch loads all visual assets and [`parameters.txt`](./Visualizer/data/parameters.txt)
from the `data` directory.

## Windows and displays

When `useFullScreen=true`, the sketch lists all displays before creating the
visualization surface. Each entry includes the operating-system display ID,
resolution, refresh rate when reported, colour depth when reported, bounds,
and fullscreen support.

`visualizationDisplay` in `parameters.txt` is a zero-based default selection
for this dialog:

```properties
visualizationDisplay=0
```

The visualization is a Processing `P2D` surface because it uses GLSL shaders.
Windows uses the sketch's existing Java UI-scale configuration to improve
compatibility with scaled displays.

## Runtime windows

The application has two Processing windows:

```text
audio source
    |
    v
main P2D visualizer ------------------> fullscreen output display
    |
    +-------------------------------> ControlsWindow
                                        sliders, buttons, diagnostics
```

The controls window can be resized. Its layout is recalculated from the
current width and height. It contains:

- `FULL`, `SPOTLIGHT`, and `AREA` reveal-mode buttons.
- **Mask Intensity:** the **Base Image** slider and a solid and a bloom slider
  for each active colour mask.
- **Audio Response:** a vertical sensitivity fader and live energy meter for
  each active mask, plus the **Audio Sensitivity** slider, FFT mapping, gain
  and smoothing controls, and the colour/band mapping text box. EQ faders start
  at 1.0×, range from 0× to 5×, and double-clicking one resets it to 1.0×.
  The energy meter shows pre-EQ band magnitude relative to a full-scale,
  bin-centred sine-wave FFT bin; it has a -60 dB display floor and is
  independent of Audio Sensitivity and the band multiplier. It is not an
  acoustic SPL reading, and multi-bin band levels can exceed 0 dB. A second
  orange meter beside it (same dB scale) shows the same level after the total
  gain: `audioBandMultiplier` × Audio Sensitivity × the band's EQ fader. That
  gain is applied to the band energy that drives the mask intensity.
- **Spotlight:** radius, feather and motion sliders, plus toggle buttons.
- **Area:** energy and cycle sliders, plus the tile-style buttons.
- Runtime diagnostics and FFT band labels.

See [Where each setting lives](#where-each-setting-lives) for which settings
come from `parameters.txt`, which can be changed live, and which exist in only
one of the two places.

Tap or click a horizontal slider's value box to enter a precise numeric value.
Type a number and press **Enter** to apply it; press **Escape** to cancel.
Double-click (or double-tap) a horizontal slider track to reset it to its
startup value. Double-click an EQ fader to reset that band's sensitivity to
1.0×.

## Audio and FFT mapping

The sketch uses Minim to play a selected audio file. For live input, the
startup chooser lists Java Sound (Minim) and the input drivers detected by
the optional PortAudio backend. Each frame:

1. The source buffer is sent to the FFT.
2. Overall audio level drives base-image brightness and reveal-mode energy.
3. FFT bins are divided among configured colour masks.
4. Each band's energy is smoothed using attack and release time constants; the
   Audio Response EQ shows pre-EQ band magnitude on a relative logarithmic
   scale. It combines the band's FFT magnitudes as a root-sum-square, normalized
   to the magnitude of a full-scale, bin-centred sine-wave FFT bin, with a
   -60 dB display floor. It applies an independent 0×–5× sensitivity to the
   corresponding mask.
5. Solid and bloom mask layers are composited with additive blending.

### PortAudio live input (Windows x64)

File playback remains on Minim. To use PortAudio drivers, obtain a compatible
JNA jar and a 64-bit Windows PortAudio DLL. The supplied DLL determines which
host APIs are available: a non-ASIO build cannot list ASIO devices. An
ASIO-enabled build is needed for ASIO; check the applicable Steinberg and
binary redistribution licenses before distributing it. The local tests used
Processing's JNA 5.19.1 and the PortAudio DLL from the `sounddevice` 0.5.6 Windows wheel.
For example, the spike setup supplies
`Spikes\PortAudioSpike\jna-lib\jna.jar` and
`Spikes\PortAudioSpike\data\libportaudio64bit.dll`. Review the dependencies'
licenses and provenance before redistribution. With Processing's bundled JDK:

```powershell
powershell -ExecutionPolicy Bypass -File Visualizer\setup-wasapi.ps1 `
  -JnaJar Spikes\PortAudioSpike\jna-lib\jna.jar `
  -PortAudioDll Spikes\PortAudioSpike\data\libportaudio64bit.dll
```

For local ASIO testing, use an ASIO-enabled DLL instead, such as the spike's
`libportaudio64bit-asio.dll`. Re-run the setup script and re-export the
application after changing the DLL. Supplying the DLL does not resolve its
licensing or redistribution requirements.

When selecting live input, use the **Audio driver** dropdown and then select an
input device. It lists all input-capable host APIs exposed by the supplied
PortAudio DLL, plus Java Sound (Minim). A device can appear under multiple
drivers; support and latency are device-dependent. If PortAudio cannot load,
the dialog reports why and still offers Java Sound when available. ASIO is
shown only if the DLL supports it and a corresponding input driver is installed.

The **Shared / Exclusive** dropdown applies to WASAPI only. Select the driver,
device and mode before opening the input; to change them later, restart the
application. The `liveInputBackend` parameter sets only the initial driver
selection (`minim` or `wasapi`); no parameter edit is required to select
another driver. The `wasapiMode` parameter controls the dropdown's
initial selection (shared by default); a selection in the dialog applies only
to the current run and does not change the file. Exclusive mode
can prevent other applications from using the input and may fail, stall, or
perform poorly with some devices or drivers. Test each device; an opening
failure or capture error is reported without silently switching modes. Choose
Shared on the next launch if exclusive mode is unsuitable. `captureBufferSize` controls the PortAudio read size in
frames (default 256); `audioBufferSize` remains the power-of-two FFT window.
The startup dropdowns offer powers of two from 32 to 8192 capture frames and
32 to 65536 audio samples. If an existing `captureBufferSize` is not a power
of two, select an available capture size in the dialog before starting PortAudio.
Both can be changed in the live-input startup dialog; the parameter values are
the initial defaults, and changes apply only to the current run. The capture
size field is disabled for Java Sound, which uses the audio / FFT buffer size.
File playback continues to use `audioBufferSize` from the parameters file.
The two channels of stereo capture are averaged, as with Minim's mix buffer.
The startup error dialog reports missing dependencies or a stream-open failure;
there is no silent fallback to another backend. If polling shows no complete
audio block for at least three seconds (or four block periods, whichever is
longer), the control window reports a stall rather than continuing to show
stale audio. A native call that itself hangs is not covered by this check.
Run `setup-wasapi.ps1` again after updating the backend source.

The generated `data\wasapi` directory must accompany the Windows sketch or
export; Processing exports its `data` directory. The control panel reports
PortAudio's input latency and capture timing, not end-to-end audio-to-display
latency. FFT windowing, smoothing, graphics and display delay remain
additional factors.

### PortAudio live input (macOS arm64)

The shared PortAudio backend also supports Core Audio on macOS arm64.
File playback remains on Minim. WASAPI exclusive mode is Windows-only; the
mode selector is disabled for Core Audio and other non-WASAPI hosts.

With Homebrew PortAudio installed and Processing 4's bundled JDK/JNA
available, stage and validate the native dependencies:

```sh
bash Visualizer/setup-coreaudio.sh
```

By default the script uses Processing's bundled JDK and JNA 5.19.1 plus
Homebrew's arm64 PortAudio 19.7.0. Override `PROCESSING_JAVA_HOME`, `JNA_JAR`,
``PORTAUDIO_LIB`, or `PORTAUDIO_LICENSE` if they are installed elsewhere. The
script verifies arm64/Core Audio support and JNA's arm64 native payload,
preserves and validates any existing native code signature, compiles the
shared backend, runs ABI and rolling-buffer tests, copies license notices,
and stages files in `Visualizer/data/coreaudio/`. It refuses to overwrite an
existing staged directory. The Homebrew dylib is copied without rewriting its
install name because doing so invalidates its code signature. PortAudio's
remaining dependencies are system frameworks. Review both licenses and
redistribution requirements before distributing any export.

Run a real-input stability check with microphone access enabled:

```sh
bash Visualizer/test-coreaudio.sh "Core Audio" "M4" 60 128 512
```

Arguments are host API fragment, unique input-device fragment, duration in
seconds, capture frames per read and rolling FFT-window size. The test
requires finite, non-silent samples, reports blocks/latency/overflows, and
fails on capture errors, stalls or any overflows. For built-in microphone
testing, replace `M4` with `MacBook Pro Microphone`. macOS microphone privacy
authorization depends on the launch context; allow access for the app
responsible for the JVM. The command-line test does not prove permissions in
the exported app.

To export to a new directory:

```sh
bash Visualizer/export-macos.sh /path/to/new-export
```

The export script checks the app executable architecture, copied dependencies,
and `NSMicrophoneUsageDescription`, and refuses to overwrite an existing
destination. Editing `Info.plist` can invalidate app signing, so sign and
notarize the finished app afterward as required. Processing 4.5.7 currently
fails arm64 CLI export with `NoSuchElementException` in
`JavaBuild.exportApplication` on this Mac; the script detects the incomplete
bundle and leaves the partial output for inspection. See
[Processing issue #1193](https://github.com/processing/processing4/issues/1193).
Until Processing export works, app-bundle layout, privacy prompt, signing,
clean-machine operation and visualizer GUI behavior remain unverified.

For a repeatable capture-stability check (not end-to-end latency), run for
example:

```powershell
powershell -ExecutionPolicy Bypass -File Visualizer\test-wasapi.ps1 `
  -DeviceName "part of device name" -DurationSeconds 60 -CaptureFrames 256
```

The name fragment must uniquely identify a WASAPI input. The test reports
sample rate, host-reported input latency, block interval and overflow count;
it fails for capture errors, a stall or any overflow. Repeat under typical
system load and with the buffer sizes to be compared. This test captures
audio without running the visualization, so it does not replace testing the
complete application under load.

The test tool also accepts `-Mode exclusive` or `-Mode exclusive-polling`.
The main visualizer's exclusive mode uses the non-polling option; polling is
for driver investigation only. For example, on one MOTU M Series input it reported about 743 ms
and stalled after a short burst in both modes; the cause remains unconfirmed.
The same input ran in shared mode. Do not treat successful opening or a
reported latency as proof of sustained capture or end-to-end performance.

#### Windows export

After running the WASAPI setup, export to a **new** directory:

```powershell
powershell -ExecutionPolicy Bypass -File Visualizer\export-windows.ps1 `
  -OutputPath C:\Exports\MusicVisualizer-test
```

The parent directory must already exist. The script refuses to overwrite an
existing destination, checks the WASAPI dependencies when enabled, verifies
the exported launcher and data-file hashes, and records the dependency hashes
in `wasapi-dependencies.json`. Use `-ProcessingExe` if Processing is installed
elsewhere. A failed export may leave a partial directory; inspect it before
removing it. Verify the exported app on another Windows x64 machine without
Processing or Python installed, including file playback, Minim live input and
WASAPI live input. The manifest identifies binaries; it does not verify their
origin or grant redistribution rights.

#### Measuring audio-to-display latency

The reported WASAPI input latency is not an end-to-end measurement. Use a
high-speed camera (preferably 240 fps or faster) to record both a stimulus
indicator and the actual visualization display in the same shot:

1. Feed a repeatable, short electrical audio pulse to the selected input and
   simultaneously trigger an LED visible to the camera. Characterize any
   delay between the LED and the actual signal at the input; avoid using
   the computer's audio output as an unmeasured reference.
2. Record the display and LED together. Use a stable, visible visualization
   response, fixed camera exposure, and note the backend, device, sample
   rate, `captureBufferSize`, `audioBufferSize`, FPS, attack/release settings
   and display. Allow the application to warm up.
3. For each of at least 20 spaced pulses, record the first video frame where
   the LED changes and the first frame where the display visibly responds.
   Include missed responses in your report; do not silently omit them. If
   the indicator and screen are at different vertical positions, account
   for camera rolling-shutter and display scanout effects.
4. Save the observed pairs as CSV, with a header and integer frame numbers:

   ```text
   stimulusFrame,responseFrame
   120,125
   360,364
   ```

5. Run, for example:

   ```powershell
   powershell -ExecutionPolicy Bypass -File Visualizer\analyze-latency.ps1 `
     -CsvPath C:\Measurements\latency.csv -FramesPerSecond 240
   ```

The script reports min, mean, nearest-rank p95 and max, and compares p95 and
max to 25 ms and 50 ms with a one-frame quantization allowance. Those comparisons
are **not certification**: source/LED timing, rolling shutter, scanout and
detecting the first visible response add unquantified errors. At 240 fps one
frame is about 4.17 ms; use a faster camera for tighter uncertainty. Repeat
the same procedure for Minim and WASAPI, and report missed responses and
capture overflows alongside the numbers.

Each solid or bloom mask is composited using at most **10 image draws** per frame.
This limits GPU work when audio multipliers are high. Intensities above 10 are
clamped for rendering, so increasing `audioBandMultiplier`,
`audioBloomMultiplier`, or a mask's manual intensity beyond that effective
level does not add further brightness or draw passes.

### Colour-band mapping

`colorBandMapping` selects both the active masks and their low-to-high FFT
band order:

```properties
colorBandMapping=BCROY
```

| Initial | Mask |
|---|---|
| `B` | Blue |
| `C` | Cyan |
| `R` | Red |
| `O` | Orange |
| `Y` | Yellow |
| `G` | Green |
| `M` | Magenta |

Initials must be unique. The mapping is case-insensitive, and whitespace is
ignored. For example, `MBCGYRO` uses all masks while assigning magenta to the
lowest configured FFT band.

## Reveal modes

### FULL

The base image and every configured mask use their normal audio-reactive
intensities. No spatial or tile-level reveal shader is applied.

### SPOTLIGHT

Each coloured mask is clipped by a moving radial spotlight. The
[`spotlight_reveal.glsl`](./Visualizer/data/spotlight_reveal.glsl) shader
receives a centre, radius, edge feather, and image aspect ratio.

The base image uses
[`spotlight_base_reveal.glsl`](./Visualizer/data/spotlight_base_reveal.glsl).
At low energy, it shows a narrow outer rim; as energy rises, visibility moves
inward toward the centre. The squared energy curve keeps the quiet-signal rim
thin.

Spotlight position can be shared by all masks or independently moved per mask.
Each position follows a smoothed Brownian-motion target.

### AREA

AREA mode chooses whole tiles using audio energy, then renders the selected
tile with one of three styles:

| Style | Behavior |
|---|---|
| `WHOLE_TILE` | Active tiles are completely visible. |
| `CENTER_GLOW` | Active tiles reveal outward from their centres. |
| `TRAIL` | Active tiles contain a Brownian-like moving particle and fading trail. |

Set the startup style with:

```properties
areaRevealStyle=WHOLE_TILE
```

The style can also be changed live in the **AREA REVEAL** controls section.

## AREA pipeline

```text
audio level
    |
    v
smoothed Area energy
    |
    v
area_reveal.glsl per solid/bloom mask
    |
    v
additive coloured tile output
```

For each mask, the sketch passes the Area shader:

- `audioEnergy`: the smoothed, Area-scaled audio level.
- `time` and `cycleDuration`: the tile activation-cycle clock.
- `seedOffset`: a per-mask offset when independent positions are enabled.
- `areaRevealStyle`: whole-tile, centre-glow, or trail selection.
- `trailProgress`: energy-speed-controlled history for Trail mode.

### Tile ID mask

[`mask_area_ids.png`](./Visualizer/data/mask_area_ids.png) defines tile
boundaries. Pixels in one tile share the same non-black RGB value; black
(`0,0,0`) represents background and is always transparent.

```text
black background       tile A                 tile B
   0,0,0           12,34,56              98,76,54
      .              +-------+            +-----+
      .              |       |            |     |
      .              +-------+            +-----+
```

The shader reconstructs the RGB bytes, hashes the tile ID with `seedOffset`,
and gives the tile a stable animation phase. A tile is selected when its
phase-shifted cycle value is below `audioEnergy`; low energy selects fewer
tiles, while high energy selects more.

### Runtime tile geometry

At startup, `createAreaCenterMap()` derives an internal map from the ID mask
for `CENTER_GLOW` and `TRAIL`:

```text
areaCenterMap channels

R = tile centre X, normalized to the image width
G = tile centre Y, normalized to the image height
B = distance from the centre to the farthest tile pixel
```

This lets the shader calculate each fragment's local tile position while the
ID mask continues to enforce real tile boundaries.

### Trail motion

Trail mode generates a smooth random walk for each active tile. The main
sketch advances `trailProgress` using a speed interpolated from quiet to loud
audio energy. The shader samples the current and seven prior positions:

```text
low energy:  slow particle + short dim history
high energy: fast particle + long bright history
```

The trail is procedural rather than a retained framebuffer, so it remains
deterministic, GPU-friendly, and clipped to each tile.

## Configuration

All startup settings are in
[`Visualizer/data/parameters.txt`](./Visualizer/data/parameters.txt). Changes
to this file require a restart. The controls window changes supported
visualization settings only for the running session; those edits are never
written back to the file.

### Where each setting lives

| Group | Settings | `parameters.txt` | Controls window |
|---|---|---|---|
| **File only** (need a restart) | `useFullScreen`, `canvasWidth`, `canvasHeight`, `visualizationDisplay`, `controlsWindowWidth`, `controlsWindowHeight`, `fps` | Yes | No |
| **File sets default, startup dialog can change it** | `liveInputBackend`, `wasapiMode`, `captureBufferSize`, `audioBufferSize` for live input; `audioBufferSize` for file playback comes only from the file | Yes | No |
| **File sets the startup value, controls change it live** | **Audio Response** sliders: `initialAudioSensitivity` (**Audio Sensitivity**), `maxFftFrequency`, `frequencyMappingExponent`, `bandOverlap`, `audioBandMultiplier`, `audioBloomMultiplier`, `audioBaseIntensityScale`, `baseImageSilenceFloor` (**Silence Floor**), `audioAttackTimeMs`, `audioReleaseTimeMs`. **Spotlight** sliders: `spotlightEnergyMultiplier`, `spotlightMinimumRadius`, `spotlightMaximumRadius`, `spotlightEdgeFeatherProportion`, `spotlightMotionUpdateIntervalMs`, `spotlightBrownianStep`, `spotlightMotionSmoothingTimeMs`. **Area** sliders: `areaEnergyMultiplier`, `areaCycleDurationSeconds` | Yes | Yes, one slider each |
| **File sets the startup value, controls change it live** (non-slider) | `colorBandMapping` (text box in **Audio Response**), `startRevealMode` (mode buttons or `M`), `spotlightIndependentMaskPositions` and `spotlightKeepCirclesInsideImage` (**Spotlight** buttons), `areaRevealStyle` (**Area** buttons) | Yes | Yes |
| **Controls window only** | **Base Image** slider and the per-colour **Solid** and **Bloom** sliders in **Mask Intensity**; per-mask **Audio Response** EQ sensitivities | No; the Base Image slider starts at `baseImageSilenceFloor`, colour sliders start at 0, and EQ sensitivities start at 1.0× | Yes |

A slider's startup value is also what a double-click on it resets to.

The file uses `name=value` entries; lines beginning with `#` are comments.
Keep each setting on its own line and do not quote values. Boolean values must
be `true` or `false`. If a setting is omitted, its built-in default is used.
Numeric values outside the supported range are clamped; values that cannot be
parsed are ignored and reported in the Processing console. `audioBufferSize`
has an additional power-of-two requirement.

The ranges below describe the values accepted at startup, not recommended
targets. The current values in `parameters.txt` are a useful starting point.
The tables mark each setting with where it can be changed (see the table
above).

### Window and controls

| Setting | Accepted values | What it changes |
|---|---|---|
| `useFullScreen` | `true` or `false` | `true` opens the visualizer fullscreen and shows the display chooser. `false` creates a window using `canvasWidth` and `canvasHeight`. |
| `canvasWidth` | 320-16384 pixels | Width of the visualization window when fullscreen is off. |
| `canvasHeight` | 240-16384 pixels | Height of the visualization window when fullscreen is off. |
| `visualizationDisplay` | 0-15 | Zero-based default selection in the fullscreen display chooser. It is a default, not a forced selection; the chooser still appears. |
| `controlsWindowWidth` | 320-4096 pixels | Initial width of the separate controls window. It can be resized after launch. |
| `controlsWindowHeight` | 240-4096 pixels | Initial height of the separate controls window. |
| `fps` | 1-240 | Target sketch frame rate. Actual performance can be lower depending on the display, shaders, and machine. |

### Audio response

| Setting | Accepted values | What it changes |
|---|---|---|
| `liveInputBackend` | `minim`, `portaudio`, or legacy `wasapi` | Initial driver preference in the live-input chooser. Other available drivers can be selected there. PortAudio requires platform setup on Windows x64 or macOS arm64. File playback always uses Minim. |
| `wasapiMode` | `shared` or `exclusive` | Default WASAPI mode shown in the startup dialog; applies only to WASAPI and can be changed for the current run. Ignored for other drivers and file playback. Defaults to `shared`. |
| `captureBufferSize` | 32-8192 frames | Default PortAudio capture read size; live-input startup choices are powers of two. A configured non-power-of-two requires an explicit startup selection. Independent of the FFT window and not used by Minim. |
| `audioBufferSize` | Power of two from 32-65536 | Default FFT-window size; can be changed at live-input startup. Also the Minim input buffer size and the file-playback buffer size. Larger windows provide finer frequency spacing but respond less immediately. |
| `colorBandMapping` | Unique initials from `B`, `C`, `R`, `O`, `Y`, `G`, `M` | Chooses which colour masks are active and assigns them from the lowest to highest FFT band, left to right. For example, `BCROY` assigns blue to the lowest band and yellow to the highest. A shorter mapping uses fewer masks; all masks are preloaded. Editable in **Controls > Audio Response** by entering initials and pressing Enter. |
| `maxFftFrequency` | 1-192000 Hz | Upper frequency limit analyzed for the colour bands. Lower it to focus the mapping on bass or midrange. Frequencies available also depend on the selected audio source and its sample rate. |
| `frequencyMappingExponent` | 0.1-20 | Shapes how the FFT range is divided among the ordered masks. `1` is linear; larger values pack more band boundaries into the low-frequency end, giving lower frequencies more individual colour bands. Smaller values shift more band resolution toward higher frequencies. |
| `bandOverlap` | 0-0.95 | Controls how much adjacent frequency bands share FFT bins. `0` keeps bands separate. Higher values widen each band by the given fraction of its width, split across its two edges; this can make neighbouring colours respond to more similar sounds. |
| `audioBandMultiplier` | 0.01-100 | Overall gain applied to each FFT band's response before it is added to that mask's solid intensity. Raise it if the masks barely react; lower it if they hit their brightness limit too easily. |
| `audioBloomMultiplier` | 0-100 | Scales the audio-driven response of the bloom layer relative to the solid layer. `0` disables audio-driven bloom while leaving manual bloom intensity available. |
| `initialAudioSensitivity` | 0-20 | Starting value of the live **Audio Sensitivity** control. This also scales overall audio energy used by the base image and reveal modes. It is a startup value; adjust the control window to change sensitivity while running. |
| `audioBaseIntensityScale` | 0-100 | Scales how much overall audio energy brightens the base image, in addition to the live base-image control. Set to `0` to remove this audio-driven brightness change. Final base-image brightness is limited to 0-1. |
| `baseImageSilenceFloor` | 0-1 | Starting level of the **Base Image** slider, i.e. base-image brightness before audio contributes. Changing **Silence Floor** in the controls window moves the Base Image slider to that value. Increase it if the base image should remain visible during silence. |
| `audioAttackTimeMs` | 0-1000 ms | Smoothing time for rising audio levels. Lower values make mask brightness and reveal energy react more quickly; `0` applies rises immediately. |
| `audioReleaseTimeMs` | 0-10000 ms | Smoothing time for falling audio levels. Higher values make colours and reveal effects linger after a sound; `0` applies falls immediately. |

The live **Audio Sensitivity** control (**Controls > Audio Response**) multiplies the FFT response and overall
audio energy; it is separate from `audioBandMultiplier`. If a visual layer is
too dim or too bright, adjust sensitivity and the corresponding layer gain
before changing frequency mapping. Mask solid and bloom intensities are each
limited to **10 image draws per mask**, so further gain above that rendering
limit has no visible effect.

### Spotlight

| Setting | Accepted values | What it changes |
|---|---|---|
| `spotlightEnergyMultiplier` | 0-100 | Scales audio energy before it is converted to spotlight size. Higher values make the spotlight reach its maximum radius at quieter sound levels. |
| `spotlightMinimumRadius` | 0.01-2, in image-height units | Spotlight radius at low energy. For example, `0.5` is half the displayed image height. |
| `spotlightMaximumRadius` | At least `spotlightMinimumRadius`, up to 2 image heights | Maximum radius at high energy. Values larger than the image can cover most or all of it. |
| `spotlightEdgeFeatherProportion` | 0-1 | Soft-edge width as a proportion of the spotlight radius. `0` gives a sharp edge; larger values make the transition more gradual. It also feathers the base-image ring: the ring's soft edge is this value times half the image width, with a small minimum. |
| `spotlightMotionUpdateIntervalMs` | 1-60000 ms | Time between new random motion targets. Shorter intervals change direction more often. |
| `spotlightBrownianStep` | 0.01-1 | Scale of each random target displacement relative to the image size. Larger values make the spotlight move farther between targets. |
| `spotlightMotionSmoothingTimeMs` | 0-60000 ms | Time used to glide toward each new target. Lower values follow targets faster; `0` moves to each target immediately. |
| `spotlightIndependentMaskPositions` | `true` or `false` | When `true`, each active colour mask has its own moving spotlight. When `false`, all masks share one position. |
| `spotlightKeepCirclesInsideImage` | `true` or `false` | When `true`, spotlight positions and radius are constrained so the circular reveal stays inside the image. Turn it off to allow edge clipping. |

### Area

| Setting | Accepted values | What it changes |
|---|---|---|
| `startRevealMode` | `FULL`, `SPOTLIGHT`, or `AREA` | Reveal mode selected when the sketch starts. Modes can also be switched using the controls window or `M`. |
| `areaEnergyMultiplier` | 0.01-100 | Scales audio energy used to select tiles. Higher values generally activate more tiles at lower volume; lower values keep the display sparser. |
| `areaCycleDurationSeconds` | 1-100 seconds | Duration of the tile-selection cycle. Shorter cycles make the pattern migrate faster; longer cycles keep its layout changing more slowly. |
| `areaRevealStyle` | `WHOLE_TILE`, `CENTER_GLOW`, or `TRAIL` | Visual treatment for selected tiles: show each tile at once, reveal outward from its centre, or draw a moving particle with a fading trail. |

### Tuning examples

- **Make colours react more strongly:** raise `audioBandMultiplier` or the live
  Audio Sensitivity value. If bloom alone needs emphasis, raise
  `audioBloomMultiplier`.
- **Make the response smoother:** increase `audioAttackTimeMs` for slower rises
  and/or `audioReleaseTimeMs` for longer fades.
- **Focus the colours on lower frequencies:** lower `maxFftFrequency` and/or
  raise `frequencyMappingExponent`. The mapping order still determines which
  colour receives each successive band.
- **Keep the base image visible in silence:** raise `baseImageSilenceFloor`;
  use `audioBaseIntensityScale` to change its additional audio-driven boost.
- **Make Spotlight respond at quieter levels:** raise
  `spotlightEnergyMultiplier`. Adjust its minimum and maximum radii separately
  to change the size range.
- **Change how many Area tiles activate:** adjust `areaEnergyMultiplier`;
  change how quickly the pattern evolves with `areaCycleDurationSeconds`.

## Runtime shortcuts

| Key | Action |
|---|---|
| `M` | Cycle between `FULL`, `SPOTLIGHT`, and `AREA`. |
| `D` | Toggle window decorations (title bar/borders) when `useFullScreen=false`. |

## Troubleshooting

- **No base image or masks:** verify the required assets are in
  [`Visualizer/data`](./Visualizer/data).
- **No audio response:** confirm the selected source is producing audio and
  that `audioBandMultiplier` and audio sensitivity are not too low.
- **Unexpected band colours:** check `colorBandMapping`; its leftmost initial
  is the lowest FFT band.
- **A setting does not persist:** edit `parameters.txt` and restart; live
  controls are session-only. The **Base Image**, **Solid** and **Bloom**
  sliders have no file entry, so they always start at their defaults.
