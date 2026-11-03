MUSIC VISUALIZER - IMAGE ANALYZER
=================================

Prepares an image for the Music Visualizer. No installation and no Python needed.

START
  Windows : double-click Start.bat
  macOS   : double-click Start.command

  A black window opens and, after a few seconds, your browser shows the app.
  Keep the window open while you work. Close it to quit.

USE
  1. Choose an image (PNG with transparency works best; JPG etc. also work).
  2. Pick the output folder with "Browse..." (default: the "output" folder next to this file).
  3. Adjust the colour ranges, then press "Confirm and export colour layers".
  4. Adjust the structure settings, then press "Confirm and export structure masks".
  5. Copy the generated files into the Visualizer's "data" folder.

  Exporting large images can take a minute or two.

FIRST START WARNINGS
  Windows : "Windows protected your PC" -> More info -> Run anyway.
            If you downloaded the zip, right-click it -> Properties -> Unblock BEFORE unzipping.
  macOS   : if Start.command is blocked, right-click it -> Open -> Open.
            Or run in Terminal:  xattr -dr com.apple.quarantine <path to this folder>

TROUBLESHOOTING
  - The browser does not open: open the address printed in the black window
    (for example http://localhost:8866).
  - "The folder dialog is not available": type the output folder path instead.
  - Everything stays on your computer; the app only listens on localhost.
