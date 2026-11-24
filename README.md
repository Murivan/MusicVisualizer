# Music Visualizer

A Processing sketch that visualizes an audio file or live audio input over a
window-image composition. The visualizer renders the output fullscreen and
opens a separate, resizable control window for live tuning.

The original stained glass image is licensed to the parish of Heilig Kreuz, Detmold (Germany) (https://www.pv-lippe-detmold.de/kirchorte/heilig-kreuz-detmold/) and has been taken by © Ansgar Hoffmann 2023 (https://hoffmannfoto.de/)

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

The sketch uses Minim to play a selected audio file or capture a selected
audio input. Each frame:

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
| **File only** (need a restart) | `useFullScreen`, `canvasWidth`, `canvasHeight`, `visualizationDisplay`, `controlsWindowWidth`, `controlsWindowHeight`, `fps`, `audioBufferSize` | Yes | No |
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
| `audioBufferSize` | Power of two from 32-65536 | Number of audio samples used by the input buffer and FFT. Larger buffers provide finer frequency spacing but respond less immediately; smaller buffers respond faster but give coarser frequency spacing. |
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
