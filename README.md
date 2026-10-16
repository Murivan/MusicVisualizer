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
ImageAnalyzer.ipynb              Optional image/mask analysis notebook
```

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
- Mask intensity controls.
- Audio response controls.
- Spotlight controls.
- Area controls.
- Runtime diagnostics and FFT band labels.

Tap or click a slider's value box to enter a precise numeric value. Type a
number and press **Enter** to apply it; press **Escape** to cancel.

## Audio and FFT mapping

The sketch uses Minim to play a selected audio file or capture a selected
audio input. Each frame:

1. The source buffer is sent to the FFT.
2. Overall audio level drives base-image brightness and reveal-mode energy.
3. FFT bins are divided among configured colour masks.
4. Per-band levels are smoothed using attack and release time constants.
5. Solid and bloom mask layers are composited with additive blending.

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
visualization settings only for the running session.

### Window and controls

| Setting | Purpose |
|---|---|
| `useFullScreen` | Use selected-display fullscreen output; otherwise use `canvasWidth` and `canvasHeight`. |
| `canvasWidth`, `canvasHeight` | Non-fullscreen visualization dimensions. |
| `visualizationDisplay` | Zero-based display preselected in the display chooser. |
| `controlsWindowWidth`, `controlsWindowHeight` | Initial control-window dimensions. |
| `fps` | Target sketch frame rate. |

### Audio response

| Setting | Purpose |
|---|---|
| `audioBufferSize` | FFT/input buffer size; must be a power of two. |
| `colorBandMapping` | Initial mask order and low-to-high FFT-band mapping. Editable at runtime in Controls > Audio Response (type initials, press Enter); all masks are preloaded. |
| `maxFftFrequency` | Highest frequency included in mask-band analysis. |
| `frequencyMappingExponent` | Distribution curve for FFT bands; higher values favour lower frequencies. |
| `bandOverlap` | 0 to 0.95. Each band widens by this fraction of its width (half on each side, clamped to 0 and the max bin), so neighbours overlap while the full range stays covered. |
| `audioBandMultiplier` | FFT amplitude scaling for solid masks. |
| `audioBloomMultiplier` | Additional bloom responsiveness multiplier. |
| `initialAudioSensitivity` | Starting live audio-sensitivity value. |
| `audioBaseIntensityScale` | Audio contribution to base-image brightness. |
| `baseImageSilenceFloor` | Base-image brightness before audio contribution. |
| `audioAttackTimeMs`, `audioReleaseTimeMs` | Smoothing time constants for responsive visual changes. |

### Spotlight

| Setting | Purpose |
|---|---|
| `spotlightEnergyMultiplier` | Audio-energy scaling for Spotlight mode. |
| `spotlightMinimumRadius`, `spotlightMaximumRadius` | Quiet and loud spotlight radius limits. |
| `spotlightEdgeFeatherProportion` | Soft-edge fraction of each spotlight. |
| `spotlightMotionUpdateIntervalMs` | Time between Brownian-motion targets. |
| `spotlightBrownianStep` | Brownian target displacement scale. |
| `spotlightMotionSmoothingTimeMs` | Gliding time constant toward a target. |
| `spotlightIndependentMaskPositions` | Use one Spotlight position per colour mask. |
| `spotlightKeepCirclesInsideImage` | Keep spotlights inside image bounds. |

### Area

| Setting | Purpose |
|---|---|
| `startRevealMode` | Initial mode: `FULL`, `SPOTLIGHT`, or `AREA`. |
| `areaEnergyMultiplier` | Audio-energy scaling for Area tile selection. |
| `areaCycleDurationSeconds` | Tile-selection cycle duration. |
| `areaRevealStyle` | Active-tile style: `WHOLE_TILE`, `CENTER_GLOW`, or `TRAIL`. |

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
  controls are session-only.
