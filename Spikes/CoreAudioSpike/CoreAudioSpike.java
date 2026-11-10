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
import java.util.Locale;

/** Isolated macOS PortAudio/Core Audio enumeration and blocking-capture probe. */
public final class CoreAudioSpike implements AutoCloseable {
  private static final String CORE_AUDIO = "Core Audio";
  private static final int PA_FLOAT32 = 1;
  private static final int PA_INPUT_OVERFLOWED = -9981;

  private interface PortAudio extends Library {
    int Pa_Initialize();
    int Pa_Terminate();
    String Pa_GetVersionText();
    String Pa_GetErrorText(int code);
    int Pa_GetHostApiCount();
    Pointer Pa_GetHostApiInfo(int index);
    int Pa_GetDeviceCount();
    Pointer Pa_GetDeviceInfo(int index);
    int Pa_OpenStream(PointerByReference stream, Pointer input, Pointer output,
        double sampleRate, NativeLong frames, NativeLong flags, Pointer callback, Pointer userData);
    int Pa_StartStream(Pointer stream);
    int Pa_ReadStream(Pointer stream, Pointer buffer, NativeLong frames);
    Pointer Pa_GetStreamInfo(Pointer stream);
    int Pa_StopStream(Pointer stream);
    int Pa_CloseStream(Pointer stream);
  }

  @Structure.FieldOrder({"version", "type", "name", "deviceCount", "defaultInput", "defaultOutput"})
  public static final class HostInfo extends Structure {
    public int version;
    public int type;
    public Pointer name;
    public int deviceCount;
    public int defaultInput;
    public int defaultOutput;

    HostInfo(Pointer pointer) {
      super(pointer);
      read();
    }

    HostInfo() {}
  }

  @Structure.FieldOrder({"version", "name", "hostApi", "maxInputChannels", "maxOutputChannels",
      "defaultLowInputLatency", "defaultLowOutputLatency", "defaultHighInputLatency",
      "defaultHighOutputLatency", "defaultSampleRate"})
  public static final class DeviceInfo extends Structure {
    public int version;
    public Pointer name;
    public int hostApi;
    public int maxInputChannels;
    public int maxOutputChannels;
    public double defaultLowInputLatency;
    public double defaultLowOutputLatency;
    public double defaultHighInputLatency;
    public double defaultHighOutputLatency;
    public double defaultSampleRate;

    DeviceInfo(Pointer pointer) {
      super(pointer);
      read();
    }

    DeviceInfo() {}

    int offsetOf(String field) {
      return fieldOffset(field);
    }
  }

  @Structure.FieldOrder({"device", "channels", "format", "suggestedLatency", "hostInfo"})
  public static final class StreamParameters extends Structure {
    public int device;
    public int channels;
    public NativeLong format;
    public double suggestedLatency;
    public Pointer hostInfo;

    int offsetOf(String field) {
      return fieldOffset(field);
    }
  }

  @Structure.FieldOrder({"version", "inputLatency", "outputLatency", "sampleRate"})
  public static final class StreamInfo extends Structure {
    public int version;
    public double inputLatency;
    public double outputLatency;
    public double sampleRate;

    StreamInfo(Pointer pointer) {
      super(pointer);
      read();
    }

    StreamInfo() {}

    int offsetOf(String field) {
      return fieldOffset(field);
    }
  }

  private static final class Device {
    final int index;
    final String name;
    final String host;
    final int hostType;
    final int channels;
    final double sampleRate;
    final double lowLatency;

    Device(int index, String name, String host, int hostType, DeviceInfo info) {
      this.index = index;
      this.name = name;
      this.host = host;
      this.hostType = hostType;
      channels = info.maxInputChannels;
      sampleRate = info.defaultSampleRate;
      lowLatency = info.defaultLowInputLatency;
    }
  }

  private final PortAudio pa;
  private final String libraryPath;
  private boolean initialized;
  private boolean closed;
  private Pointer stream;

  private CoreAudioSpike(String libraryPath) throws IOException {
    this.libraryPath = libraryPath;
    pa = Native.load(libraryPath, PortAudio.class);
    check(pa.Pa_Initialize(), "Initialize PortAudio");
    initialized = true;
  }

  public static void main(String[] args) throws Exception {
    if (args.length < 2) {
      throw new IllegalArgumentException(
          "Usage: CoreAudioSpike <libportaudio.dylib> --abi | --list | --capture <device fragment> [seconds] [read-frames] [fft-size]");
    }
    try (CoreAudioSpike spike = new CoreAudioSpike(args[0])) {
      spike.printEnvironment();
      if ("--abi".equals(args[1])) {
        spike.printAndVerifyLayouts();
      } else if ("--list".equals(args[1])) {
        spike.listDevices();
      } else if ("--capture".equals(args[1])) {
        if (args.length < 3 || args.length > 6) {
          throw new IllegalArgumentException(
              "--capture requires a device-name fragment and accepts seconds, read-frames, and FFT size");
        }
        int seconds = args.length > 3 ? Integer.parseInt(args[3]) : 10;
        int readFrames = args.length > 4 ? Integer.parseInt(args[4]) : 128;
        int fftSize = args.length > 5 ? Integer.parseInt(args[5]) : 512;
        spike.capture(args[2], seconds, readFrames, fftSize);
      } else {
        throw new IllegalArgumentException("Expected --abi, --list, or --capture");
      }
    }
  }

  private void printEnvironment() {
    System.out.println("PortAudio: " + pa.Pa_GetVersionText());
    System.out.println("Library: " + libraryPath);
    System.out.println("JVM: " + System.getProperty("java.version") + ", "
        + System.getProperty("os.arch") + ", pointer size " + Native.POINTER_SIZE);
    System.out.println("JNA native long size: " + NativeLong.SIZE);
  }

  private void printAndVerifyLayouts() {
    HostInfo host = new HostInfo();
    DeviceInfo device = new DeviceInfo();
    StreamParameters parameters = new StreamParameters();
    StreamInfo info = new StreamInfo();
    requireLayout("PaHostApiInfo", host.size(), 32);
    requireLayout("PaDeviceInfo", device.size(), 72);
    requireLayout("PaStreamParameters", parameters.size(), 32);
    requireLayout("PaStreamInfo", info.size(), 32);
    requireLayout("PaDeviceInfo.name offset", device.offsetOf("name"), 8);
    requireLayout("PaDeviceInfo.hostApi offset", device.offsetOf("hostApi"), 16);
    requireLayout("PaDeviceInfo.defaultSampleRate offset", device.offsetOf("defaultSampleRate"), 64);
    requireLayout("PaStreamParameters.format offset", parameters.offsetOf("format"), 8);
    requireLayout("PaStreamParameters.hostInfo offset", parameters.offsetOf("hostInfo"), 24);
    requireLayout("PaStreamInfo.inputLatency offset", info.offsetOf("inputLatency"), 8);
    System.out.println("PortAudio LP64 JNA structure layouts: verified");
  }

  private static void requireLayout(String name, int actual, int expected) {
    if (actual != expected) {
      throw new IllegalStateException(name + " is " + actual + " bytes; expected " + expected);
    }
    System.out.println(name + ": " + actual);
  }

  private List<Device> inputDevices() throws IOException {
    int count = pa.Pa_GetDeviceCount();
    if (count < 0) throw failure(count, "Enumerate devices");
    List<Device> devices = new ArrayList<>();
    for (int i = 0; i < count; i++) {
      Pointer devicePointer = pa.Pa_GetDeviceInfo(i);
      if (devicePointer == null) throw new IOException("Missing PortAudio device info for index " + i);
      DeviceInfo info = new DeviceInfo(devicePointer);
      if (info.maxInputChannels <= 0) continue;
      Pointer hostPointer = pa.Pa_GetHostApiInfo(info.hostApi);
      if (hostPointer == null) throw new IOException("Missing host API info for device " + i);
      HostInfo host = new HostInfo(hostPointer);
      devices.add(new Device(i, info.name.getString(0, "UTF-8"),
          host.name.getString(0, "UTF-8"), host.type, info));
    }
    return devices;
  }

  private void listDevices() throws IOException {
    int hostCount = pa.Pa_GetHostApiCount();
    if (hostCount < 0) throw failure(hostCount, "Enumerate host APIs");
    System.out.println("Host APIs:");
    for (int i = 0; i < hostCount; i++) {
      Pointer pointer = pa.Pa_GetHostApiInfo(i);
      if (pointer == null) throw new IOException("Missing host API info for index " + i);
      HostInfo host = new HostInfo(pointer);
      System.out.println("  " + host.name.getString(0, "UTF-8") + " (type " + host.type + ")");
    }
    System.out.println("Input devices:");
    for (Device device : inputDevices()) {
      System.out.printf(Locale.ROOT, "  [%d] %s | %s | %d channels | %.0f Hz | default low latency %.2f ms%n",
          device.index, device.host, device.name, device.channels, device.sampleRate,
          device.lowLatency * 1000.0);
    }
  }

  private void capture(String fragment, int seconds, int readFrames, int fftSize) throws IOException {
    if (seconds <= 0 || readFrames <= 0 || fftSize <= 0) {
      throw new IllegalArgumentException("Capture duration and buffer sizes must be positive");
    }
    Device selected = null;
    for (Device device : inputDevices()) {
      if (CORE_AUDIO.equalsIgnoreCase(device.host)
          && device.name.toLowerCase(Locale.ROOT).contains(fragment.toLowerCase(Locale.ROOT))) {
        if (selected != null) throw new IllegalArgumentException("Ambiguous Core Audio device fragment: " + fragment);
        selected = device;
      }
    }
    if (selected == null) throw new IllegalArgumentException("Core Audio input not found: " + fragment);

    int channels = Math.min(2, selected.channels);
    StreamParameters parameters = new StreamParameters();
    parameters.device = selected.index;
    parameters.channels = channels;
    parameters.format = new NativeLong(PA_FLOAT32);
    parameters.suggestedLatency = selected.lowLatency;
    parameters.hostInfo = null;
    parameters.write();

    PointerByReference streamReference = new PointerByReference();
    check(pa.Pa_OpenStream(streamReference, parameters.getPointer(), null, selected.sampleRate,
        new NativeLong(readFrames), new NativeLong(0), null, null), "Open Core Audio input");
    stream = streamReference.getValue();
    try {
      Pointer streamInfoPointer = pa.Pa_GetStreamInfo(stream);
      if (streamInfoPointer == null) throw new IOException("PortAudio returned no stream information");
      StreamInfo info = new StreamInfo(streamInfoPointer);
      check(pa.Pa_StartStream(stream), "Start Core Audio input");
      reportCapture(selected, channels, readFrames, fftSize, seconds, info);
    } finally {
      closeStream();
    }
  }

  private void reportCapture(Device device, int channels, int readFrames, int fftSize, int seconds,
      StreamInfo info) throws IOException {
    Memory buffer = new Memory((long) readFrames * channels * Float.BYTES);
    float[] block = new float[readFrames * channels];
    float[] window = new float[fftSize];
    RollingAudioBuffer rolling = new RollingAudioBuffer(fftSize);
    long deadline = System.nanoTime() + seconds * 1_000_000_000L;
    long blocks = 0;
    long overflows = 0;
    long firstBlock = 0;
    long lastBlock = 0;
    double intervalSum = 0;
    float peak = 0;
    double squareSum = 0;
    long sampleCount = 0;

    while (System.nanoTime() < deadline) {
      int result = pa.Pa_ReadStream(stream, buffer, new NativeLong(readFrames));
      if (result == PA_INPUT_OVERFLOWED) {
        overflows++;
      } else if (result != 0) {
        throw failure(result, "Read Core Audio input");
      }
      long now = System.nanoTime();
      if (firstBlock == 0) firstBlock = now;
      if (lastBlock != 0) intervalSum += (now - lastBlock) / 1e6;
      lastBlock = now;
      buffer.read(0, block, 0, block.length);
      rolling.append(block, readFrames, channels);
      for (float sample : block) {
        float magnitude = Math.abs(sample);
        if (magnitude > peak) peak = magnitude;
        squareSum += sample * sample;
        sampleCount++;
      }
      blocks++;
    }

    rolling.copyTo(window);
    double windowSquareSum = 0;
    float windowPeak = 0;
    for (float sample : window) {
      windowSquareSum += sample * sample;
      windowPeak = Math.max(windowPeak, Math.abs(sample));
    }
    double averageIntervalMs = blocks > 1 ? intervalSum / (blocks - 1) : 0;
    double elapsedSeconds = blocks > 1 ? (lastBlock - firstBlock) / 1e9 : 0;
    double rms = sampleCount > 0 ? Math.sqrt(squareSum / sampleCount) : 0;
    double windowRms = Math.sqrt(windowSquareSum / window.length);

    System.out.println("Capture: " + device.host + " / " + device.name);
    System.out.printf(Locale.ROOT,
        "Stream: %.0f Hz, %d channel(s), read %d frames (%.2f ms), FFT window %d frames (%.2f ms), input latency %.2f ms%n",
        info.sampleRate, channels, readFrames, readFrames * 1000.0 / info.sampleRate,
        fftSize, fftSize * 1000.0 / info.sampleRate, info.inputLatency * 1000.0);
    System.out.printf(Locale.ROOT,
        "Progress: %d blocks over %.2f s, mean block interval %.2f ms, overflows %d%n",
        blocks, elapsedSeconds, averageIntervalMs, overflows);
    System.out.printf(Locale.ROOT,
        "Signal: RMS %.6f, peak %.6f; final FFT window RMS %.6f, peak %.6f%s%n",
        rms, peak, windowRms, windowPeak, peak > 0.001f ? " (non-silent activity detected)" : " (very quiet; verify input)");
    if (blocks == 0) throw new IOException("Capture completed without audio blocks");
  }

  private IOException failure(int code, String operation) {
    return new IOException(operation + ": " + pa.Pa_GetErrorText(code) + " (" + code + ")");
  }

  private void check(int result, String operation) throws IOException {
    if (result != 0) throw failure(result, operation);
  }

  private void closeStream() throws IOException {
    if (stream == null) return;
    IOException problem = null;
    int result = pa.Pa_StopStream(stream);
    if (result != 0) problem = failure(result, "Stop Core Audio input");
    result = pa.Pa_CloseStream(stream);
    stream = null;
    if (result != 0) {
      IOException closeError = failure(result, "Close Core Audio input");
      if (problem == null) problem = closeError;
      else problem.addSuppressed(closeError);
    }
    if (problem != null) throw problem;
  }

  @Override
  public void close() throws IOException {
    if (closed) return;
    IOException problem = null;
    try {
      closeStream();
    } catch (IOException e) {
      problem = e;
    }
    if (initialized) {
      int result = pa.Pa_Terminate();
      initialized = false;
      if (result != 0) {
        IOException terminateError = failure(result, "Terminate PortAudio");
        if (problem == null) problem = terminateError;
        else problem.addSuppressed(terminateError);
      }
    }
    closed = true;
    if (problem != null) throw problem;
  }
}
