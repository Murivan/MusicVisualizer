PImage baseImg;
PImage[] solidMasks;
PImage[] bloomMasks;
volatile boolean masksDecoded = false;
volatile int masksDecodedCount = 0;
int warmupIndex = 0;
boolean allMasksReady = false;
int animationStartMs = 0;
float imgX, imgY, imgW, imgH;


// Configuration variables
// ------------------------
boolean useFullScreen = true; // Set to false to use custom canvas bounds below
int canvasWidth = 1920;
int canvasHeight = 1080;
int fps = 30;

String[] colorNames = {
  "red", "orange", "yellow", "green", "cyan", "blue", "magenta"
};
int colorDurationMs = 5000; // Each color remains active for 5 seconds
float solidBrightness = 0.75; // Added solid-mask intensity: 0.0 to 1.0
float bloomBrightness = 1.0;  // Added bloom intensity: 0.0 to 1.0

void setup() {
  fullScreen(P2D); // Enable GPU acceleration instead of CPU
  frameRate(fps);
  //smooth(4); // Reduced from 8 since Retina density already makes lines crisp
  //pixelDensity(displayDensity());

  // Load the base image immediately, then decode every mask in a background thread.
  baseImg = loadImage("window_base.png");
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

  thread("preloadMasks");
}

void draw() {
  background(0);
  int activeColor = allMasksReady
    ? ((millis() - animationStartMs) / colorDurationMs) % colorNames.length
    : 0;

  if (baseImg != null) {
    // Draw the unmodified source image first.
    blendMode(BLEND);
    tint(255, 255);
    image(baseImg, imgX, imgY, imgW, imgH);

    // Decode in the background, then upload one mask pair per frame to the GPU.
    if (masksDecoded && !allMasksReady) {
      warmUpNextMaskPair();
    }

    // Every mask is already in CPU and GPU memory, so transitions are instantaneous.
    if (allMasksReady) {
      blendMode(ADD);

      tint(255, 255 * solidBrightness);
      image(solidMasks[activeColor], imgX, imgY, imgW, imgH);

      tint(255, 255 * bloomBrightness);
      image(bloomMasks[activeColor], imgX, imgY, imgW, imgH);
    }

    // Restore normal drawing state for subsequent effects or UI.
    blendMode(BLEND);
    noTint();
  } else {
    fill(255);
    textAlign(CENTER, CENTER);
    text("window_base.png not found in data folder or sketch folder.", width/2, height/2);
  }

  drawStatusOverlay(activeColor);
}

void drawStatusOverlay(int activeColor) {
  String maskStatus;
  if (!masksDecoded) {
    maskStatus = "PRELOADING MASKS: " + masksDecodedCount + "/" + colorNames.length;
  } else if (!allMasksReady) {
    maskStatus = "UPLOADING MASKS TO GPU: " + warmupIndex + "/" + colorNames.length;
  } else {
    maskStatus = "MASK: " + colorNames[activeColor].toUpperCase();
  }

  String fpsStatus = "FPS: " + nf(frameRate, 0, 1);
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
