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
float[] solidIntensities = new float[colorNames.length];
float[] bloomIntensities = new float[colorNames.length];

Slider[] solidSliders;
Slider[] bloomSliders;

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

  solidSliders = new Slider[colorNames.length];
  bloomSliders = new Slider[colorNames.length];
  for (int i = 0; i < colorNames.length; i++) {
    solidIntensities[i] = 0.0; // Default solid intensity
    bloomIntensities[i] = 0.0;  // Default bloom intensity
    
    int yBase = 100 + i * 55;
    solidSliders[i] = new Slider(colorNames[i].toUpperCase() + " SOLID", 20, yBase, 150, 12, 0.0, 5.0, solidIntensities[i]);
    bloomSliders[i] = new Slider(colorNames[i].toUpperCase() + " BLOOM", 20, yBase + 25, 150, 12, 0.0, 5.0, bloomIntensities[i]);
  }

  thread("preloadMasks");
}

void draw() {
  background(0);
  
  // Update sliders
  if (solidSliders != null && bloomSliders != null) {
    boolean mPressed = mousePressed;
    for (int i = 0; i < colorNames.length; i++) {
      solidSliders[i].update(mouseX, mouseY, mPressed);
      solidIntensities[i] = solidSliders[i].val;
      
      bloomSliders[i].update(mouseX, mouseY, mPressed);
      bloomIntensities[i] = bloomSliders[i].val;
    }
  }

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

      for (int i = 0; i < colorNames.length; i++) {
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

  drawStatusOverlay();
  
  // Draw sliders
  if (solidSliders != null && bloomSliders != null && allMasksReady) {
    for (int i = 0; i < colorNames.length; i++) {
      solidSliders[i].draw();
      bloomSliders[i].draw();
    }
  }
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
