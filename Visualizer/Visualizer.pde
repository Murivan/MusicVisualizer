import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;
import ddf.minim.signals.*;
import ddf.minim.spi.*;
import ddf.minim.ugens.*;

import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Mixer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Properties;

import javax.swing.JFileChooser;
import javax.swing.filechooser.FileNameExtensionFilter;
import javax.swing.JOptionPane;
import javax.swing.JDialog;
import java.io.File;
import java.io.InputStream;
import java.awt.GraphicsEnvironment;
import java.awt.GraphicsDevice;
import java.awt.DisplayMode;
import java.awt.Rectangle;

PImage baseImg;
PImage areaIdMask;
PImage areaCenterMap;
PImage[] solidMasks;
PImage[] bloomMasks;
PShader spotlightRevealShader;
PShader spotlightBaseRevealShader;
PShader areaRevealShader;
volatile boolean masksDecoded = false;
volatile int masksDecodedCount = 0;
int warmupIndex = 0;
boolean allMasksReady = false;
int animationStartMs = 0;
float imgX, imgY, imgW, imgH;

Minim minim;
AudioPlayer track;
AudioInput in;
FFT fft;
boolean useAudioInput = false;
String audioFileName = "";
volatile boolean isAudioReady = false;
boolean audioPlaybackStarted = false;
boolean isCancelled = false;

// Configuration variables
// ------------------------
boolean useFullScreen = true; // Set to false to use custom canvas bounds below
int canvasWidth = 1920;
int canvasHeight = 1080;
int visualizationDisplay = 0;
int controlsWindowWidth = 900;
int controlsWindowHeight = 1080;
int fps = 30;
ControlsWindow controlsWindow;

// Audio Configuration
int audioBufferSize = 2048;           // Size of the audio buffer (also dictates FFT resolution)
float maxFftFrequency = 20000.0;       // The maximum frequency (Hz) analyzed and mapped across the masks
float frequencyMappingExponent = 3.5; // 1.0 is linear; higher values give lower frequencies more masks
float bandOverlap = 0.0;              // 0 = no overlap; each band widens by this fraction of its width (max 0.95)
float audioBandMultiplier = 0.1;      // Base scaling factor for the real-time FFT band amplitudes
float audioBloomMultiplier = 1.0;     // Indicates how much more the bloom reacts compared to solid masks
final int MAX_MASK_DRAW_PASSES = 10;
final int DOUBLE_CLICK_MS = 400;        // Max interval between presses that counts as a slider double-click
final float DOUBLE_CLICK_DISTANCE = 30.0;  // Max pointer travel between those presses, in pixels
float initialAudioSensitivity = 2.0;  // Initial value for the audio sensitivity slider
float audioBaseIntensityScale = 0.5;  // How much the overall audio energy boosts the base image brightness
float baseImageSilenceFloor = 0.0;    // The base image brightness (baseline) before audio boosts it
// Reveal Modes
enum RevealMode {
  FULL,
  SPOTLIGHT,
  AREA
}
RevealMode currentRevealMode = RevealMode.FULL;

enum AreaRevealStyle {
  WHOLE_TILE,
  CENTER_GLOW,
  TRAIL
}

// Full/Global settings
float audioAttackTimeMs = 50.0;       // Time constant for colored areas to rise toward a higher audio level
float audioReleaseTimeMs = 500.0;     // Time constant for colored areas to fade after their audio level falls
float audioSampleRate = 0.0;
int actualAudioBufferSize = audioBufferSize;

// Spotlight Reveal Mode
float spotlightEnergyMultiplier = 1.0;            // Scales audio level before converting it to spotlight area
float spotlightMinimumRadius = 0.04;              // Quiet-sound radius as a fraction of the image height
float spotlightMaximumRadius = 0.5;               // Loud-sound radius; 0.5 covers the circular image when centered
float spotlightEdgeFeatherProportion = 0.25;       // Fraction of each spotlight radius used for its soft edge
float spotlightMotionUpdateIntervalMs = 1000.0;   // Milliseconds between new Brownian motion targets
float spotlightBrownianStep = 0.03;               // Brownian target-step scale as a fraction of image size
float spotlightMotionSmoothingTimeMs = 500.0;     // Time constant used to glide toward each new target
boolean spotlightIndependentMaskPositions = true; // Give each color mask its own moving spotlight
boolean spotlightKeepCirclesInsideImage = true;   // Recenter and limit spotlights so edges never clip them

// Area Reveal Mode
float areaEnergyMultiplier = 1.0;               // Scales audio level before converting it to probability threshold
float areaCycleDurationSeconds = 12.0;          // How fast the random areas evolve and cycle (seconds)
AreaRevealStyle areaRevealStyle = AreaRevealStyle.WHOLE_TILE;


String colorBandMapping = "BCGROY";
String[] colorNames = getColorNames(colorBandMapping);
float[] solidIntensities = new float[colorNames.length];
float[] bloomIntensities = new float[colorNames.length];
float[] releasedBandIntensities = new float[colorNames.length];
float baseIntensity = baseImageSilenceFloor;
float audioSensitivity = initialAudioSensitivity;
volatile float currentAudioLevel = 0.0;
int lastAudioResponseMs = 0;

float spotlightEnergy = 0.0;
float spotlightRevealRadius = 0.0;
float areaTrailProgress = 0.0;
float[] spotlightPositionX = new float[colorNames.length];
float[] spotlightPositionY = new float[colorNames.length];
float[] spotlightTargetX = new float[colorNames.length];
float[] spotlightTargetY = new float[colorNames.length];
int lastSpotlightMotionUpdateMs = 0;

Slider[] solidSliders;
Slider[] bloomSliders;
Slider baseSlider;
Slider audioSensSlider;
RuntimeSlider[] audioResponseSliders;
RuntimeSlider[] spotlightRevealSliders;
RuntimeSlider[] areaRevealSliders;

static
{
  String operatingSystem = System.getProperty("os.name", "").toLowerCase();
  if (operatingSystem.startsWith("windows")) {
    // Windows requires a non-1.0 value to force 1:1 pixel rendering.
    System.setProperty("sun.java2d.uiScale", "1.01");
  }
}

void settings() {
  loadParameters();
  if (useFullScreen) {
    GraphicsDevice[] displays = GraphicsEnvironment.getLocalGraphicsEnvironment().getScreenDevices();
    int displayCount = displays.length;
    visualizationDisplay = constrain(visualizationDisplay, 0, max(0, displayCount - 1));
    visualizationDisplay = promptForVisualizationDisplay(displays, visualizationDisplay);
    fullScreen(P2D, visualizationDisplay);
  } else {
    size(canvasWidth, canvasHeight, P2D);
  }
}

int promptForVisualizationDisplay(GraphicsDevice[] displays, int defaultDisplay) {
  if (displays.length == 0) {
    println("No displays were reported; using display 0.");
    return 0;
  }

  String[] displayOptions = new String[displays.length];
  for (int i = 0; i < displays.length; i++) {
    displayOptions[i] = describeDisplay(i, displays[i]);
  }

  JOptionPane pane = new JOptionPane(
    "Select the display for the fullscreen visualization:",
    JOptionPane.QUESTION_MESSAGE,
    JOptionPane.DEFAULT_OPTION,
    null,
    null,
    null
  );
  pane.setWantsInput(true);
  pane.setSelectionValues(displayOptions);
  pane.setInitialSelectionValue(displayOptions[defaultDisplay]);
  JDialog dialog = pane.createDialog(null, "Fullscreen Visualization Display");
  dialog.setAlwaysOnTop(true);
  dialog.setVisible(true);

  Object selectedValue = pane.getInputValue();
  if (selectedValue == JOptionPane.UNINITIALIZED_VALUE || selectedValue == null) {
    return defaultDisplay;
  }

  for (int i = 0; i < displayOptions.length; i++) {
    if (displayOptions[i].equals(selectedValue)) return i;
  }

  println("Could not match the selected display; using configured display " + defaultDisplay + ".");
  return defaultDisplay;
}

String describeDisplay(int index, GraphicsDevice display) {
  DisplayMode mode = display.getDisplayMode();
  Rectangle bounds = display.getDefaultConfiguration().getBounds();
  String refreshRate = mode.getRefreshRate() == DisplayMode.REFRESH_RATE_UNKNOWN
    ? "unknown refresh"
    : mode.getRefreshRate() + " Hz";
  String colorDepth = mode.getBitDepth() == DisplayMode.BIT_DEPTH_MULTI
    ? "multi-depth"
    : mode.getBitDepth() + "-bit";

  return "Display " + (index + 1)
    + " | " + display.getIDstring()
    + " | " + mode.getWidth() + "x" + mode.getHeight()
    + " @ " + refreshRate
    + " | " + colorDepth
    + " | bounds " + bounds.x + "," + bounds.y + " " + bounds.width + "x" + bounds.height
    + " | fullscreen " + (display.isFullScreenSupported() ? "supported" : "not supported");
}

void setup() {
  frameRate(fps);
  baseIntensity = baseImageSilenceFloor;
  audioSensitivity = initialAudioSensitivity;
  actualAudioBufferSize = audioBufferSize;
  spotlightRevealRadius = spotlightMinimumRadius;
  //smooth(4); // Reduced from 8 since Retina density already makes lines crisp
  //pixelDensity(displayDensity());

  // Setup GPU shaders and masks
  baseImg = loadImage("window_base.png");
  areaIdMask = loadImage("mask_area_ids.png");
  areaCenterMap = createAreaCenterMap(areaIdMask);
  spotlightRevealShader = loadShader("spotlight_reveal.glsl");
  spotlightBaseRevealShader = loadShader("spotlight_base_reveal.glsl");
  areaRevealShader = loadShader("area_reveal.glsl");
  solidMasks = new PImage[colorNames.length];
  bloomMasks = new PImage[colorNames.length];

  updateImageLayout();
  initializeSpotlightPositions();

  controlsWindow = new ControlsWindow();
  PApplet.runSketch(new String[] {"ControlsWindow"}, controlsWindow);

  thread("preloadMasks");
  thread("setupAudio");
}

void initializeSpotlightPositions() {
  for (int i = 0; i < colorNames.length; i++) {
    float randomX = random(0.0, 1.0);
    float randomY = random(0.0, 1.0);
    spotlightPositionX[i] = randomX;
    spotlightPositionY[i] = randomY;
    spotlightTargetX[i] = randomX;
    spotlightTargetY[i] = randomY;
  }
}

void loadParameters() {
  Properties parameters = new Properties();

  try {
    InputStream input = createInput("parameters.txt");
    if (input == null) {
      println("parameters.txt not found; using built-in defaults.");
      return;
    }
    parameters.load(input);
    input.close();
  }
  catch (Exception error) {
    println("Could not read parameters.txt; using built-in defaults: " + error.getMessage());
    return;
  }

  useFullScreen = getBooleanParameter(parameters, "useFullScreen", useFullScreen);
  canvasWidth = getIntParameter(parameters, "canvasWidth", canvasWidth, 320, 16384);
  canvasHeight = getIntParameter(parameters, "canvasHeight", canvasHeight, 240, 16384);
  visualizationDisplay = getIntParameter(parameters, "visualizationDisplay", visualizationDisplay, 0, 15);
  controlsWindowWidth = getIntParameter(parameters, "controlsWindowWidth", controlsWindowWidth, 320, 4096);
  controlsWindowHeight = getIntParameter(parameters, "controlsWindowHeight", controlsWindowHeight, 240, 4096);
  fps = getIntParameter(parameters, "fps", fps, 1, 240);
  configureColorBandMapping(parameters.getProperty("colorBandMapping", colorBandMapping));
  int requestedBufferSize = getIntParameter(parameters, "audioBufferSize", audioBufferSize, 32, 65536);
  if ((requestedBufferSize & (requestedBufferSize - 1)) == 0) {
    audioBufferSize = requestedBufferSize;
  } else {
    println("Ignoring audioBufferSize: value must be a power of two.");
  }

  maxFftFrequency = getFloatParameter(parameters, "maxFftFrequency", maxFftFrequency, 1.0, 192000.0);
  frequencyMappingExponent = getFloatParameter(parameters, "frequencyMappingExponent", frequencyMappingExponent, 0.1, 20.0);
  bandOverlap = getFloatParameter(parameters, "bandOverlap", bandOverlap, 0.0, 0.95);
  audioBandMultiplier = getFloatParameter(parameters, "audioBandMultiplier", audioBandMultiplier, 0.01, 100.0);
  audioBloomMultiplier = getFloatParameter(parameters, "audioBloomMultiplier", audioBloomMultiplier, 0.0, 100.0);
  initialAudioSensitivity = getFloatParameter(parameters, "initialAudioSensitivity", initialAudioSensitivity, 0.0, 20.0);
  audioBaseIntensityScale = getFloatParameter(parameters, "audioBaseIntensityScale", audioBaseIntensityScale, 0.0, 100.0);
  baseImageSilenceFloor = getFloatParameter(parameters, "baseImageSilenceFloor", baseImageSilenceFloor, 0.0, 1.0);
  audioAttackTimeMs = getFloatParameter(parameters, "audioAttackTimeMs",   audioAttackTimeMs, 0.0, 1000.0);
    audioReleaseTimeMs = getFloatParameter(parameters, "audioReleaseTimeMs", audioReleaseTimeMs, 0.0, 10000.0);

  String startMode = parameters.getProperty("startRevealMode", "FULL").trim().toUpperCase();
  if (startMode.equals("SPOTLIGHT")) currentRevealMode = RevealMode.SPOTLIGHT;
  else if (startMode.equals("AREA")) currentRevealMode = RevealMode.AREA;
  else currentRevealMode = RevealMode.FULL;

  spotlightEnergyMultiplier = getFloatParameter(parameters, "spotlightEnergyMultiplier", spotlightEnergyMultiplier, 0.0, 100.0);
  spotlightMinimumRadius = getFloatParameter(parameters, "spotlightMinimumRadius", spotlightMinimumRadius, 0.01, 2.0);
  spotlightMaximumRadius = getFloatParameter(parameters, "spotlightMaximumRadius", spotlightMaximumRadius, spotlightMinimumRadius, 2.0);
  spotlightEdgeFeatherProportion = getFloatParameter(parameters, "spotlightEdgeFeatherProportion", spotlightEdgeFeatherProportion, 0.0, 1.0);
  spotlightMotionUpdateIntervalMs = getFloatParameter(parameters, "spotlightMotionUpdateIntervalMs", spotlightMotionUpdateIntervalMs, 1.0, 60000.0);
  spotlightBrownianStep = getFloatParameter(parameters, "spotlightBrownianStep", spotlightBrownianStep, 0.01, 1.0);
  spotlightMotionSmoothingTimeMs = getFloatParameter(parameters, "spotlightMotionSmoothingTimeMs", spotlightMotionSmoothingTimeMs, 0.0, 60000.0);
  spotlightIndependentMaskPositions = getBooleanParameter(parameters, "spotlightIndependentMaskPositions", spotlightIndependentMaskPositions);
  spotlightKeepCirclesInsideImage = getBooleanParameter(parameters, "spotlightKeepCirclesInsideImage", spotlightKeepCirclesInsideImage);

  areaEnergyMultiplier = getFloatParameter(parameters, "areaEnergyMultiplier", areaEnergyMultiplier, 0.01, 100.0);
  areaCycleDurationSeconds = getFloatParameter(parameters, "areaCycleDurationSeconds", areaCycleDurationSeconds, 1.0, 100.0);
  areaRevealStyle = getAreaRevealStyle(parameters);
}

AreaRevealStyle getAreaRevealStyle(Properties parameters) {
  String value = parameters.getProperty("areaRevealStyle");
  if (value == null) {
    return getBooleanParameter(parameters, "areaCenterGlow", false)
      ? AreaRevealStyle.CENTER_GLOW
      : AreaRevealStyle.WHOLE_TILE;
  }

  String normalizedValue = value.trim().toUpperCase();
  if (normalizedValue.equals("CENTER_GLOW")) return AreaRevealStyle.CENTER_GLOW;
  if (normalizedValue.equals("TRAIL")) return AreaRevealStyle.TRAIL;
  if (normalizedValue.equals("WHOLE_TILE")) return AreaRevealStyle.WHOLE_TILE;

  println("Ignoring invalid areaRevealStyle=" + value + ". Use WHOLE_TILE, CENTER_GLOW, or TRAIL.");
  return AreaRevealStyle.WHOLE_TILE;
}

PImage createAreaCenterMap(PImage idMap) {
  if (idMap == null) return null;

  idMap.loadPixels();
  HashMap<Integer, TileGeometry> tiles = new HashMap<Integer, TileGeometry>();
  for (int y = 0; y < idMap.height; y++) {
    for (int x = 0; x < idMap.width; x++) {
      int index = y * idMap.width + x;
      int tileId = idMap.pixels[index] & 0x00FFFFFF;
      if (tileId == 0) continue;

      TileGeometry tile = tiles.get(tileId);
      if (tile == null) {
        tile = new TileGeometry();
        tiles.put(tileId, tile);
      }
      tile.add(x, y);
    }
  }

  float imageAspect = idMap.width / (float)idMap.height;
  float radiusScale = max(1.0, imageAspect);
  for (TileGeometry tile : tiles.values()) {
    tile.finish(idMap.width, idMap.height, imageAspect);
  }
  for (int y = 0; y < idMap.height; y++) {
    for (int x = 0; x < idMap.width; x++) {
      TileGeometry tile = tiles.get(idMap.pixels[y * idMap.width + x] & 0x00FFFFFF);
      if (tile != null) tile.measureRadius(x, y, idMap.width, idMap.height, imageAspect);
    }
  }

  PImage centerMap = createImage(idMap.width, idMap.height, RGB);
  centerMap.loadPixels();
  for (int y = 0; y < idMap.height; y++) {
    for (int x = 0; x < idMap.width; x++) {
      int index = y * idMap.width + x;
      TileGeometry tile = tiles.get(idMap.pixels[index] & 0x00FFFFFF);
      if (tile == null) {
        centerMap.pixels[index] = color(0);
      } else {
        int centerX = round(constrain(tile.centerX, 0.0, 1.0) * 255.0);
        int centerY = round(constrain(tile.centerY, 0.0, 1.0) * 255.0);
        int radius = round(constrain(tile.radius / radiusScale, 0.0, 1.0) * 255.0);
        centerMap.pixels[index] = color(centerX, centerY, radius);
      }
    }
  }
  centerMap.updatePixels();
  return centerMap;
}

class TileGeometry {
  float sumX;
  float sumY;
  int pixelCount;
  float centerX;
  float centerY;
  float radius;

  void add(int x, int y) {
    sumX += x + 0.5;
    sumY += y + 0.5;
    pixelCount++;
  }

  void finish(int imageWidth, int imageHeight, float imageAspect) {
    centerX = sumX / pixelCount / imageWidth;
    centerY = sumY / pixelCount / imageHeight;
  }

  void measureRadius(int x, int y, int imageWidth, int imageHeight, float imageAspect) {
    float offsetX = ((x + 0.5) / imageWidth - centerX) * imageAspect;
    float offsetY = (y + 0.5) / imageHeight - centerY;
    radius = max(radius, sqrt(offsetX * offsetX + offsetY * offsetY));
  }
}

boolean configureColorBandMapping(String mapping) {
  String normalizedMapping = mapping.replaceAll("\\s", "").toUpperCase();
  String[] configuredColors = getColorNames(normalizedMapping);
  if (configuredColors == null) {
    println("Ignoring invalid colorBandMapping=" + mapping + ". Use unique initials from B, C, R, O, Y, G, M.");
    return false;
  }

  colorBandMapping = normalizedMapping;
  colorNames = configuredColors;
  solidIntensities = new float[colorNames.length];
  bloomIntensities = new float[colorNames.length];
  releasedBandIntensities = new float[colorNames.length];
  spotlightPositionX = new float[colorNames.length];
  spotlightPositionY = new float[colorNames.length];
  spotlightTargetX = new float[colorNames.length];
  spotlightTargetY = new float[colorNames.length];
  return true;
}

String[] getColorNames(String mapping) {
  if (mapping == null || mapping.length() == 0) return null;

  String[] names = new String[mapping.length()];
  boolean[] usedInitials = new boolean[7];
  for (int i = 0; i < mapping.length(); i++) {
    char initial = mapping.charAt(i);
    int initialIndex = getColorInitialIndex(initial);
    if (initialIndex < 0 || usedInitials[initialIndex]) return null;

    usedInitials[initialIndex] = true;
    names[i] = getColorName(initial);
  }
  return names;
}

int getColorInitialIndex(char initial) {
  if (initial == 'B') return 0;
  if (initial == 'C') return 1;
  if (initial == 'R') return 2;
  if (initial == 'O') return 3;
  if (initial == 'Y') return 4;
  if (initial == 'G') return 5;
  if (initial == 'M') return 6;
  return -1;
}

String getColorName(char initial) {
  if (initial == 'B') return "blue";
  if (initial == 'C') return "cyan";
  if (initial == 'R') return "red";
  if (initial == 'O') return "orange";
  if (initial == 'Y') return "yellow";
  if (initial == 'G') return "green";
  return "magenta";
}

int getIntParameter(Properties parameters, String name, int defaultValue, int minimum, int maximum) {
  String value = parameters.getProperty(name);
  if (value == null) return defaultValue;

  try {
    return constrain(Integer.parseInt(value.trim()), minimum, maximum);
  }
  catch (NumberFormatException error) {
    println("Ignoring invalid integer parameter " + name + "=" + value);
    return defaultValue;
  }
}

float getFloatParameter(Properties parameters, String name, float defaultValue, float minimum, float maximum) {
  String value = parameters.getProperty(name);
  if (value == null) return defaultValue;

  try {
    return constrain(Float.parseFloat(value.trim()), minimum, maximum);
  }
  catch (NumberFormatException error) {
    println("Ignoring invalid numeric parameter " + name + "=" + value);
    return defaultValue;
  }
}

boolean getBooleanParameter(Properties parameters, String name, boolean defaultValue) {
  String value = parameters.getProperty(name);
  if (value == null) return defaultValue;

  String normalizedValue = value.trim().toLowerCase();
  if (normalizedValue.equals("true")) return true;
  if (normalizedValue.equals("false")) return false;

  println("Ignoring invalid boolean parameter " + name + "=" + value);
  return defaultValue;
}

// Fits the base image into the current window; called every frame so resizing works.
void updateImageLayout() {
  if (baseImg == null) return;
  float scaleRatio = min((float)width / baseImg.width, (float)height / baseImg.height);
  imgW = baseImg.width * scaleRatio;
  imgH = baseImg.height * scaleRatio;
  imgX = (width - imgW) / 2;
  imgY = (height - imgH) / 2;
}

int[] savedWindowBounds;

void toggleWindowDecorations() {
  if (useFullScreen) return;
  Object nativeWindow = surface.getNative();
  if (nativeWindow instanceof com.jogamp.newt.opengl.GLWindow) {
    final com.jogamp.newt.opengl.GLWindow window = (com.jogamp.newt.opengl.GLWindow)nativeWindow;
    new Thread(new Runnable() {
      public void run() {
        if (window.isUndecorated()) {
          window.setUndecorated(false);
          if (savedWindowBounds != null) {
            window.setSize(savedWindowBounds[2], savedWindowBounds[3]);
            window.setPosition(savedWindowBounds[0], savedWindowBounds[1]);
          }
        } else {
          savedWindowBounds = new int[] { window.getX(), window.getY(), window.getWidth(), window.getHeight() };
          com.jogamp.newt.MonitorDevice monitor = window.getMainMonitor();
          for (com.jogamp.newt.MonitorDevice m : window.getScreen().getMonitorDevices()) {
            println("Monitor " + m.getId() + ": pixels " + m.getViewport() + " | window units " + m.getViewportInWindowUnits());
          }
          savedWindowBounds = new int[] { window.getX(), window.getY(), window.getWidth(), window.getHeight() };
          window.setUndecorated(true);
          fitWindowToMonitor(window, monitor);
        }
      }
    }).start();
  }
}

// Window units and pixels differ on scaled (HiDPI) displays and the ratio is not always what JOGL
// reports, so resize, measure the real surface in pixels, and correct until it matches the monitor.
void fitWindowToMonitor(com.jogamp.newt.opengl.GLWindow window, com.jogamp.newt.MonitorDevice monitor) {
 com.jogamp.nativewindow.util.RectangleImmutable units = monitor.getViewportInWindowUnits();
 com.jogamp.nativewindow.util.RectangleImmutable pixels = monitor.getViewport();
 float factor = 1.0;
 for (int attempt = 0; attempt < 4; attempt++) {
   window.setSize(round(units.getWidth() * factor), round(units.getHeight() * factor));
   window.setPosition(round(units.getX() * factor), round(units.getY() * factor));
   try { Thread.sleep(250); } catch (InterruptedException e) { return; }
   int actualWidth = window.getSurfaceWidth();
   println("Fit attempt " + attempt + ": surface " + actualWidth + "x" + window.getSurfaceHeight()
     + " target " + pixels.getWidth() + "x" + pixels.getHeight() + " factor " + factor);
   if (abs(actualWidth - pixels.getWidth()) <= 1 || actualWidth <= 0) return;
   factor *= (float)pixels.getWidth() / actualWidth;
 }
}

// Both windows draw under this lock so a mapping change never exposes half-resized arrays.
final Object mappingLock = new Object();
volatile String pendingColorBandMapping = null;
PImage[] allSolidMasks = new PImage[7];
PImage[] allBloomMasks = new PImage[7];
final String[] allColorNames = { "blue", "cyan", "red", "orange", "yellow", "green", "magenta" };

void draw() {
  synchronized (mappingLock) {
    applyPendingColorBandMapping();
    drawVisualization();
  }
}

void applyPendingColorBandMapping() {
  String requested = pendingColorBandMapping;
  if (requested == null) return;
  pendingColorBandMapping = null;

  String[] previousNames = colorNames;
  if (!configureColorBandMapping(requested)) return;
  initializeSpotlightPositions();
  assignActiveMasks();
  if (controlsWindow != null) controlsWindow.rebuildMaskSliders(previousNames);
}

void assignActiveMasks() {
  PImage[] solid = new PImage[colorNames.length];
  PImage[] bloom = new PImage[colorNames.length];
  for (int i = 0; i < colorNames.length; i++) {
    int poolIndex = getColorInitialIndex(colorBandMapping.charAt(i));
    solid[i] = allSolidMasks[poolIndex];
    bloom[i] = allBloomMasks[poolIndex];
  }
  solidMasks = solid;
  bloomMasks = bloom;
}

void drawVisualization() {
  updateImageLayout();
  if (isCancelled) {
    exit();
    return;
  }

  float currentLevel = 0.0;
  if (isAudioReady) {
    if (useAudioInput && in != null) {
      fft.forward(in.mix);
      currentLevel = in.mix.level();
    } else if (!useAudioInput && track != null) {
      fft.forward(track.mix);
      currentLevel = track.mix.level();
    }
  }

  background(0);

  currentAudioLevel = currentLevel;
  int currentAudioResponseMs = millis();
  float elapsedMs = lastAudioResponseMs == 0 ? 1000.0 / fps : currentAudioResponseMs - lastAudioResponseMs;
  lastAudioResponseMs = currentAudioResponseMs;
  float attackAmount = audioAttackTimeMs <= 0.0 ? 1.0 : 1.0 - exp(-elapsedMs / audioAttackTimeMs);
  float releaseAmount = audioReleaseTimeMs <= 0.0 ? 1.0 : 1.0 - exp(-elapsedMs / audioReleaseTimeMs);

  if (solidSliders != null && bloomSliders != null) {
    for (int i = 0; i < colorNames.length; i++) {
      float bandVal = 0.0;
      if (isAudioReady && fft != null) {
        int maxBin = getMaxAnalysisBin();
        int startBin = getBandStartBin(i, maxBin);
        int endBin = getBandEndBin(i, maxBin);

        float sum = 0;
        for (int b = startBin; b < endBin; b++) {
          sum += fft.getBand(b);
        }
        bandVal = (sum / (endBin - startBin)) * audioBandMultiplier * audioSensitivity;
      }

      if (bandVal >= releasedBandIntensities[i]) {
        releasedBandIntensities[i] = lerp(releasedBandIntensities[i], bandVal, attackAmount);
      } else {
        releasedBandIntensities[i] = lerp(releasedBandIntensities[i], bandVal, releaseAmount);
      }

      solidIntensities[i] = solidSliders[i].val + releasedBandIntensities[i];
      bloomIntensities[i] = bloomSliders[i].val + releasedBandIntensities[i] * audioBloomMultiplier;
    }

    updateSpotlightReveal(currentLevel, currentAudioResponseMs, elapsedMs, attackAmount, releaseAmount);
  }

  if (baseImg != null) {
    boolean useSpotlightBaseReveal = currentRevealMode == RevealMode.SPOTLIGHT && spotlightBaseRevealShader != null;
    blendMode(BLEND);
    tint(255 * baseIntensity, 255);
    if (useSpotlightBaseReveal) {
      spotlightBaseRevealShader.set("revealEnergy", spotlightEnergy);
      spotlightBaseRevealShader.set("edgeFeather", max(0.02, spotlightEdgeFeatherProportion * 0.5));
      spotlightBaseRevealShader.set("imageAspect", imgW / imgH);
      shader(spotlightBaseRevealShader);
    }
    image(baseImg, imgX, imgY, imgW, imgH);
    if (useSpotlightBaseReveal) resetShader();

    // Decode in the background, then upload one mask pair per frame to the GPU.
    if (masksDecoded && !allMasksReady) {
      warmUpNextMaskPair();
    }

    // Every mask is already in CPU and GPU memory, so transitions are instantaneous.
    if (allMasksReady) {
      blendMode(ADD);

      boolean useSpotlightShader = currentRevealMode == RevealMode.SPOTLIGHT && spotlightRevealShader != null;
      boolean useAreaShader = currentRevealMode == RevealMode.AREA && areaRevealShader != null && areaIdMask != null;

      for (int i = 0; i < colorNames.length; i++) {
        if (useSpotlightShader) {
          float revealRadius = getSpotlightRevealRadiusForMask(i);
          spotlightRevealShader.set("revealCenter", spotlightPositionX[i], spotlightPositionY[i]);
          spotlightRevealShader.set("revealRadius", revealRadius);
          spotlightRevealShader.set("revealFeather", revealRadius * spotlightEdgeFeatherProportion);
          spotlightRevealShader.set("imageAspect", imgW / imgH);
          shader(spotlightRevealShader);
        } else if (useAreaShader) {
          areaRevealShader.set("idMap", areaIdMask);
          if (areaCenterMap != null) areaRevealShader.set("centerMap", areaCenterMap);

          float maskSeedOffset = spotlightIndependentMaskPositions ? (float)i * 123.456 : 0.0;
          float timeInSeconds = (float)millis() / 1000.0;

          areaRevealShader.set("audioEnergy", spotlightEnergy);
          areaRevealShader.set("time", timeInSeconds);
          areaRevealShader.set("cycleDuration", areaCycleDurationSeconds);
          areaRevealShader.set("seedOffset", maskSeedOffset);
          areaRevealShader.set("areaRevealStyle", areaCenterMap != null ? (float)areaRevealStyle.ordinal() : 0.0);
          areaRevealShader.set("trailProgress", areaTrailProgress);
          areaRevealShader.set("imageAspect", imgW / imgH);
          shader(areaRevealShader);
        }

        drawMaskWithCappedIntensity(solidMasks[i], solidIntensities[i]);
        drawMaskWithCappedIntensity(bloomMasks[i], bloomIntensities[i]);

        if (useSpotlightShader) {
          resetShader();
        }
      }

      if (useAreaShader) {
        resetShader();
      }
    }

    // Restore normal drawing state for subsequent effects or UI.
    blendMode(BLEND);
    noTint();
  } else {
    fill(255);
    textAlign(CENTER, CENTER);
    text("window_base.png not found in data folder or sketch folder.", width/2, height/2);
  }

  startAudioPlaybackIfReady();

}

void drawMaskWithCappedIntensity(PImage mask, float intensity) {
  float remainingIntensity = min(max(0.0, intensity), (float)MAX_MASK_DRAW_PASSES);
  int passes = 0;
  while (remainingIntensity > 0.0 && passes < MAX_MASK_DRAW_PASSES) {
    float passIntensity = min(1.0, remainingIntensity);
    tint(255, 255.0 * passIntensity);
    image(mask, imgX, imgY, imgW, imgH);
    remainingIntensity -= passIntensity;
    passes++;
  }
}

void keyPressed() {
  handleKeyPressed();
}

void handleKeyPressed() {
  if (key == 'd' || key == 'D') toggleWindowDecorations();
  if (key == 'm' || key == 'M') {
    int nextMode = (currentRevealMode.ordinal() + 1) % RevealMode.values().length;
    currentRevealMode = RevealMode.values()[nextMode];
    if (currentRevealMode == RevealMode.SPOTLIGHT) {
      lastSpotlightMotionUpdateMs = millis() - round(spotlightMotionUpdateIntervalMs);
    }
  }

}

void updateSpotlightReveal(float currentLevel, int currentMs, float elapsedMs, float attackAmount, float releaseAmount) {
  float energyMult = (currentRevealMode == RevealMode.AREA) ? areaEnergyMultiplier : spotlightEnergyMultiplier;
  float targetEnergy = constrain(currentLevel * audioSensitivity * energyMult, 0.0, 1.0);
  float energyAmount = targetEnergy >= spotlightEnergy ? attackAmount : releaseAmount;
  spotlightEnergy = lerp(spotlightEnergy, targetEnergy, energyAmount);

  if (currentRevealMode == RevealMode.AREA && areaRevealStyle == AreaRevealStyle.TRAIL) {
    float areaTrailSpeed = lerp(0.05, 3.0, spotlightEnergy);
    areaTrailProgress += elapsedMs / 1000.0 * areaTrailSpeed;
  }

  if (currentRevealMode != RevealMode.SPOTLIGHT) return;

  float minimumArea = spotlightMinimumRadius * spotlightMinimumRadius;
  float maximumArea = spotlightMaximumRadius * spotlightMaximumRadius;
  spotlightRevealRadius = sqrt(lerp(minimumArea, maximumArea, spotlightEnergy));

  float imageAspect = imgH > 0.0 ? imgW / imgH : 1.0;
  if (spotlightKeepCirclesInsideImage) {
    spotlightRevealRadius = min(spotlightRevealRadius, min(0.5, imageAspect * 0.5));
  }

  boolean updateTargets = lastSpotlightMotionUpdateMs == 0
    || currentMs - lastSpotlightMotionUpdateMs >= spotlightMotionUpdateIntervalMs;
  float motionAmount = spotlightMotionSmoothingTimeMs <= 0.0
    ? 1.0
    : 1.0 - exp(-elapsedMs / spotlightMotionSmoothingTimeMs);
  int movingPositionCount = spotlightIndependentMaskPositions ? colorNames.length : 1;

  float horizontalMargin = spotlightKeepCirclesInsideImage ? spotlightRevealRadius / imageAspect : 0.0;
  float verticalMargin = spotlightKeepCirclesInsideImage ? spotlightRevealRadius : 0.0;

  for (int i = 0; i < movingPositionCount; i++) {
    if (updateTargets) {
      spotlightTargetX[i] += randomGaussian() * spotlightBrownianStep;
      spotlightTargetY[i] += randomGaussian() * spotlightBrownianStep;
    }

    spotlightTargetX[i] = constrain(spotlightTargetX[i], horizontalMargin, 1.0 - horizontalMargin);
    spotlightTargetY[i] = constrain(spotlightTargetY[i], verticalMargin, 1.0 - verticalMargin);
    spotlightPositionX[i] = lerp(spotlightPositionX[i], spotlightTargetX[i], motionAmount);
    spotlightPositionY[i] = lerp(spotlightPositionY[i], spotlightTargetY[i], motionAmount);
  }

  if (!spotlightIndependentMaskPositions) {
    for (int i = 1; i < colorNames.length; i++) {
      spotlightPositionX[i] = spotlightPositionX[0];
      spotlightPositionY[i] = spotlightPositionY[0];
      spotlightTargetX[i] = spotlightTargetX[0];
      spotlightTargetY[i] = spotlightTargetY[0];
    }
  }

  if (updateTargets) {
    lastSpotlightMotionUpdateMs = currentMs;
  }
}

float getSpotlightRevealRadiusForMask(int maskIndex) {
  if (!spotlightKeepCirclesInsideImage || imgH <= 0.0) {
    return spotlightRevealRadius;
  }

  float imageAspect = imgW / imgH;
  float distanceToLeft = spotlightPositionX[maskIndex] * imageAspect;
  float distanceToRight = (1.0 - spotlightPositionX[maskIndex]) * imageAspect;
  float distanceToTop = spotlightPositionY[maskIndex];
  float distanceToBottom = 1.0 - spotlightPositionY[maskIndex];
  float edgeLimitedRadius = min(min(distanceToLeft, distanceToRight), min(distanceToTop, distanceToBottom));
  return max(0.0, min(spotlightRevealRadius, edgeLimitedRadius));
}

void startAudioPlaybackIfReady() {
  if (allMasksReady && isAudioReady && !useAudioInput && track != null && !audioPlaybackStarted) {
    track.loop();
    audioPlaybackStarted = true;
    lastAudioResponseMs = millis();
  }
}

int getMaxAnalysisBin() {
  float binWidth = audioSampleRate / actualAudioBufferSize;
  float effectiveMaxFrequency = min(maxFftFrequency, audioSampleRate * 0.5);
  int maxBin = ceil(effectiveMaxFrequency / binWidth);
  return constrain(maxBin, colorNames.length, fft.specSize());
}

int getBandBoundaryBin(int boundaryIndex, int maxBin) {
  float normalizedPosition = boundaryIndex / (float)colorNames.length;
  int distributableBins = maxBin - colorNames.length;
  return boundaryIndex + round(distributableBins * pow(normalizedPosition, frequencyMappingExponent));
}

int getBandStartBin(int maskIndex, int maxBin) {
  int start = getBandBoundaryBin(maskIndex, maxBin);
  int end = getBandBoundaryBin(maskIndex + 1, maxBin);
  return max(0, start - round((end - start) * bandOverlap * 0.5));
}

int getBandEndBin(int maskIndex, int maxBin) {
  int start = getBandBoundaryBin(maskIndex, maxBin);
  int end = getBandBoundaryBin(maskIndex + 1, maxBin);
  return min(maxBin, max(end + round((end - start) * bandOverlap * 0.5), getBandStartBin(maskIndex, maxBin) + 1));
}

String formatFrequency(float frequency) {
  if (frequency >= 1000.0) {
    return nf(frequency / 1000.0, 1, 2) + " kHz";
  }
  return nf(frequency, 1, 0) + " Hz";
}

void drawBandMapping(PApplet app, float panelTop) {
  int maxBin = getMaxAnalysisBin();
  float binWidth = audioSampleRate / actualAudioBufferSize;
  float effectiveMaxFrequency = min(maxFftFrequency, audioSampleRate * 0.5);
  String heading = "FFT BANDS — " + nf(audioSampleRate, 1, 0) + " Hz, " + actualAudioBufferSize + " samples, max " + formatFrequency(effectiveMaxFrequency) + ", curve " + nf(frequencyMappingExponent, 1, 2);
  String[] bandLabels = new String[colorNames.length];

  app.pushStyle();
  app.textSize(18);
  float panelWidth = app.textWidth(heading);
  for (int i = 0; i < colorNames.length; i++) {
    float startFrequency = getBandStartBin(i, maxBin) * binWidth;
    float endFrequency = min(getBandEndBin(i, maxBin) * binWidth, effectiveMaxFrequency);
    bandLabels[i] = colorNames[i].toUpperCase() + ": " + formatFrequency(startFrequency) + " - " + formatFrequency(endFrequency);
    panelWidth = max(panelWidth, app.textWidth(bandLabels[i]));
  }

  float padding = 12;
  float rowHeight = 30;
  float panelHeight = 38 + colorNames.length * rowHeight;
  app.noStroke();
  app.fill(0, 190);
  app.rect(app.width - panelWidth - padding * 2, panelTop, panelWidth + padding * 2, panelHeight);

  app.fill(255);
  app.textAlign(RIGHT, TOP);
  app.text(heading, app.width - padding, panelTop + 8);
  for (int i = 0; i < colorNames.length; i++) {
    app.text(bandLabels[i], app.width - padding, panelTop + 30 + i * rowHeight);
  }
  app.popStyle();
}

void drawStatusOverlay(PApplet app, float panelTop) {
  String maskStatus;
  if (!masksDecoded) {
    maskStatus = "PRELOADING MASKS: " +     masksDecodedCount + "/" + allColorNames.length;
  } else if (!allMasksReady) {
        maskStatus = "UPLOADING MASKS TO GPU: " + warmupIndex + "/" + allColorNames.length;
  } else {
    maskStatus = "ALL MASKS ACTIVE";
  }
  maskStatus += " | MODE: " + currentRevealMode.name() + " (M)";

  String fpsStatus = "FPS: " + app.nf(app.frameRate, 0, 1);
  if (currentRevealMode != RevealMode.FULL) {
    fpsStatus += " | ENERGY: " + nf(spotlightEnergy * 100.0, 0, 0) + "%";
  }
  String combinedStatus = maskStatus + "   " + fpsStatus;

  float padding = 18;
  float boxHeight = 44;

  app.blendMode(BLEND);
  app.noTint();
  app.textSize(24);

  // Dark translucent background keeps the green text readable over bright imagery.
  app.noStroke();
  app.fill(0, 190);
  float boxWidth = app.textWidth(combinedStatus) + padding * 2;
  app.rect(app.width - boxWidth, panelTop, boxWidth, boxHeight);

  app.fill(0, 255, 80);
  app.textAlign(RIGHT, TOP);
  app.text(combinedStatus, app.width - padding, panelTop + 8);
}

void preloadMasks() {
  // Disk access and PNG decoding happen outside the OpenGL animation thread.
  // Every colour is loaded so the mapping can be changed at runtime.
  for (int i = 0; i < allColorNames.length; i++) {
    allSolidMasks[i] = loadImage("mask_" + allColorNames[i] + "_solid.png");
    allBloomMasks[i] = loadImage("mask_" + allColorNames[i] + "_bloom.png");
    masksDecodedCount = i + 1;
  }

  synchronized (mappingLock) {
    assignActiveMasks();
  }
  // This volatile write publishes all completed array writes to draw().
  masksDecoded = true;
}

void warmUpNextMaskPair() {
  if (warmupIndex >= allColorNames.length) {
    allMasksReady = true;
    animationStartMs = millis();
    return;
  }

  // Alpha zero keeps this upload invisible while image() initializes each GPU texture.
  blendMode(BLEND);
  tint(255, 0);
  image(allSolidMasks[warmupIndex], imgX, imgY, imgW, imgH);
  image(allBloomMasks[warmupIndex], imgX, imgY, imgW, imgH);
  noTint();

  warmupIndex++;
  if (warmupIndex >= allColorNames.length) {
    allMasksReady = true;
    animationStartMs = millis();
  }
}

class ControlsWindow extends PApplet {
  float diagnosticsTop;
  float lastSilenceFloor = baseImageSilenceFloor;
  float sectionContentTop;
  int activeSection = 0;
  Button[] modeButtons;
  Button[] sectionButtons;
  Button spotlightIndependentButton;
  Button spotlightKeepInsideButton;
  Button[] areaStyleButtons;
  Slider editingSlider;

  void settings() {
    size(controlsWindowWidth, controlsWindowHeight, P2D);
  }

  void setup() {
    surface.setTitle("Music Visualizer Controls");
    surface.setResizable(false);
    surface.setLocation(40, 40);
    frameRate(fps);

    solidSliders = new Slider[colorNames.length];
    bloomSliders = new Slider[colorNames.length];
    audioSensSlider = new Slider("AUDIO SENSITIVITY", 0, 0, 0, 0, 0.0, 20.0, initialAudioSensitivity);
    baseSlider = new Slider("BASE IMAGE", 0, 0, 0, 0, 0.0, 1.0, baseIntensity);

    for (int i = 0; i < colorNames.length; i++) {
      solidSliders[i] = new Slider(colorNames[i].toUpperCase() + " SOLID", 0, 0, 0, 0, 0.0, 5.0, solidIntensities[i]);
      bloomSliders[i] = new Slider(colorNames[i].toUpperCase() + " BLOOM", 0, 0, 0, 0, 0.0, 5.0, bloomIntensities[i]);
    }

    audioResponseSliders = new RuntimeSlider[] {
      new RuntimeSlider("FFT MAX FREQUENCY", "maxFftFrequency", 1.0, 192000.0),
      new RuntimeSlider("FREQUENCY CURVE", "frequencyMappingExponent", 0.1, 20.0),
      new RuntimeSlider("BAND OVERLAP", "bandOverlap", 0.0, 0.95),
      new RuntimeSlider("BAND MULTIPLIER",       "audioBandMultiplier", 0.01, 100.0),
      new RuntimeSlider("BLOOM MULTIPLIER", "audioBloomMultiplier", 0.0, 100.0),
      new RuntimeSlider("BASE AUDIO BOOST", "audioBaseIntensityScale", 0.0, 100.0),
      new RuntimeSlider("SILENCE FLOOR", "baseImageSilenceFloor", 0.0, 1.0),
      new RuntimeSlider("ATTACK (MS)",       "audioAttackTimeMs", 0.0, 1000.0),
            new RuntimeSlider("RELEASE (MS)", "audioReleaseTimeMs", 0.0, 10000.0)
    };
    spotlightRevealSliders = new RuntimeSlider[] {
      new RuntimeSlider("ENERGY MULTIPLIER", "spotlightEnergyMultiplier", 0.0, 100.0),
      new RuntimeSlider("MINIMUM RADIUS", "spotlightMinimumRadius", 0.01, 1.0),
      new RuntimeSlider("MAXIMUM RADIUS", "spotlightMaximumRadius", 0.01, 2.0),
      new RuntimeSlider("EDGE FEATHER", "spotlightEdgeFeatherProportion", 0.0, 1.0),
      new RuntimeSlider("MOTION INTERVAL (MS)", "spotlightMotionUpdateIntervalMs", 1.0, 60000.0),
      new RuntimeSlider("BROWNIAN STEP", "spotlightBrownianStep", 0.01, 1.0),
      new RuntimeSlider("MOTION SMOOTHING (MS)", "spotlightMotionSmoothingTimeMs", 0.0, 60000.0)
    };
    areaRevealSliders = new RuntimeSlider[] {
      new RuntimeSlider("ENERGY MULTIPLIER", "areaEnergyMultiplier", 0.01, 100.0),
      new RuntimeSlider("CYCLE DURATION (S)",       "areaCycleDurationSeconds", 1.0, 100.0)
    };

    modeButtons = new Button[] {
      new Button("FULL"),
      new Button("SPOTLIGHT"),
      new Button("AREA")
    };
    sectionButtons = new Button[] {
      new Button("MASK INTENSITY"),
      new Button("AUDIO RESPONSE"),
      new Button("SPOTLIGHT REVEAL"),
      new Button("AREA REVEAL")
    };
    spotlightIndependentButton = new Button("INDEPENDENT MASK POSITIONS");
    spotlightKeepInsideButton = new Button("KEEP CIRCLES INSIDE IMAGE");
    areaStyleButtons = new Button[] {
      new Button("WHOLE TILE"),
      new Button("CENTER GLOW"),
      new Button("TRAIL")
    };
  }

  void draw() {
    synchronized (mappingLock) {
      drawControls();
    }
  }

  void rebuildMaskSliders(String[] previousNames) {
    Slider[] previousSolid = solidSliders;
    Slider[] previousBloom = bloomSliders;
    solidSliders = new Slider[colorNames.length];
    bloomSliders = new Slider[colorNames.length];
    for (int i = 0; i < colorNames.length; i++) {
      float solidValue = 0.0;
      float bloomValue = 0.0;
      float solidDefault = 0.0;
      float bloomDefault = 0.0;
      for (int j = 0; j < previousNames.length; j++) {
        if (previousNames[j].equals(colorNames[i]) && previousSolid != null && j < previousSolid.length) {
          solidValue = previousSolid[j].val;
          bloomValue = previousBloom[j].val;
          solidDefault = previousSolid[j].defaultVal;
          bloomDefault = previousBloom[j].defaultVal;
        }
      }
      solidSliders[i] = new Slider(colorNames[i].toUpperCase() + " SOLID", 0, 0, 0, 0, 0.0, 5.0, solidDefault);
      bloomSliders[i] = new Slider(colorNames[i].toUpperCase() + " BLOOM", 0, 0, 0, 0, 0.0, 5.0, bloomDefault);
      solidSliders[i].val = solidValue;
      bloomSliders[i].val = bloomValue;
    }
    editingSlider = null;
  }

  void drawControls() {
    background(24);

    if (audioSensSlider == null || baseSlider == null || solidSliders == null || bloomSliders == null) return;
    layoutControls();

    updateButtons();
    drawButtons();
    layoutActiveSection();
    updateActiveSection();
    updateMappingField();
    audioSensitivity = audioSensSlider.val;
    // The silence floor is the Base Image slider's starting level, so moving it live moves the slider.
    if (baseImageSilenceFloor != lastSilenceFloor) {
      baseSlider.val = baseImageSilenceFloor;
      lastSilenceFloor = baseImageSilenceFloor;
    }
    baseIntensity = constrain(baseSlider.val + currentAudioLevel * audioBaseIntensityScale * audioSensitivity, 0.0, 1.0);
    drawActiveSection();
    drawMappingField();

    drawStatusOverlay(this, diagnosticsTop);
    if (isAudioReady) drawBandMapping(this, diagnosticsTop + 54);
  }

  // Text box for colorBandMapping, shown at the bottom of the Audio Response section.
  boolean editingMapping = false;
  boolean mappingWasPressed = false;
  String mappingText = "";
  String mappingMessage = "";
  float mappingFieldX, mappingFieldY, mappingFieldW, mappingFieldH;

  void layoutMappingField() {
    int sliderRows = audioResponseSliders.length + 1;
    float rowSpacing = sliderRowSpacing(sliderRows + 2);
    mappingFieldX = 42.0;
    mappingFieldW = audioResponseSliders[0].leftColumnWidth();
    mappingFieldH = 52.0;
    mappingFieldY = sectionContentTop + rowSpacing * sliderRows + 40.0;
  }

  void updateMappingField() {
    boolean pressedNow = mousePressed && !mappingWasPressed;
    mappingWasPressed = mousePressed;
    if (activeSection != 1) {
      editingMapping = false;
      return;
    }
    layoutMappingField();
    if (!pressedNow) return;
    boolean hit = mouseX >= mappingFieldX && mouseX <= mappingFieldX + mappingFieldW
      && mouseY >= mappingFieldY && mouseY <= mappingFieldY + mappingFieldH;
    if (hit && !editingMapping) {
      editingMapping = true;
      mappingText = colorBandMapping;
      mappingMessage = "";
    } else if (!hit) {
      editingMapping = false;
    }
  }

  void drawMappingField() {
    if (activeSection != 1) return;
    pushStyle();
    textSize(20);
    textAlign(LEFT, BOTTOM);
    fill(210);
    text("COLOR / BAND MAPPING", mappingFieldX, mappingFieldY - 4.0);

    stroke(editingMapping ? color(0, 255, 80) : color(120));
    strokeWeight(2);
    fill(editingMapping ? 40 : 32);
    rect(mappingFieldX, mappingFieldY, mappingFieldW, mappingFieldH, 6);
    noStroke();
    fill(255);
    textSize(28);
    textAlign(LEFT, CENTER);
    String shown = editingMapping ? mappingText + ((millis() / 500) % 2 == 0 ? "_" : "") : colorBandMapping;
    text(shown, mappingFieldX + 12.0, mappingFieldY + mappingFieldH * 0.5);

    float noteX = audioResponseSliders[0].trackX();
    textSize(18);
    textAlign(LEFT, TOP);
    fill(170);
    text("Color masks and low-to-high FFT-band mapping. Use unique initials: B=blue, C=cyan,\nR=red, O=orange, Y=yellow, G=green, M=magenta. Type a sequence and press Enter.\nThe current setting uses " + colorBandMapping + ".", noteX, mappingFieldY);
    if (mappingMessage.length() > 0) {
      fill(255, 120, 90);
      text(mappingMessage, noteX, mappingFieldY + 66.0);
    }
    popStyle();
  }

  boolean handleMappingKey(char typedKey, int typedKeyCode) {
    if (typedKeyCode == ESC) {
      editingMapping = false;
    } else if (typedKeyCode == ENTER || typedKeyCode == RETURN) {
      String candidate = mappingText.replaceAll("\\s", "").toUpperCase();
      if (getColorNames(candidate) == null) {
        mappingMessage = "Invalid: use unique initials from B C R O Y G M.";
      } else {
        pendingColorBandMapping = candidate;
        mappingMessage = "";
        editingMapping = false;
      }
    } else if (typedKeyCode == BACKSPACE) {
      if (mappingText.length() > 0) mappingText = mappingText.substring(0, mappingText.length() - 1);
    } else if (Character.isLetter(typedKey) && mappingText.length() < allColorNames.length) {
      mappingText += Character.toUpperCase(typedKey);
    }
    return true;
  }

  void layoutControls() {
    float margin = 42.0;
    float diagnosticsHeight = 270.0;
    diagnosticsTop = max(330.0, height - diagnosticsHeight);
    float buttonGap = 12.0;
    float modeWidth = (width - margin * 2.0 - buttonGap * 2.0) / 3.0;
    for (int i = 0; i < modeButtons.length; i++) {
      modeButtons[i].setBounds(margin + i * (modeWidth + buttonGap), 30.0, modeWidth, 54.0);
    }

    float sectionWidth = (width - margin * 2.0 - buttonGap * 3.0) / 4.0;
    for (int i = 0; i < sectionButtons.length; i++) {
      sectionButtons[i].setBounds(margin + i * (sectionWidth + buttonGap), 106.0, sectionWidth, 54.0);
    }
    sectionContentTop = sectionButtons[0].y + sectionButtons[0].h + 24.0;
  }

  void updateButtons() {
    for (int i = 0; i < modeButtons.length; i++) {
      if (modeButtons[i].update(mouseX, mouseY, mousePressed)) {
        currentRevealMode = RevealMode.values()[i];
        if (currentRevealMode == RevealMode.SPOTLIGHT) {
          lastSpotlightMotionUpdateMs = millis() - round(spotlightMotionUpdateIntervalMs);
        }
      }
    }
    for (int i = 0; i < sectionButtons.length; i++) {
      if (sectionButtons[i].update(mouseX, mouseY, mousePressed)) activeSection = i;
    }
    if (activeSection == 2) {
      if (spotlightIndependentButton.update(mouseX, mouseY, mousePressed)) {
        spotlightIndependentMaskPositions = !spotlightIndependentMaskPositions;
      }
      if (spotlightKeepInsideButton.update(mouseX, mouseY, mousePressed)) {
        spotlightKeepCirclesInsideImage = !spotlightKeepCirclesInsideImage;
      }
    } else if (activeSection == 3) {
      for (int i = 0; i < areaStyleButtons.length; i++) {
        if (areaStyleButtons[i].update(mouseX, mouseY, mousePressed)) {
          areaRevealStyle = AreaRevealStyle.values()[i];
        }
      }
    }
  }

  void drawButtons() {
    for (int i = 0; i < modeButtons.length; i++) {
      modeButtons[i].draw(this, currentRevealMode.ordinal() == i);
    }
    for (int i = 0; i < sectionButtons.length; i++) {
      sectionButtons[i].draw(this, activeSection == i);
    }
  }

  void updateActiveSection() {
    if (editingSlider == null) {
      Slider[] activeSliders = getActiveSliders();
      for (Slider slider : activeSliders) {
        if (slider.beginEditing(mouseX, mouseY, mousePressed)) {
          editingSlider = slider;
          return;
        }
      }
    } else {
      return;
    }

    if (activeSection == 0) {
      baseSlider.update(mouseX, mouseY, mousePressed);
      for (int i = 0; i < colorNames.length; i++) {
        solidSliders[i].update(mouseX, mouseY, mousePressed);
        bloomSliders[i].update(mouseX, mouseY, mousePressed);
      }
    } else if (activeSection == 1) {
      audioSensSlider.update(mouseX, mouseY, mousePressed);
      updateRuntimeSliders(audioResponseSliders);
    } else if (activeSection == 2) {
      updateRuntimeSliders(spotlightRevealSliders);
    } else {
      updateRuntimeSliders(areaRevealSliders);
    }
  }

  Slider[] getAudioResponseSliders() {
    Slider[] sliders = new Slider[audioResponseSliders.length + 1];
    sliders[0] = audioSensSlider;
    for (int i = 0; i < audioResponseSliders.length; i++) sliders[i + 1] = audioResponseSliders[i];
    return sliders;
  }

  Slider[] getActiveSliders() {
    if (activeSection == 0) {
      Slider[] visualSliders = new Slider[1 + colorNames.length * 2];
      visualSliders[0] = baseSlider;
      for (int i = 0; i < colorNames.length; i++) {
        visualSliders[i * 2 + 1] = solidSliders[i];
        visualSliders[i * 2 + 2] = bloomSliders[i];
      }
      return visualSliders;
    }
    if (activeSection == 1) return getAudioResponseSliders();
    if (activeSection == 2) return spotlightRevealSliders;
    return areaRevealSliders;
  }

  void drawActiveSection() {
    if (activeSection == 0) {
      baseSlider.draw(this);
      for (int i = 0; i < colorNames.length; i++) {
        solidSliders[i].draw(this);
        bloomSliders[i].draw(this);
      }
    } else if (activeSection == 1) {
      audioSensSlider.draw(this);
      drawRuntimeSliders(audioResponseSliders);
    } else if (activeSection == 2) {
      drawRuntimeSliders(spotlightRevealSliders);
      spotlightIndependentButton.draw(this, spotlightIndependentMaskPositions);
      spotlightKeepInsideButton.draw(this, spotlightKeepCirclesInsideImage);
    } else {
      drawRuntimeSliders(areaRevealSliders);
      for (int i = 0; i < areaStyleButtons.length; i++) {
        areaStyleButtons[i].draw(this, areaRevealStyle.ordinal() == i);
      }
    }
  }

  void layoutActiveSection() {
    if (activeSection == 0) {
      Slider[] visualSliders = getActiveSliders();
      layoutSliders(visualSliders, sectionContentTop);
    } else if (activeSection == 1) {
      Slider[] audioSliders = getAudioResponseSliders();
      layoutSliders(audioSliders, sectionContentTop, audioSliders.length + 2);
    } else if (activeSection == 2) {
      int controlRows = spotlightRevealSliders.length + 1;
      layoutSliders(spotlightRevealSliders, sectionContentTop, controlRows);
      float y = sectionContentTop + sliderRowSpacing(controlRows) * spotlightRevealSliders.length + 8.0;
      float buttonWidth = (width - 96.0) * 0.5;
      spotlightIndependentButton.setBounds(42.0, y, buttonWidth, 52.0);
      spotlightKeepInsideButton.setBounds(54.0 + buttonWidth, y, buttonWidth, 52.0);
    } else {
      int controlRows = areaRevealSliders.length + 1;
      layoutSliders(areaRevealSliders, sectionContentTop, controlRows);
      float y = sectionContentTop + sliderRowSpacing(controlRows) * areaRevealSliders.length + 8.0;
      float buttonGap = 12.0;
      float buttonWidth = (width - 84.0 - buttonGap * 2.0) / areaStyleButtons.length;
      for (int i = 0; i < areaStyleButtons.length; i++) {
        areaStyleButtons[i].setBounds(42.0 + i * (buttonWidth + buttonGap), y, buttonWidth, 52.0);
      }
    }
  }

  void layoutSliders(Slider[] sliders, float top) {
    layoutSliders(sliders, top, sliders.length);
  }

  void layoutSliders(Slider[] sliders, float top, int controlRows) {
    float margin = 42.0;
    float rowSpacing = sliderRowSpacing(controlRows);
    float touchDiameter = constrain(rowSpacing * 0.62, 22.0, 36.0);
    float sliderWidth = max(160.0, width - margin * 2.0);
    for (int i = 0; i < sliders.length; i++) {
      sliders[i].setBounds(margin, top + (i + 0.5) * rowSpacing, sliderWidth, touchDiameter);
    }
  }

  float sliderRowSpacing(int controlCount) {
    return (diagnosticsTop - sectionContentTop) / max(1, controlCount);
  }

  void updateRuntimeSliders(RuntimeSlider[] sliders) {
    for (RuntimeSlider slider : sliders) slider.updateAndApply(mouseX, mouseY, mousePressed);
  }

  void drawRuntimeSliders(RuntimeSlider[] sliders) {
    for (RuntimeSlider slider : sliders) slider.draw(this);
  }

  void keyPressed() {
    synchronized (mappingLock) {
      if (editingMapping) {
        boolean escapePressed = keyCode == ESC;
        handleMappingKey(key, keyCode);
        if (escapePressed) key = 0;
        return;
      }
      if (editingSlider != null) {
        boolean escapePressed = keyCode == ESC;
        if (editingSlider.handleKey(key, keyCode)) editingSlider = null;
        if (escapePressed) key = 0;
        return;
      }
      handleKeyPressed();
    }
  }
}

class Slider {
  float x, y, w, h;
  float minVal, maxVal;
  float val;
  String label;
  boolean dragging = false;
  boolean wasPressed = false;
  boolean editing = false;
  String editText = "";
  boolean replaceEditText = false;
  float defaultVal;
  int lastPressMs = -10000;
  float lastPressX, lastPressY;

  Slider(String label, float x, float y, float w, float h, float minVal, float maxVal, float defaultVal) {
    this.defaultVal = defaultVal;
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.minVal = minVal;
    this.maxVal = maxVal;
    this.val = defaultVal;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void update(int mx, int my, boolean mPressed) {
    if (mPressed && !wasPressed) {
      // Just pressed
      if (mx >= trackX() - h * 0.5 && mx <= x + w + h * 0.5 && my >= y - h && my <= y + h) {
        dragging = true;
        int now = millis();
        boolean doubleClick = now - lastPressMs <= DOUBLE_CLICK_MS
          && dist(mx, my, lastPressX, lastPressY) <= DOUBLE_CLICK_DISTANCE;
        lastPressMs = doubleClick ? -10000 : now;
        lastPressX = mx;
        lastPressY = my;
        if (doubleClick) {
          dragging = false;
          resetToDefault();
        }
      }
    } else if (!mPressed) {
      dragging = false;
    }

    if (dragging) {
      val = map(mx, trackX(), trackX() + trackWidth(), minVal, maxVal);
      val = constrain(val, minVal, maxVal);
    }
    wasPressed = mPressed;
  }

  void resetToDefault() {
    val = constrain(defaultVal, minVal, maxVal);
  }

  boolean beginEditing(int mx, int my, boolean mPressed) {
    if (!mPressed || wasPressed || !isValueFieldHit(mx, my)) return false;
    editText = nf(val, 1, 2);
    editing = true;
    replaceEditText = true;
    return true;
  }

  boolean handleKey(char typedKey, int typedKeyCode) {
    if (typedKeyCode == ENTER || typedKeyCode == RETURN) {
      try {
        applyEditedValue(Float.parseFloat(editText));
        editing = false;
        replaceEditText = false;
        return true;
      }
      catch (NumberFormatException error) {
        println("Invalid value for " + label + ": " + editText);
        return false;
      }
    }
    if (typedKeyCode == ESC) {
      editing = false;
      replaceEditText = false;
      return true;
    }
    if (typedKeyCode == BACKSPACE) {
      if (replaceEditText) {
        editText = "";
        replaceEditText = false;
        return false;
      }
      if (editText.length() > 0) editText = editText.substring(0, editText.length() - 1);
      return false;
    }
    if (typedKey >= '0' && typedKey <= '9' || typedKey == '.' || typedKey == '-' || typedKey == '+' || typedKey == 'e' || typedKey == 'E') {
      if (replaceEditText) {
        editText = "";
        replaceEditText = false;
      }
      editText += typedKey;
    }
    return false;
  }

  void applyEditedValue(float value) {
    val = constrain(value, minVal, maxVal);
  }

  // Two-column row: label and value box on the left, slider track on the right.
  float leftColumnWidth() {
    return constrain(w * 0.26, 300.0, 380.0);
  }

  float trackX() {
    return x + leftColumnWidth() + 16.0;
  }

  float trackWidth() {
    return max(60.0, x + w - h * 0.5 - trackX());
  }

  float valueFieldWidth() {
    return 130.0;
  }

  float valueFieldHeight() {
    return max(32.0, h * 1.1);
  }

  float valueFieldX() {
    return x + leftColumnWidth() - valueFieldWidth();
  }

  float valueFieldY() {
    return y - valueFieldHeight() * 0.5;
  }

  boolean isValueFieldHit(int mx, int my) {
    return mx >= valueFieldX() && mx <= valueFieldX() + valueFieldWidth()
      && my >= valueFieldY() && my <= valueFieldY() + valueFieldHeight();
  }

  void draw(PApplet app) {
    app.pushStyle();
    app.fill(100, 200);
    app.noStroke();
    float trackHeight = max(8.0, h * 0.2);
    float tx = trackX();
    app.rect(tx, y - trackHeight * 0.5, trackWidth(), trackHeight);
    app.fill(200, 200);
    float px = app.map(val, minVal, maxVal, tx, tx + trackWidth());
    app.rect(tx, y - trackHeight * 0.5, px - tx, trackHeight);
    app.fill(255);
    app.ellipse(px, y, h, h);
    app.fill(255);
    app.textAlign(LEFT, CENTER);
    app.textSize(max(18.0, h * 0.52));
    app.text(label, x, y);
    app.fill(editing ? app.color(45, 125, 185) : app.color(55, 55, 62));
    app.rect(valueFieldX(), valueFieldY(), valueFieldWidth(), valueFieldHeight(), 6);
    app.fill(255);
    app.textAlign(CENTER, CENTER);
    app.text(editing ? editText : app.nf(val, 1, 2), valueFieldX() + valueFieldWidth() * 0.5, valueFieldY() + valueFieldHeight() * 0.5);
    app.popStyle();
  }
}

class RuntimeSlider extends Slider {
  String parameter;

  RuntimeSlider(String label, String parameter, float minVal, float maxVal) {
    super(label, 0, 0, 0, 0, minVal, maxVal, 0.0);
    this.parameter = parameter;
    val = getParameterValue();
    defaultVal = val;
  }

  void updateAndApply(int mx, int my, boolean mPressed) {
    if (!dragging) val = getParameterValue();
    update(mx, my, mPressed);
    setParameterValue(val);
    val = getParameterValue();
  }

  float getParameterValue() {
    if (parameter.equals("maxFftFrequency")) return maxFftFrequency;
    if (parameter.equals("frequencyMappingExponent")) return frequencyMappingExponent;
    if (parameter.equals("bandOverlap")) return bandOverlap;
    if (parameter.equals("audioBandMultiplier")) return audioBandMultiplier;
    if (parameter.equals("audioBloomMultiplier")) return audioBloomMultiplier;
    if (parameter.equals("audioBaseIntensityScale")) return audioBaseIntensityScale;
    if (parameter.equals("baseImageSilenceFloor")) return baseImageSilenceFloor;
    if (parameter.equals("audioAttackTimeMs")) return audioAttackTimeMs;
    if (parameter.equals("audioReleaseTimeMs")) return audioReleaseTimeMs;
    if (parameter.equals("spotlightEnergyMultiplier")) return spotlightEnergyMultiplier;
    if (parameter.equals("spotlightMinimumRadius")) return spotlightMinimumRadius;
    if (parameter.equals("spotlightMaximumRadius")) return spotlightMaximumRadius;
    if (parameter.equals("spotlightEdgeFeatherProportion")) return spotlightEdgeFeatherProportion;
    if (parameter.equals("spotlightMotionUpdateIntervalMs")) return spotlightMotionUpdateIntervalMs;
    if (parameter.equals("spotlightBrownianStep")) return spotlightBrownianStep;
    if (parameter.equals("spotlightMotionSmoothingTimeMs")) return spotlightMotionSmoothingTimeMs;
    if (parameter.equals("areaEnergyMultiplier")) return areaEnergyMultiplier;
    if (parameter.equals("areaCycleDurationSeconds")) return areaCycleDurationSeconds;
    return minVal;
  }

  void setParameterValue(float value) {
    if (parameter.equals("maxFftFrequency")) maxFftFrequency = value;
    else if (parameter.equals("frequencyMappingExponent")) frequencyMappingExponent = value;
    else if (parameter.equals("bandOverlap")) bandOverlap = value;
    else if (parameter.equals("audioBandMultiplier")) audioBandMultiplier = value;
    else if (parameter.equals("audioBloomMultiplier")) audioBloomMultiplier = value;
    else if (parameter.equals("audioBaseIntensityScale")) audioBaseIntensityScale = value;
    else if (parameter.equals("baseImageSilenceFloor")) baseImageSilenceFloor = value;
    else if (parameter.equals("audioAttackTimeMs")) audioAttackTimeMs = value;
    else if (parameter.equals("audioReleaseTimeMs")) audioReleaseTimeMs = value;
    else if (parameter.equals("spotlightEnergyMultiplier")) spotlightEnergyMultiplier = value;
    else if (parameter.equals("spotlightMinimumRadius")) spotlightMinimumRadius = min(value, spotlightMaximumRadius);
    else if (parameter.equals("spotlightMaximumRadius")) spotlightMaximumRadius = max(value, spotlightMinimumRadius);
    else if (parameter.equals("spotlightEdgeFeatherProportion")) spotlightEdgeFeatherProportion = value;
    else if (parameter.equals("spotlightMotionUpdateIntervalMs")) spotlightMotionUpdateIntervalMs = value;
    else if (parameter.equals("spotlightBrownianStep")) spotlightBrownianStep = value;
    else if (parameter.equals("spotlightMotionSmoothingTimeMs")) spotlightMotionSmoothingTimeMs = value;
    else if (parameter.equals("areaEnergyMultiplier")) areaEnergyMultiplier = value;
    else if (parameter.equals("areaCycleDurationSeconds")) areaCycleDurationSeconds = value;
  }

  void applyEditedValue(float value) {
    val = constrain(value, minVal, maxVal);
    setParameterValue(val);
    val = getParameterValue();
  }
}

class Button {
  String label;
  float x, y, w, h;
  boolean wasPressed;

  Button(String label) {
    this.label = label;
  }

  void setBounds(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  boolean update(int mx, int my, boolean mPressed) {
    boolean clicked = mPressed && !wasPressed && mx >= x && mx <= x + w && my >= y && my <= y + h;
    wasPressed = mPressed;
    return clicked;
  }

  void draw(PApplet app, boolean selected) {
    app.pushStyle();
    app.noStroke();
    app.fill(selected ? app.color(30, 150, 210) : app.color(70, 70, 76));
    app.rect(x, y, w, h, 10);
    app.fill(255);
    app.textAlign(CENTER, CENTER);
    app.textSize(min(20.0, max(14.0, h * 0.35)));
    app.text(label, x + w * 0.5, y + h * 0.5);
    app.popStyle();
  }
}

void setupAudio() {
  surface.setVisible(false);

  int result = promptForInputMethod();
  if (result == -1) {
    isCancelled = true;
    surface.setVisible(true);
    return;
  }
  useAudioInput = (result == 1);

  if (!useAudioInput) {
    String path = promptForAudioFile();
    if (path != null) audioFileName = path;
    else {
      isCancelled = true;
      surface.setVisible(true);
      return;
    }
  }

  minim = new Minim(this);

  if (useAudioInput) {
    Mixer.Info[] mixerInfo = AudioSystem.getMixerInfo();
    ArrayList<String> inputNames = new ArrayList<String>();
    ArrayList<Mixer.Info> inputMixers = new ArrayList<Mixer.Info>();

    for (int i = 0; i < mixerInfo.length; i++) {
      Mixer m = AudioSystem.getMixer(mixerInfo[i]);
      boolean hasTargetDataLine = false;
      int maxChannels = 0;
      for (javax.sound.sampled.Line.Info info : m.getTargetLineInfo()) {
        if (info instanceof javax.sound.sampled.TargetDataLine.Info) {
          hasTargetDataLine = true;
          javax.sound.sampled.DataLine.Info dataInfo = (javax.sound.sampled.DataLine.Info) info;
          for (javax.sound.sampled.AudioFormat format : dataInfo.getFormats()) {
            if (format.getChannels() != javax.sound.sampled.AudioSystem.NOT_SPECIFIED && format.getChannels() > maxChannels) {
              maxChannels = format.getChannels();
            }
          }
        }
      }

      if (hasTargetDataLine) {
        String name = mixerInfo[i].getName();
        String desc = mixerInfo[i].getDescription();
        String vendor = mixerInfo[i].getVendor();
        String channelStr = maxChannels > 0 ? (maxChannels + " ch") : "Unknown ch";
        String displayName = String.format("%s  [%s]  (%s) {%s}", name, desc, channelStr, vendor);
        inputNames.add(displayName);
        inputMixers.add(mixerInfo[i]);
      }
    }

    int inputType = Minim.STEREO;

    if (inputNames.size() > 0) {
      String[] optionsArray = inputNames.toArray(new String[0]);
      java.util.Arrays.sort(optionsArray, String.CASE_INSENSITIVE_ORDER);
      String selected = promptForMixer(optionsArray);

      if (selected != null) {
        int idx = inputNames.indexOf(selected);
        Mixer mixer = AudioSystem.getMixer(inputMixers.get(idx));
        minim.setInputMixer(mixer);

        boolean supportsMono = false;
        boolean supportsStereo = false;

        javax.sound.sampled.Line.Info[] targetInfos = mixer.getTargetLineInfo();
        for (javax.sound.sampled.Line.Info info : targetInfos) {
          if (info instanceof javax.sound.sampled.DataLine.Info) {
            javax.sound.sampled.DataLine.Info dataInfo = (javax.sound.sampled.DataLine.Info) info;
            for (javax.sound.sampled.AudioFormat format : dataInfo.getFormats()) {
              if (format.getChannels() == 1) {
                supportsMono = true;
              }
              if (format.getChannels() >= 2 || format.getChannels() == javax.sound.sampled.AudioSystem.NOT_SPECIFIED) {
                supportsStereo = true;
              }
            }
          }
        }

        if (supportsMono && supportsStereo) {
          int formatSel = promptForFormatSelection();
          if (formatSel == -1) {
            isCancelled = true;
            surface.setVisible(true);
            return;
          }
          inputType = (formatSel == 0) ? Minim.MONO : Minim.STEREO;
        } else if (supportsStereo) {
          inputType = Minim.STEREO;
        } else {
          inputType = Minim.MONO;
        }
      } else {
        isCancelled = true;
        surface.setVisible(true);
        return;
      }
    }

    in = minim.getLineIn(inputType, audioBufferSize);
    actualAudioBufferSize = in.bufferSize();
    audioSampleRate = in.sampleRate();
    fft = new FFT(actualAudioBufferSize, audioSampleRate);
  } else {
    track = minim.loadFile(audioFileName, audioBufferSize);
    if (track != null) {
      actualAudioBufferSize = track.bufferSize();
      audioSampleRate = track.sampleRate();
      fft = new FFT(actualAudioBufferSize, audioSampleRate);
    } else {
      isCancelled = true;
      surface.setVisible(true);
      return;
    }
  }

  isAudioReady = true;
  surface.setVisible(true);
}

int promptForInputMethod() {
  Object[] options = {"Audio File", "Audio Input"};
  JOptionPane pane = new JOptionPane("Select Audio Source:", JOptionPane.QUESTION_MESSAGE, JOptionPane.YES_NO_OPTION, null, options, options[0]);
  JDialog dialog = pane.createDialog(null, "Input Selection");
  dialog.setAlwaysOnTop(true);
  dialog.setVisible(true);
  Object selectedValue = pane.getValue();
  if (selectedValue == null || selectedValue.equals(JOptionPane.UNINITIALIZED_VALUE)) return -1;
  if (selectedValue.equals(options[0])) return 0;
  if (selectedValue.equals(options[1])) return 1;
  return -1;
}

String promptForAudioFile() {
  JFileChooser chooser = new JFileChooser() {
    @Override
      protected JDialog createDialog(java.awt.Component parent) throws java.awt.HeadlessException {
      JDialog dialog = super.createDialog(parent);
      dialog.setAlwaysOnTop(true);
      return dialog;
    }
  };
  chooser.setDialogTitle("Select Audio File");
  FileNameExtensionFilter filter = new FileNameExtensionFilter("Audio Files (.mp3, .wav, .aiff, .flac)", "mp3", "wav", "aiff", "flac");
  chooser.setFileFilter(filter);
  chooser.setCurrentDirectory(new File(dataPath("")));

  int returnVal = chooser.showOpenDialog(null);
  if (returnVal == JFileChooser.APPROVE_OPTION) {
    return chooser.getSelectedFile().getAbsolutePath();
  }
  return null;
}

int promptForFormatSelection() {
  Object[] options = {"Mono", "Stereo"};
  JOptionPane pane = new JOptionPane("Select Audio Format:", JOptionPane.QUESTION_MESSAGE, JOptionPane.YES_NO_OPTION, null, options, options[1]);
  JDialog dialog = pane.createDialog(null, "Format Selection");
  dialog.setAlwaysOnTop(true);
  dialog.setVisible(true);
  Object selectedValue = pane.getValue();
  if (selectedValue == null || selectedValue.equals(JOptionPane.UNINITIALIZED_VALUE)) return -1;
  if (selectedValue.equals(options[0])) return 0;
  if (selectedValue.equals(options[1])) return 1;
  return -1;
}

String promptForMixer(String[] optionsArray) {
  JOptionPane pane = new JOptionPane("Select Audio Input Device/Channel:", JOptionPane.QUESTION_MESSAGE, JOptionPane.DEFAULT_OPTION, null, null, null);
  pane.setWantsInput(true);
  pane.setSelectionValues(optionsArray);
  pane.setInitialSelectionValue(optionsArray[0]);
  JDialog dialog = pane.createDialog(null, "Input Selection");
  dialog.setAlwaysOnTop(true);
  dialog.setVisible(true);
  Object selectedValue = pane.getInputValue();
  if (selectedValue == JOptionPane.UNINITIALIZED_VALUE || selectedValue == null) return null;
  return (String) selectedValue;
}
