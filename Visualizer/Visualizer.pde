import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;
import ddf.minim.signals.*;
import ddf.minim.spi.*;
import ddf.minim.ugens.*;

import javax.sound.sampled.AudioSystem;
import javax.sound.sampled.Mixer;
import java.util.ArrayList;

import javax.swing.JFileChooser;
import javax.swing.filechooser.FileNameExtensionFilter;
import javax.swing.JOptionPane;
import javax.swing.JDialog;
import java.io.File;

PImage baseImg;
PImage[] solidMasks;
PImage[] bloomMasks;
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
boolean isAudioReady = false;
boolean isCancelled = false;

// Configuration variables
// ------------------------
boolean useFullScreen = true; // Set to false to use custom canvas bounds below
int canvasWidth = 1920;
int canvasHeight = 1080;
int fps = 30;

// Audio Configuration
int audioBufferSize = 2048;           // Size of the audio buffer (also dictates FFT resolution)
float maxFftFrequency = 20000.0;       // The maximum frequency (Hz) analyzed and mapped across the masks
float audioBandMultiplier = 0.1;      // Base scaling factor for the real-time FFT band amplitudes
float audioBloomMultiplier = 1.0;     // Indicates how much more the bloom reacts compared to solid masks
float initialAudioSensitivity = 5.0;  // Initial value for the audio sensitivity slider
float audioBaseIntensityScale = 1.5;  // How much the overall audio energy boosts the base image brightness
float baseImageSilenceFloor = 0.2;    // The base image brightness (baseline) before audio boosts it


// Different mappings can be obtained changing the order of the color names in this array.
String[] colorNames = {
  // "red", "orange", "yellow", "green", "cyan", "blue", "magenta"
  // "magenta", "blue", "cyan", "green", "yellow", "orange", "red"
  // "magenta", "blue", "green", "cyan", "red", "orange", "yellow"
  "blue", "cyan", "red", "orange", "yellow"
};
float[] solidIntensities = new float[colorNames.length];
float[] bloomIntensities = new float[colorNames.length];
float baseIntensity = baseImageSilenceFloor;
float audioSensitivity = initialAudioSensitivity;

Slider[] solidSliders;
Slider[] bloomSliders;
Slider baseSlider;
Slider audioSensSlider;

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
  baseSlider = new Slider("BASE IMAGE", 20, 60, 150, 12, 0.0, 1.0, baseIntensity);
  audioSensSlider = new Slider("AUDIO SENSITIVITY", 20, 20, 150, 12, 0.0, 20.0, initialAudioSensitivity);

  for (int i = 0; i < colorNames.length; i++) {
    solidIntensities[i] = 0.0; // Default solid intensity
    bloomIntensities[i] = 0.0;  // Default bloom intensity

    int yBase = 100 + i * 55;
    solidSliders[i] = new Slider(colorNames[i].toUpperCase() + " SOLID", 20, yBase, 150, 12, 0.0, 5.0, solidIntensities[i]);
    bloomSliders[i] = new Slider(colorNames[i].toUpperCase() + " BLOOM", 20, yBase + 25, 150, 12, 0.0, 5.0, bloomIntensities[i]);
  }

  thread("preloadMasks");
  thread("setupAudio");
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

    for (int i = 0; i < colorNames.length; i++) {
      float bandVal = 0.0;
      if (isAudioReady && fft != null) {
        float maxFreq = maxFftFrequency;
        int maxBin = fft.freqToIndex(maxFreq);
        if (maxBin < colorNames.length) maxBin = colorNames.length;

        int binsPerColor = maxBin / colorNames.length;
        int startBin = i * binsPerColor;
        int endBin = startBin + binsPerColor;

        float sum = 0;
        for (int b = startBin; b < endBin; b++) {
          sum += fft.getBand(b);
        }
        bandVal = (sum / binsPerColor) * audioBandMultiplier * audioSensitivity;
      }

      solidSliders[i].update(mouseX, mouseY, mPressed);
      solidIntensities[i] = solidSliders[i].val + bandVal;

      bloomSliders[i].update(mouseX, mouseY, mPressed);
      bloomIntensities[i] = bloomSliders[i].val + bandVal * audioBloomMultiplier;
    }
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
  if (solidSliders != null && bloomSliders != null && baseSlider != null && audioSensSlider != null && allMasksReady && isAudioReady) {
    audioSensSlider.draw();
    baseSlider.draw();
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
    fft = new FFT(in.bufferSize(), in.sampleRate());
  } else {
    track = minim.loadFile(audioFileName, audioBufferSize);
    if (track != null) {
      track.loop();
      fft = new FFT(track.bufferSize(), track.sampleRate());
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

