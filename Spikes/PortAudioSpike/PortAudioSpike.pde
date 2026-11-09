// Throwaway spike: can a Processing sketch capture live audio through PortAudio (WASAPI/ASIO) via JNA,
// and what latency does it get? Pick an input device, then watch the reported latency and timing.
//
// Keys: UP/DOWN select | ENTER open | BACKSPACE close | B cycle buffer size | E toggle WASAPI exclusive

import java.io.File;
import java.util.ArrayList;
import java.util.List;

final int[] BUFFER_CHOICES = {0, 64, 128, 256, 512, 1024};   // 0 = let the host API decide

PortAudioBackend backend;
String loadedLibrary = "";
String initError = "";
List<PortAudioBackend.Device> allDevices = new ArrayList<PortAudioBackend.Device>();
List<PortAudioBackend.Device> devices = new ArrayList<PortAudioBackend.Device>();   // filtered by host API
List<String> hostApis = new ArrayList<String>();   // index 0 = "All"
int hostFilter = 0;
int selected = 0;
int scrollTop = 0;
final float ROW_HEIGHT = 24;
float listTop = 80;
int bufferChoice = 0;
boolean wasapiExclusive = false;
String status = "";
Capture capture;

void setup() {
  size(1000, 720);
  surface.setTitle("PortAudio spike");
  textSize(16);

  // The ASIO-enabled build also contains WASAPI, WDM-KS, MME and DirectSound.
  String[] candidates = {"libportaudio64bit-asio.dll", "libportaudio64bit.dll"};
  for (String file : candidates) {
    File f = new File(dataPath(file));
    if (!f.exists()) continue;
    try {
      backend = new PortAudioBackend(f);
      loadedLibrary = file + " (" + backend.version() + ")";
      allDevices = backend.inputDevices();
      hostApis.add("All");
      for (PortAudioBackend.Device d : allDevices) {
        if (!hostApis.contains(d.hostApi)) hostApis.add(d.hostApi);
      }
      applyHostFilter();
      initError = "";
      break;
    } catch (Throwable t) {
      initError = file + ": " + t;
      backend = null;
    }
  }
}

void applyHostFilter() {
  devices = new ArrayList<PortAudioBackend.Device>();
  for (PortAudioBackend.Device d : allDevices) {
    if (hostFilter == 0 || d.hostApi.equals(hostApis.get(hostFilter))) devices.add(d);
  }
  selected = 0;
  scrollTop = 0;
}

int visibleRows() {
  return max(1, int((height - listTop - 30) / ROW_HEIGHT));
}

void moveSelection(int delta) {
  if (devices.size() == 0) return;
  selected = constrain(selected + delta, 0, devices.size() - 1);
  int rows = visibleRows();
  if (selected < scrollTop) scrollTop = selected;
  if (selected >= scrollTop + rows) scrollTop = selected - rows + 1;
}

void scrollList(int delta) {
  scrollTop = constrain(scrollTop + delta, 0, max(0, devices.size() - visibleRows()));
}

void mouseWheel(MouseEvent event) {
  if (capture == null) scrollList(event.getCount() * 3);
}

void openSelected() {
  closeStream();
  if (devices.size() == 0) return;
  PortAudioBackend.Device d = devices.get(selected);
  try {
    PortAudioBackend.InputStream s = backend.openInput(d, BUFFER_CHOICES[bufferChoice], wasapiExclusive);
    capture = new Capture(s);
    capture.start();
    status = "Streaming" + (s.exclusive ? " (WASAPI exclusive)" : "");
  } catch (Throwable t) {
    status = t.getMessage();
  }
}

void closeStream() {
  if (capture != null) {
    capture.shutdown();
    capture = null;
  }
}

class Capture extends Thread {
  final PortAudioBackend.InputStream stream;
  volatile boolean stop = false;
  volatile double intervalMs = 0;
  volatile double jitterMs = 0;
  volatile double maxIntervalMs = 0;
  volatile float rms = 0;
  volatile float peak = 0;
  volatile int overflows = 0;
  volatile long blocks = 0;
  volatile String readError = "";

  Capture(PortAudioBackend.InputStream stream) {
    super("portaudio-capture");
    this.stream = stream;
    setDaemon(true);
  }

  void run() {
    float[] samples = new float[stream.readFrames * stream.channels];
    long previous = 0;
    while (!stop) {
      int err = stream.read(samples);
      long now = System.nanoTime();
      if (err == PortAudioBackend.INPUT_OVERFLOWED) {
        overflows++;
      } else if (err != 0) {
        readError = backend.errorText(err);
        break;
      }
      double sum = 0;
      float p = 0;
      for (int i = 0; i < samples.length; i++) {
        float s = samples[i];
        sum += s * s;
        p = max(p, abs(s));
      }
      rms = (float) Math.sqrt(sum / samples.length);
      peak = p;
      if (previous != 0) {
        double dt = (now - previous) / 1.0e6;
        if (intervalMs == 0) {
          intervalMs = dt;
        } else {
          jitterMs += 0.05 * (Math.abs(dt - intervalMs) - jitterMs);
          intervalMs += 0.05 * (dt - intervalMs);
        }
        maxIntervalMs = Math.max(maxIntervalMs, dt);
      }
      previous = now;
      blocks++;
    }
  }

  void shutdown() {
    stop = true;
    try {
      join(1000);
    } catch (InterruptedException e) {
    }
    stream.close();
  }
}

void draw() {
  background(20);
  fill(255);
  textAlign(LEFT, TOP);
  float y = 16;
  text("PortAudio: " + (backend == null ? "NOT LOADED  " + initError : loadedLibrary), 20, y);
  y += 26;
  text("Buffer (B): " + (BUFFER_CHOICES[bufferChoice] == 0 ? "host default" : BUFFER_CHOICES[bufferChoice] + " frames")
    + "    WASAPI exclusive (E): " + (wasapiExclusive ? "on" : "off") + "    Status: " + status, 20, y);
  y += 36;

  if (backend == null) return;

  Capture c = capture;
  if (c == null) {
    text("Input devices (" + devices.size() + ") - host API filter (H): " + hostApis.get(hostFilter)
      + " | UP/DOWN/PgUp/PgDn/wheel scroll, ENTER opens", 20, y);
    y += 28;
    listTop = y;
    int rows = visibleRows();
    for (int i = scrollTop; i < min(devices.size(), scrollTop + rows); i++) {
      PortAudioBackend.Device d = devices.get(i);
      fill(i == selected ? color(0, 255, 80) : color(255));
      text(d.hostApi + " | " + d.name + " | " + d.maxInputChannels + "ch @ " + nf((float) d.defaultSampleRate, 1, 0)
        + " Hz | default low latency " + nf((float) (d.defaultLowLatencySeconds * 1000.0), 1, 1) + " ms", 20, y);
      y += ROW_HEIGHT;
    }
    if (devices.size() > rows) {
      float trackHeight = rows * ROW_HEIGHT;
      float thumbHeight = max(20, trackHeight * rows / devices.size());
      float thumbY = listTop + (trackHeight - thumbHeight) * scrollTop / max(1, devices.size() - rows);
      noStroke();
      fill(50);
      rect(width - 14, listTop, 6, trackHeight);
      fill(160);
      rect(width - 14, thumbY, 6, thumbHeight);
    }
    return;
  }

  PortAudioBackend.InputStream s = c.stream;
  PortAudioBackend.Device d = devices.get(selected);
  fill(0, 255, 80);
  text(d.hostApi + " | " + d.name, 20, y);
  y += 32;
  double blockMs = s.readFrames * 1000.0 / s.sampleRate;
  double estimate = s.inputLatencyMs + blockMs * 0.5;
  color verdict = estimate <= 25 ? color(0, 255, 80) : (estimate <= 50 ? color(255, 200, 0) : color(255, 80, 60));
  fill(255);
  text("Stream sample rate: " + nf((float) s.sampleRate, 1, 0) + " Hz, " + s.channels + " ch, read size " + s.readFrames + " frames (" + nf((float) blockMs, 1, 2) + " ms)", 20, y);
  y += 28;
  fill(verdict);
  text("Reported input latency (driver/host API): " + nf((float) s.inputLatencyMs, 1, 2) + " ms", 20, y);
  y += 28;
  text("Estimated capture latency (reported + half read block): " + nf((float) estimate, 1, 2) + " ms", 20, y);
  y += 36;
  fill(255);
  text("Measured block interval: " + nf((float) c.intervalMs, 1, 2) + " ms  (+/- " + nf((float) c.jitterMs, 1, 2) + ", max " + nf((float) c.maxIntervalMs, 1, 1) + " ms)", 20, y);
  y += 28;
  text("Blocks: " + c.blocks + "   Input overflows: " + c.overflows + (c.readError.length() > 0 ? "   ERROR: " + c.readError : ""), 20, y);
  y += 36;
  text("Level (RMS / peak)", 20, y);
  y += 26;
  noStroke();
  fill(60);
  rect(20, y, width - 40, 24);
  fill(0, 255, 80);
  rect(20, y, (width - 40) * constrain(c.rms * 4.0, 0, 1), 24);
  y += 30;
  fill(255, 200, 0);
  rect(20, y, (width - 40) * constrain(c.peak, 0, 1), 12);
  y += 40;
  fill(160);
  text("Note: the reported latency is the host API's own figure; confirm with a real loopback/click test.", 20, y);
}

void keyPressed() {
  if (key == 'b' || key == 'B') {
    bufferChoice = (bufferChoice + 1) % BUFFER_CHOICES.length;
    if (capture != null) openSelected();
  } else if (key == 'e' || key == 'E') {
    wasapiExclusive = !wasapiExclusive;
    if (capture != null) openSelected();
  } else if (key == BACKSPACE) {
    closeStream();
    status = "Closed";
  } else if (key == CODED && capture == null) {
    if (keyCode == UP) moveSelection(-1);
    if (keyCode == DOWN) moveSelection(1);
    if (keyCode == java.awt.event.KeyEvent.VK_PAGE_UP) moveSelection(-visibleRows());
    if (keyCode == java.awt.event.KeyEvent.VK_PAGE_DOWN) moveSelection(visibleRows());
  } else if ((key == 'h' || key == 'H') && capture == null) {
    hostFilter = (hostFilter + 1) % hostApis.size();
    applyHostFilter();
  } else if ((key == ENTER || key == RETURN) && capture == null) {
    openSelected();
  }
}

void exit() {
  closeStream();
  if (backend != null) backend.terminate();
  super.exit();
}
