import com.sun.jna.Library;
import com.sun.jna.Memory;
import com.sun.jna.Native;
import com.sun.jna.NativeLong;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;
import com.sun.jna.ptr.PointerByReference;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/** Windows WASAPI capture. Loaded independently of Processing's library scanner. */
public final class WasapiInput implements AutoCloseable {
  private interface PortAudio extends Library {
    int Pa_Initialize();
    int Pa_Terminate();
    String Pa_GetErrorText(int code);
    int Pa_GetDeviceCount();
    Pointer Pa_GetDeviceInfo(int index);
    Pointer Pa_GetHostApiInfo(int index);
    int Pa_OpenStream(PointerByReference stream, StreamParameters input, Pointer output,
        double sampleRate, NativeLong frames, NativeLong flags, Pointer callback, Pointer userData);
    int Pa_StartStream(Pointer stream);
    NativeLong Pa_GetStreamReadAvailable(Pointer stream);
    int Pa_ReadStream(Pointer stream, Pointer buffer, NativeLong frames);
    Pointer Pa_GetStreamInfo(Pointer stream);
    int Pa_StopStream(Pointer stream);
    int Pa_CloseStream(Pointer stream);
  }

  @Structure.FieldOrder({"version", "name", "hostApi", "maxInputChannels", "maxOutputChannels",
      "defaultLowInputLatency", "defaultLowOutputLatency", "defaultHighInputLatency",
      "defaultHighOutputLatency", "defaultSampleRate"})
  public static class DeviceInfo extends Structure {
    public int version;
    public Pointer name;
    public int hostApi, maxInputChannels, maxOutputChannels;
    public double defaultLowInputLatency, defaultLowOutputLatency, defaultHighInputLatency,
        defaultHighOutputLatency, defaultSampleRate;
    DeviceInfo(Pointer pointer) { super(pointer); read(); }
  }

  @Structure.FieldOrder({"version", "type", "name", "deviceCount", "defaultInput", "defaultOutput"})
  public static class HostInfo extends Structure {
    public int version, type;
    public Pointer name;
    public int deviceCount, defaultInput, defaultOutput;
    HostInfo(Pointer pointer) { super(pointer); read(); }
  }

  @Structure.FieldOrder({"device", "channels", "format", "suggestedLatency", "hostInfo"})
  public static class StreamParameters extends Structure {
    public int device, channels;
    public NativeLong format;
    public double suggestedLatency;
    public Pointer hostInfo;
  }

  @Structure.FieldOrder({"version", "inputLatency", "outputLatency", "sampleRate"})
  public static class StreamInfo extends Structure {
    public int version;
    public double inputLatency, outputLatency, sampleRate;
    StreamInfo(Pointer pointer) { super(pointer); read(); }
  }

  @Structure.FieldOrder({"size", "hostApiType", "version", "flags", "channelMask",
      "hostProcessorOutput", "hostProcessorInput", "threadPriority", "streamCategory", "streamOption"})
  public static class WasapiStreamInfo extends Structure {
    public NativeLong size, version, flags, channelMask;
    public int hostApiType;
    public Pointer hostProcessorOutput, hostProcessorInput;
    public int threadPriority, streamCategory, streamOption;

    WasapiStreamInfo(boolean polling) {
      size = new NativeLong(size());
      hostApiType = WASAPI;
      version = new NativeLong(1);
      flags = new NativeLong(polling ? 9 : 1);
      channelMask = new NativeLong(0);
    }
  }

  private static final int WASAPI = 13;
  private static final int INPUT_OVERFLOW = -9981;
  private final PortAudio pa;
  private final List<Integer> deviceIndices = new ArrayList<>();
  private final List<String> deviceNames = new ArrayList<>();
  private final List<Integer> allIndices = new ArrayList<>();
  private final List<String> allNames = new ArrayList<>();
  private final List<String> allHostNames = new ArrayList<>();
  private final List<Integer> allHostTypes = new ArrayList<>();
  private Pointer stream;
  private RollingAudioBuffer window;
  private Thread worker;
  private volatile boolean stopping;
  private volatile String error = "";
  private volatile long blocks, overflows, lastBlockNanos;
  private volatile double intervalMs, jitterMs;
  private double sampleRate, inputLatencyMs;
  private int readFrames, channels;
  private boolean exclusive;
  private boolean closed;

  public WasapiInput(String libraryPath) throws IOException {
    if (!System.getProperty("os.name").startsWith("Windows") || Native.POINTER_SIZE != 8) {
      throw new IOException("WASAPI capture requires 64-bit Windows");
    }
    pa = Native.load(libraryPath, PortAudio.class);
    check(pa.Pa_Initialize(), "Initialize PortAudio");
    try {
      int count = pa.Pa_GetDeviceCount();
      if (count < 0) throw failure(count, "Enumerate devices");
      for (int i = 0; i < count; i++) {
        Pointer ptr = pa.Pa_GetDeviceInfo(i);
        if (ptr == null) throw new IOException("Missing PortAudio device info for index " + i);
        DeviceInfo info = new DeviceInfo(ptr);
        Pointer hostPtr = pa.Pa_GetHostApiInfo(info.hostApi);
        if (hostPtr == null) throw new IOException("Missing host API info for device " + i);
        HostInfo host = new HostInfo(hostPtr);
        if (info.maxInputChannels > 0) {
          String name = info.name.getString(0, "UTF-8") + " (" + info.maxInputChannels
              + " channels, " + (int) info.defaultSampleRate + " Hz)";
          allIndices.add(i);
          allNames.add(name);
          allHostNames.add(host.name.getString(0, "UTF-8"));
          allHostTypes.add(host.type);
          if (host.type == WASAPI) {
            deviceIndices.add(i);
            deviceNames.add(name);
          }
        }
      }
    } catch (IOException | RuntimeException | LinkageError e) {
      int result = pa.Pa_Terminate();
      if (result != 0) e.addSuppressed(failure(result, "Terminate PortAudio"));
      throw e;
    }
  }

  public String[] devices() { return deviceNames.toArray(new String[0]); }
  public String[] allDevices() { return allNames.toArray(new String[0]); }
  public String[] allHostApis() { return allHostNames.toArray(new String[0]); }
  public int[] allHostTypes() { return allHostTypes.stream().mapToInt(Integer::intValue).toArray(); }
  public double sampleRate() { return sampleRate; }
  public double inputLatencyMs() { return inputLatencyMs; }
  public int readFrames() { return readFrames; }
  public int channels() { return channels; }
  public boolean exclusive() { return exclusive; }
  public long blocks() { return blocks; }
  public long overflows() { return overflows; }
  public long lastBlockNanos() { return lastBlockNanos; }
  public double intervalMs() { return intervalMs; }
  public double jitterMs() { return jitterMs; }
  public String error() { return error; }
  public void snapshot(float[] output) { window.copyTo(output); }

  public void open(int selection, int frames, int fftSize) throws IOException {
    open(selection, frames, fftSize, false);
  }

  public void open(int selection, int frames, int fftSize, boolean exclusive) throws IOException {
    open(selection, frames, fftSize, exclusive, false);
  }

  public void open(int selection, int frames, int fftSize, boolean exclusive, boolean polling) throws IOException {
    if (selection < 0 || selection >= deviceIndices.size()) throw new IllegalArgumentException("Invalid device");
    openIndex(deviceIndices.get(selection), frames, fftSize, exclusive, polling);
  }

  public void openAny(int selection, int frames, int fftSize, boolean exclusive) throws IOException {
    if (selection < 0 || selection >= allIndices.size()) throw new IllegalArgumentException("Invalid device");
    if (exclusive && allHostTypes.get(selection) != WASAPI)
      throw new IllegalArgumentException("Exclusive mode is only available for WASAPI");
    openIndex(allIndices.get(selection), frames, fftSize, exclusive, false);
  }

  private void openIndex(int index, int frames, int fftSize, boolean exclusive, boolean polling) throws IOException {
    if (polling && !exclusive) throw new IllegalArgumentException("Polling probe requires exclusive mode");
    if (closed || stream != null || frames < 1 || fftSize < 1)
      throw new IllegalArgumentException("Invalid capture configuration");
    DeviceInfo info = new DeviceInfo(pa.Pa_GetDeviceInfo(index));
    channels = Math.min(2, info.maxInputChannels);
    readFrames = frames;
    StreamParameters params = new StreamParameters();
    params.device = index;
    params.channels = channels;
    params.format = new NativeLong(1); // paFloat32
    params.suggestedLatency = (double) frames / info.defaultSampleRate;
    WasapiStreamInfo wasapi = exclusive ? new WasapiStreamInfo(polling) : null;
    if (wasapi != null) {
      wasapi.write();
      params.hostInfo = wasapi.getPointer();
    }
    PointerByReference ref = new PointerByReference();
    check(pa.Pa_OpenStream(ref, params, null, info.defaultSampleRate, new NativeLong(frames),
        new NativeLong(0), null, null), "Open WASAPI stream");
    stream = ref.getValue();
    try {
      Pointer streamInfo = pa.Pa_GetStreamInfo(stream);
      if (streamInfo == null) throw new IOException("PortAudio returned no stream information");
      StreamInfo actual = new StreamInfo(streamInfo);
      sampleRate = actual.sampleRate;
      inputLatencyMs = actual.inputLatency * 1000;
      if (sampleRate <= 0 || !Double.isFinite(sampleRate)) throw new IOException("Invalid stream sample rate");
      window = new RollingAudioBuffer(fftSize);
      check(pa.Pa_StartStream(stream), "Start WASAPI stream");
      this.exclusive = exclusive;
      worker = new Thread(() -> {
        try {
          capture();
        } catch (RuntimeException | LinkageError e) {
          error = "Capture failed: " + e;
        }
      }, "wasapi-capture");
      worker.setDaemon(true);
      worker.start();
    } catch (IOException | RuntimeException e) {
      int closeResult = pa.Pa_CloseStream(stream);
      stream = null;
      if (closeResult != 0) e.addSuppressed(failure(closeResult, "Close WASAPI stream"));
      throw e;
    }
  }

  private void capture() {
    Memory buffer = new Memory((long) readFrames * channels * Float.BYTES);
    float[] samples = new float[readFrames * channels];
    long previous = 0;
    long lastProgress = System.nanoTime();
    long stallTimeoutNanos = Math.max(3_000_000_000L,
        (long) Math.ceil(4.0 * readFrames * 1_000_000_000.0 / sampleRate));
    while (!stopping) {
      long available = pa.Pa_GetStreamReadAvailable(stream).longValue();
      if (available < 0) {
        error = failure((int) available, "Read availability").getMessage();
        return;
      }
      if (available < readFrames) {
        if (isCaptureStalled(System.nanoTime(), lastProgress, stallTimeoutNanos)) {
          error = "PortAudio capture stalled: no complete audio block for "
              + (stallTimeoutNanos / 1_000_000L) + " ms";
          return;
        }
        try {
          Thread.sleep(1);
        } catch (InterruptedException e) {
          Thread.currentThread().interrupt();
          if (!stopping) error = "Capture thread interrupted";
          return;
        }
        continue;
      }
      int result = pa.Pa_ReadStream(stream, buffer, new NativeLong(readFrames));
      if (result == INPUT_OVERFLOW) overflows++;
      else if (result != 0) {
        error = failure(result, "Capture audio").getMessage();
        return;
      }
      long now = System.nanoTime();
      lastProgress = now;
      buffer.read(0, samples, 0, samples.length);
      window.append(samples, readFrames, channels);
      if (previous != 0) {
        double dt = (now - previous) / 1e6;
        if (intervalMs == 0) intervalMs = dt;
        else {
          jitterMs += 0.05 * (Math.abs(dt - intervalMs) - jitterMs);
          intervalMs += 0.05 * (dt - intervalMs);
        }
      }
      previous = now;
      blocks++;
      lastBlockNanos = now;
    }
  }

  static boolean isCaptureStalled(long now, long lastProgress, long timeout) {
    return now - lastProgress >= timeout;
  }

  private IOException failure(int code, String operation) {
    return new IOException(operation + ": " + pa.Pa_GetErrorText(code) + " (" + code + ")");
  }

  private void check(int result, String operation) throws IOException {
    if (result != 0) throw failure(result, operation);
  }

  public synchronized void close() throws IOException {
    if (closed) return;
    stopping = true;
    if (worker != null) {
      worker.interrupt();
      try {
        worker.join(2000);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new IOException("Interrupted while stopping WASAPI capture", e);
      }
      if (worker.isAlive()) throw new IOException("Capture thread did not stop; stream remains open");
    }
    IOException problem = null;
    if (stream != null) {
      int result = pa.Pa_StopStream(stream);
      if (result != 0) problem = failure(result, "Stop WASAPI stream");
      result = pa.Pa_CloseStream(stream);
      if (result != 0) {
        IOException closeError = failure(result, "Close WASAPI stream");
        if (problem == null) problem = closeError; else problem.addSuppressed(closeError);
      }
      stream = null;
    }
    int result = pa.Pa_Terminate();
    closed = true;
    if (result != 0) {
      IOException terminateError = failure(result, "Terminate PortAudio");
      if (problem == null) problem = terminateError; else problem.addSuppressed(terminateError);
    }
    if (problem != null) throw problem;
  }
}
