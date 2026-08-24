import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;
import ddf.minim.signals.*;
import ddf.minim.spi.*;
import ddf.minim.ugens.*;

import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Mixer;
import java.util.ArrayList;
import java.util.Properties;

import javax.swing.JFileChooser;
import javax.swing.filechooser.FileNameExtensionFilter;
import javax.swing.JOptionPane;
import javax.swing.JDialog;
import java.io.File;
import java.io.InputStream;

PImage baseImg;
PImage[] solidMasks;
PImage[] bloomMasks;
PShader spatialRevealShader;
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
int fps = 30;
boolean showVerboseUi = false;

// Audio Configuration
int audioBufferSize = 2048;           // Size of the audio buffer (also dictates FFT resolution)
float maxFftFrequency = 20000.0;       // The maximum frequency (Hz) analyzed and mapped across the masks
float frequencyMappingExponent = 3.5; // 1.0 is linear; higher values give lower frequencies more masks
float audioBandMultiplier = 0.1;      // Base scaling factor for the real-time FFT band amplitudes
float audioBloomMultiplier = 1.0;     // Indicates how much more the bloom reacts compared to solid masks
float initialAudioSensitivity = 2.0;  // Initial value for the audio sensitivity slider
float audioBaseIntensityScale = 0.5;  // How much the overall audio energy boosts the base image brightness
float baseImageSilenceFloor = 0.0;    // The base image brightness (baseline) before audio boosts it
float audioAttackTimeMs = 50.0;       // Time constant for colored areas to rise toward a higher audio level
float audioReleaseTimeMs = 500.0;     // Time constant for colored areas to fade after their audio level falls
float audioSampleRate = 0.0;
int actualAudioBufferSize = audioBufferSize;

// Spatial Reveal Mode
boolean startInSpatialRevealMode = false;       // Start with moving spotlights instead of full-mask illumination
float spatialEnergyMultiplier = 1.0;            // Scales audio level before converting it to spotlight area
float spatialMinimumRadius = 0.04;              // Quiet-sound radius as a fraction of the image height
float spatialMaximumRadius = 0.5;               // Loud-sound radius; 0.5 covers the circular image when centered
float spatialEdgeFeather = 0.035;               // Width of the soft spotlight edge in image-height units
float spatialMotionUpdateIntervalMs = 1000.0;    // Milliseconds between new Brownian motion targets
float spatialBrownianStep = 0.05;               // Maximum typical target movement as a fraction of image size
float spatialMotionSmoothingTimeMs = 500.0;     // Time constant used to glide toward each new target
boolean spatialIndependentMaskPositions = true; // Give each color mask its own moving spotlight
boolean spatialKeepCirclesInsideImage = true;   // Recenter and limit spotlights so edges never clip them


// Different mappings can be obtained changing the order of the color names in this array.
String[] colorNames = {
  // "red", "orange", "yellow", "green", "cyan", "blue", "magenta"
  // "magenta", "blue", "cyan", "green", "yellow", "orange", "red"
  // "magenta", "blue", "green", "cyan", "red", "orange", "yellow"
  "blue", "cyan", "red", "orange", "yellow"
};
float[] solidIntensities = new float[colorNames.length];
float[] bloomIntensities = new float[colorNames.length];
float[] releasedBandIntensities = new float[colorNames.length];
float baseIntensity = baseImageSilenceFloor;
float audioSensitivity = initialAudioSensitivity;
int lastAudioResponseMs = 0;

boolean spatialRevealMode = false;
float spatialEnergy = 0.0;
float spatialRevealRadius = 0.0;
float[] spatialPositionX = new float[colorNames.length];
float[] spatialPositionY = new float[colorNames.length];
float[] spatialTargetX = new float[colorNames.length];
float[] spatialTargetY = new float[colorNames.length];
int lastSpatialMotionUpdateMs = 0;

Slider[] solidSliders;
Slider[] bloomSliders;
Slider baseSlider;
Slider audioSensSlider;

static
{
  // Forces 1:1 pixel rendering by disabling OS-level DPI scaling

  System.setProperty("sun.java2d.uiScale", "1.01"); // If this is 1.0 it does NOT work!
  //System.setProperty("sun.java2d.DPIscaling", "false"); // No effect.
}

void settings() {
  loadParameters();
  if (useFullScreen) {
    fullScreen(P2D);
  } else {
    size(canvasWidth, canvasHeight, P2D);
  }
}

void setup() {
  frameRate(fps);
  baseIntensity = baseImageSilenceFloor;
  audioSensitivity = initialAudioSensitivity;
  actualAudioBufferSize = audioBufferSize;
  spatialRevealMode = startInSpatialRevealMode;
  spatialRevealRadius = spatialMinimumRadius;
  //smooth(4); // Reduced from 8 since Retina density already makes lines crisp
  //pixelDensity(displayDensity());

  // Load the base image immediately, then decode every mask in a background thread.
  baseImg = loadImage("window_base.png");
  spatialRevealShader = loadShader("spatial_reveal.glsl");
  solidMasks = new PImage[colorNames.length];
  bloomMasks = new PImage[colorNames.length];

  if (baseImg != null) {
    // Calculate scaling to fit the fullscreen window
    float scaleRatio = min((float)width / baseImg.width, (float)height / baseImg.height);
    imgW = baseImg.width * scaleRatio;
    imgH = baseImg.height * scaleRatio;
    imgX = (width - imgW) / 2;
    imgY = (height - imgH) / 2;
  }

  solidSliders = new Slider[colorNames.length];
  bloomSliders = new Slider[colorNames.length];
  baseSlider = new Slider("BASE IMAGE", 20, 60, 150, 12, 0.0, 1.0, baseIntensity);
  audioSensSlider = new Slider("AUDIO SENSITIVITY", 20, 20, 150, 12, 0.0, 20.0, initialAudioSensitivity);

  for (int i = 0; i < colorNames.length; i++) {
    solidIntensities[i] = 0.0; // Default solid intensity
    bloomIntensities[i] = 0.0;  // Default bloom intensity
    spatialPositionX[i] = 0.5;
    spatialPositionY[i] = 0.5;
    spatialTargetX[i] = 0.5;
    spatialTargetY[i] = 0.5;

    int yBase = 100 + i * 55;
    solidSliders[i] = new Slider(colorNames[i].toUpperCase() + " SOLID", 20, yBase, 150, 12, 0.0, 5.0, solidIntensities[i]);
    bloomSliders[i] = new Slider(colorNames[i].toUpperCase() + " BLOOM", 20, yBase + 25, 150, 12, 0.0, 5.0, bloomIntensities[i]);
  }

  thread("preloadMasks");
  thread("setupAudio");
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
  fps = getIntParameter(parameters, "fps", fps, 1, 240);
  showVerboseUi = getBooleanParameter(parameters, "showVerboseUi", showVerboseUi);

  int requestedBufferSize = getIntParameter(parameters, "audioBufferSize", audioBufferSize, 32, 65536);
  if ((requestedBufferSize & (requestedBufferSize - 1)) == 0) {
    audioBufferSize = requestedBufferSize;
  } else {
    println("Ignoring audioBufferSize: value must be a power of two.");
  }

  maxFftFrequency = getFloatParameter(parameters, "maxFftFrequency", maxFftFrequency, 1.0, 192000.0);
  frequencyMappingExponent = getFloatParameter(parameters, "frequencyMappingExponent", frequencyMappingExponent, 0.1, 20.0);
  audioBandMultiplier = getFloatParameter(parameters, "audioBandMultiplier", audioBandMultiplier, 0.0, 100.0);
  audioBloomMultiplier = getFloatParameter(parameters, "audioBloomMultiplier", audioBloomMultiplier, 0.0, 100.0);
  initialAudioSensitivity = getFloatParameter(parameters, "initialAudioSensitivity", initialAudioSensitivity, 0.0, 20.0);
  audioBaseIntensityScale = getFloatParameter(parameters, "audioBaseIntensityScale", audioBaseIntensityScale, 0.0, 100.0);
  baseImageSilenceFloor = getFloatParameter(parameters, "baseImageSilenceFloor", baseImageSilenceFloor, 0.0, 1.0);
  audioAttackTimeMs = getFloatParameter(parameters, "audioAttackTimeMs", audioAttackTimeMs, 0.0, 60000.0);
  audioReleaseTimeMs = getFloatParameter(parameters, "audioReleaseTimeMs", audioReleaseTimeMs, 0.0, 60000.0);

  startInSpatialRevealMode = getBooleanParameter(parameters, "startInSpatialRevealMode", startInSpatialRevealMode);
  spatialEnergyMultiplier = getFloatParameter(parameters, "spatialEnergyMultiplier", spatialEnergyMultiplier, 0.0, 100.0);
  spatialMinimumRadius = getFloatParameter(parameters, "spatialMinimumRadius", spatialMinimumRadius, 0.0, 2.0);
  spatialMaximumRadius = getFloatParameter(parameters, "spatialMaximumRadius", spatialMaximumRadius, spatialMinimumRadius, 2.0);
  spatialEdgeFeather = getFloatParameter(parameters, "spatialEdgeFeather", spatialEdgeFeather, 0.0, 0.5);
  spatialMotionUpdateIntervalMs = getFloatParameter(parameters, "spatialMotionUpdateIntervalMs", spatialMotionUpdateIntervalMs, 1.0, 60000.0);
  spatialBrownianStep = getFloatParameter(parameters, "spatialBrownianStep", spatialBrownianStep, 0.0, 1.0);
  spatialMotionSmoothingTimeMs = getFloatParameter(parameters, "spatialMotionSmoothingTimeMs", spatialMotionSmoothingTimeMs, 0.0, 60000.0);
  spatialIndependentMaskPositions = getBooleanParameter(parameters, "spatialIndependentMaskPositions", spatialIndependentMaskPositions);
  spatialKeepCirclesInsideImage = getBooleanParameter(parameters, "spatialKeepCirclesInsideImage", spatialKeepCirclesInsideImage);
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

void draw() {
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

  // Update sliders
  if (solidSliders != null && bloomSliders != null && baseSlider != null && audioSensSlider != null) {
    boolean mPressed = mousePressed;

    audioSensSlider.update(mouseX, mouseY, mPressed);
    audioSensitivity = audioSensSlider.val;

    baseSlider.update(mouseX, mouseY, mPressed);
    baseIntensity = baseSlider.val + (currentLevel * audioBaseIntensityScale * audioSensitivity);
    baseIntensity = constrain(baseIntensity, 0.0, 1.0);

    int currentAudioResponseMs = millis();
    float elapsedMs = lastAudioResponseMs == 0 ? 1000.0 / fps : currentAudioResponseMs - lastAudioResponseMs;
    lastAudioResponseMs = currentAudioResponseMs;
    float attackAmount = audioAttackTimeMs <= 0.0 ? 1.0 : 1.0 - exp(-elapsedMs / audioAttackTimeMs);
    float releaseAmount = audioReleaseTimeMs <= 0.0 ? 1.0 : 1.0 - exp(-elapsedMs / audioReleaseTimeMs);

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

      solidSliders[i].update(mouseX, mouseY, mPressed);
      solidIntensities[i] = solidSliders[i].val + releasedBandIntensities[i];

      bloomSliders[i].update(mouseX, mouseY, mPressed);
      bloomIntensities[i] = bloomSliders[i].val + releasedBandIntensities[i] * audioBloomMultiplier;
    }

    updateSpatialReveal(currentLevel, currentAudioResponseMs, elapsedMs, attackAmount, releaseAmount);
  }

  if (baseImg != null) {
    // Draw the unmodified source image first.
    blendMode(BLEND);
    tint(255 * baseIntensity, 255);
    image(baseImg, imgX, imgY, imgW, imgH);

    // Decode in the background, then upload one mask pair per frame to the GPU.
    if (masksDecoded && !allMasksReady) {
      warmUpNextMaskPair();
    }

    // Every mask is already in CPU and GPU memory, so transitions are instantaneous.
    if (allMasksReady) {
      blendMode(ADD);

      boolean useSpatialShader = spatialRevealMode && spatialRevealShader != null;

      for (int i = 0; i < colorNames.length; i++) {
        if (useSpatialShader) {
          spatialRevealShader.set("revealCenter", spatialPositionX[i], spatialPositionY[i]);
          spatialRevealShader.set("revealRadius", getSpatialRevealRadiusForMask(i));
          spatialRevealShader.set("revealFeather", spatialEdgeFeather);
          spatialRevealShader.set("imageAspect", imgW / imgH);
          shader(spatialRevealShader);
        }

        float sInt = solidIntensities[i];
        while (sInt > 0) {
          tint(255, min(255, 255 * sInt));
          image(solidMasks[i], imgX, imgY, imgW, imgH);
          sInt -= 1.0;
        }

        float bInt = bloomIntensities[i];
        while (bInt > 0) {
          tint(255, min(255, 255 * bInt));
          image(bloomMasks[i], imgX, imgY, imgW, imgH);
          bInt -= 1.0;
        }

        if (useSpatialShader) {
          resetShader();
        }
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

  if (showVerboseUi) {
    drawStatusOverlay();

    if (solidSliders != null && bloomSliders != null && baseSlider != null && audioSensSlider != null && allMasksReady && isAudioReady) {
      audioSensSlider.draw();
      baseSlider.draw();
      for (int i = 0; i < colorNames.length; i++) {
        solidSliders[i].draw();
        bloomSliders[i].draw();
      }
      drawBandMapping();
    }
  }
}

void keyPressed() {
  if (key == 'v' || key == 'V') {
    showVerboseUi = !showVerboseUi;
  } else if (key == 'm' || key == 'M') {
    spatialRevealMode = !spatialRevealMode;
    if (spatialRevealMode) {
      lastSpatialMotionUpdateMs = millis() - round(spatialMotionUpdateIntervalMs);
    }
  }
}

void updateSpatialReveal(float currentLevel, int currentMs, float elapsedMs, float attackAmount, float releaseAmount) {
  float targetEnergy = constrain(currentLevel * audioSensitivity * spatialEnergyMultiplier, 0.0, 1.0);
  float energyAmount = targetEnergy >= spatialEnergy ? attackAmount : releaseAmount;
  spatialEnergy = lerp(spatialEnergy, targetEnergy, energyAmount);

  float minimumArea = spatialMinimumRadius * spatialMinimumRadius;
  float maximumArea = spatialMaximumRadius * spatialMaximumRadius;
  spatialRevealRadius = sqrt(lerp(minimumArea, maximumArea, spatialEnergy));

  float imageAspect = imgH > 0.0 ? imgW / imgH : 1.0;
  if (spatialKeepCirclesInsideImage) {
    spatialRevealRadius = min(spatialRevealRadius, min(0.5, imageAspect * 0.5));
  }

  if (!spatialRevealMode) return;

  boolean updateTargets = lastSpatialMotionUpdateMs == 0
    || currentMs - lastSpatialMotionUpdateMs >= spatialMotionUpdateIntervalMs;
  float motionAmount = spatialMotionSmoothingTimeMs <= 0.0
    ? 1.0
    : 1.0 - exp(-elapsedMs / spatialMotionSmoothingTimeMs);
  int movingPositionCount = spatialIndependentMaskPositions ? colorNames.length : 1;

  float horizontalMargin = spatialKeepCirclesInsideImage ? spatialRevealRadius / imageAspect : 0.0;
  float verticalMargin = spatialKeepCirclesInsideImage ? spatialRevealRadius : 0.0;

  for (int i = 0; i < movingPositionCount; i++) {
    if (updateTargets) {
      spatialTargetX[i] += randomGaussian() * spatialBrownianStep;
      spatialTargetY[i] += randomGaussian() * spatialBrownianStep;
    }

    spatialTargetX[i] = constrain(spatialTargetX[i], horizontalMargin, 1.0 - horizontalMargin);
    spatialTargetY[i] = constrain(spatialTargetY[i], verticalMargin, 1.0 - verticalMargin);
    spatialPositionX[i] = lerp(spatialPositionX[i], spatialTargetX[i], motionAmount);
    spatialPositionY[i] = lerp(spatialPositionY[i], spatialTargetY[i], motionAmount);
  }

  if (!spatialIndependentMaskPositions) {
    for (int i = 1; i < colorNames.length; i++) {
      spatialPositionX[i] = spatialPositionX[0];
      spatialPositionY[i] = spatialPositionY[0];
      spatialTargetX[i] = spatialTargetX[0];
      spatialTargetY[i] = spatialTargetY[0];
    }
  }

  if (updateTargets) {
    lastSpatialMotionUpdateMs = currentMs;
  }
}

float getSpatialRevealRadiusForMask(int maskIndex) {
  if (!spatialKeepCirclesInsideImage || imgH <= 0.0) {
    return spatialRevealRadius;
  }

  float imageAspect = imgW / imgH;
  float distanceToLeft = spatialPositionX[maskIndex] * imageAspect;
  float distanceToRight = (1.0 - spatialPositionX[maskIndex]) * imageAspect;
  float distanceToTop = spatialPositionY[maskIndex];
  float distanceToBottom = 1.0 - spatialPositionY[maskIndex];
  float edgeLimitedRadius = min(min(distanceToLeft, distanceToRight), min(distanceToTop, distanceToBottom));
  return max(0.0, min(spatialRevealRadius, edgeLimitedRadius));
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
  return getBandBoundaryBin(maskIndex, maxBin);
}

int getBandEndBin(int maskIndex, int maxBin) {
  return getBandBoundaryBin(maskIndex + 1, maxBin);
}

String formatFrequency(float frequency) {
  if (frequency >= 1000.0) {
    return nf(frequency / 1000.0, 1, 2) + " kHz";
  }
  return nf(frequency, 1, 0) + " Hz";
}

void drawBandMapping() {
  int maxBin = getMaxAnalysisBin();
  float binWidth = audioSampleRate / actualAudioBufferSize;
  float effectiveMaxFrequency = min(maxFftFrequency, audioSampleRate * 0.5);
  float x = 390;

  pushStyle();
  fill(255);
  textAlign(LEFT, CENTER);
  textSize(14);
  text("FFT BANDS — " + nf(audioSampleRate, 1, 0) + " Hz, " + actualAudioBufferSize + " samples, max " + formatFrequency(effectiveMaxFrequency) + ", curve " + nf(frequencyMappingExponent, 1, 2), x, 72);

  for (int i = 0; i < colorNames.length; i++) {
    float startFrequency = getBandStartBin(i, maxBin) * binWidth;
    float endFrequency = min(getBandEndBin(i, maxBin) * binWidth, effectiveMaxFrequency);
    float y = 112.5 + i * 55;
    text(colorNames[i].toUpperCase() + ": " + formatFrequency(startFrequency) + " - " + formatFrequency(endFrequency), x, y);
  }
  popStyle();
}

void drawStatusOverlay() {
  String maskStatus;
  if (!masksDecoded) {
    maskStatus = "PRELOADING MASKS: " + masksDecodedCount + "/" + colorNames.length;
  } else if (!allMasksReady) {
    maskStatus = "UPLOADING MASKS TO GPU: " + warmupIndex + "/" + colorNames.length;
  } else {
    maskStatus = "ALL MASKS ACTIVE";
  }
  maskStatus += " | MODE: " + (spatialRevealMode ? "SPATIAL" : "FULL") + " (M)";

  String fpsStatus = "FPS: " + nf(frameRate, 0, 1);
  if (spatialRevealMode) {
    fpsStatus += " | ENERGY: " + nf(spatialEnergy * 100.0, 0, 0) + "%";
  }
  float padding = 18;
  float boxHeight = 44;

  blendMode(BLEND);
  noTint();
  textSize(24);

  // Dark translucent backgrounds keep the green text readable over bright imagery.
  noStroke();
  fill(0, 190);
  rect(0, 0, textWidth(maskStatus) + padding * 2, boxHeight);
  rect(width - textWidth(fpsStatus) - padding * 2, 0,
    textWidth(fpsStatus) + padding * 2, boxHeight);

  fill(0, 255, 80);
  textAlign(LEFT, TOP);
  text(maskStatus, padding, 8);

  textAlign(RIGHT, TOP);
  text(fpsStatus, width - padding, 8);
}

void preloadMasks() {
  // Disk access and PNG decoding happen outside the OpenGL animation thread.
  for (int i = 0; i < colorNames.length; i++) {
    String colorName = colorNames[i];
    solidMasks[i] = loadImage("mask_" + colorName + "_solid.png");
    bloomMasks[i] = loadImage("mask_" + colorName + "_bloom.png");
    masksDecodedCount = i + 1;
  }

  // This volatile write publishes all completed array writes to draw().
  masksDecoded = true;
}

void warmUpNextMaskPair() {
  if (warmupIndex >= colorNames.length) {
    allMasksReady = true;
    animationStartMs = millis();
    return;
  }

  // Alpha zero keeps this upload invisible while image() initializes each GPU texture.
  blendMode(BLEND);
  tint(255, 0);
  image(solidMasks[warmupIndex], imgX, imgY, imgW, imgH);
  image(bloomMasks[warmupIndex], imgX, imgY, imgW, imgH);
  noTint();

  warmupIndex++;
  if (warmupIndex >= colorNames.length) {
    allMasksReady = true;
    animationStartMs = millis();
  }
}

class Slider {
  float x, y, w, h;
  float minVal, maxVal;
  float val;
  String label;
  boolean dragging = false;
  boolean wasPressed = false;

  Slider(String label, float x, float y, float w, float h, float minVal, float maxVal, float defaultVal) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.minVal = minVal;
    this.maxVal = maxVal;
    this.val = defaultVal;
  }

  void update(int mx, int my, boolean mPressed) {
    if (mPressed && !wasPressed) {
      // Just pressed
      if (mx >= x && mx <= x + w + h && my >= y - h && my <= y + h) {
        dragging = true;
      }
    } else if (!mPressed) {
      dragging = false;
    }

    if (dragging) {
      val = map(mx, x, x + w, minVal, maxVal);
      val = constrain(val, minVal, maxVal);
    }
    wasPressed = mPressed;
  }

  void draw() {
    pushStyle();
    fill(100, 200);
    noStroke();
    rect(x, y - 2, w, 4);
    fill(200, 200);
    float px = map(val, minVal, maxVal, x, x + w);
    rect(x, y - 2, px - x, 4);
    fill(255);
    ellipse(px, y, h, h);
    fill(255);
    textAlign(LEFT, CENTER);
    textSize(14);
    text(label + ": " + nf(val, 1, 2), x + w + 15, y);
    popStyle();
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
