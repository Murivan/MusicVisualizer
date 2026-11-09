Throwaway spike: live audio capture in a Processing sketch through PortAudio (WASAPI / ASIO) via JNA.

1. Run `powershell -ExecutionPolicy Bypass -File setup.ps1` once (close the sketch in Processing first, it locks the jar).
   It copies JNA from the Processing install into `jna-lib/`, downloads the PortAudio DLLs from the `sounddevice` wheel
   into `data/`, and builds `code/portaudio-backend.jar` from `backend-src/`.
2. Open `PortAudioSpike.pde` in Processing and run it.
3. To export an application, run `powershell -ExecutionPolicy Bypass -File export.ps1` (output: `windows-amd64/`).
   Do not use Processing's Export Application button: it omits `jna.jar`, which export.ps1 copies into `lib/`.

Keys: UP/DOWN/PgUp/PgDn/mouse wheel scroll the device list, H cycles the host-API filter, ENTER opens a device,
BACKSPACE closes it, B cycles the buffer size, E toggles WASAPI exclusive.

Why the odd layout: Processing treats every package inside a jar in `code/` as an import, and refuses to build while
several installed libraries (video, ...) bundle `com.sun.jna`. So JNA cannot be in `code/`; the facade jar reaches it through
its manifest `Class-Path` (`jna.jar` in the exported `lib/`, `../jna-lib/jna.jar` when running from the IDE). The PortAudio
DLLs live in `data/`, which the exporter ships and the sketch finds with `dataPath()`.
