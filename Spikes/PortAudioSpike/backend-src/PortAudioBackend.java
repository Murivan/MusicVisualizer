import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

// Minimal PortAudio capture facade over JNA (blocking read API). com.sun.jna is referenced by fully
// qualified name because Processing's preprocessor refuses `import com.sun.jna` when several installed
// libraries bundle JNA.
public class PortAudioBackend {
  public interface PA extends com.sun.jna.Library {
    int Pa_Initialize();
    int Pa_Terminate();
    String Pa_GetVersionText();
    String Pa_GetErrorText(int errorCode);
    com.sun.jna.Pointer Pa_GetHostApiInfo(int hostApi);
    int Pa_GetDeviceCount();
    com.sun.jna.Pointer Pa_GetDeviceInfo(int device);
    int Pa_OpenStream(com.sun.jna.ptr.PointerByReference stream, com.sun.jna.Pointer input, com.sun.jna.Pointer output,
      double sampleRate, com.sun.jna.NativeLong framesPerBuffer, com.sun.jna.NativeLong flags,
      com.sun.jna.Pointer callback, com.sun.jna.Pointer userData);
    int Pa_StartStream(com.sun.jna.Pointer stream);
    int Pa_StopStream(com.sun.jna.Pointer stream);
    int Pa_CloseStream(com.sun.jna.Pointer stream);
    int Pa_ReadStream(com.sun.jna.Pointer stream, com.sun.jna.Pointer buffer, com.sun.jna.NativeLong frames);
    com.sun.jna.Pointer Pa_GetStreamInfo(com.sun.jna.Pointer stream);
  }

  public static final int PA_FLOAT32 = 1;
  public static final int PA_WASAPI_TYPE_ID = 13;
  public static final int INPUT_OVERFLOWED = -9981;

  public static class Device {
    public int index;
    public String name;
    public String hostApi;
    public int hostApiType;
    public int maxInputChannels;
    public double defaultSampleRate;
    public double defaultLowLatencySeconds;
  }

  private final PA pa;
  private final String version;

  public PortAudioBackend(File library) throws IOException {
    pa = com.sun.jna.Native.load(library.getAbsolutePath(), PA.class);
    int err = pa.Pa_Initialize();
    if (err != 0) throw new IOException("Pa_Initialize: " + pa.Pa_GetErrorText(err));
    version = pa.Pa_GetVersionText();
  }

  public String version() {
    return version;
  }

  public String errorText(int code) {
    return pa.Pa_GetErrorText(code);
  }

  public void terminate() {
    pa.Pa_Terminate();
  }

  public List<Device> inputDevices() {
    List<Device> result = new ArrayList<Device>();
    int count = pa.Pa_GetDeviceCount();
    for (int i = 0; i < count; i++) {
      com.sun.jna.Pointer info = pa.Pa_GetDeviceInfo(i);
      if (info == null) continue;
      int maxIn = info.getInt(20);
      if (maxIn <= 0) continue;
      Device d = new Device();
      d.index = i;
      d.name = info.getPointer(8).getString(0, "UTF-8");
      com.sun.jna.Pointer host = pa.Pa_GetHostApiInfo(info.getInt(16));
      d.hostApiType = host.getInt(4);
      d.hostApi = host.getPointer(8).getString(0, "UTF-8");
      d.maxInputChannels = maxIn;
      d.defaultLowLatencySeconds = info.getDouble(32);
      d.defaultSampleRate = info.getDouble(64);
      result.add(d);
    }
    return result;
  }

  // framesPerBuffer 0 lets the host API choose; the block size each read() returns is then 256 frames.
  public InputStream openInput(Device d, int framesPerBuffer, boolean wasapiExclusive) throws IOException {
    int channels = Math.min(2, d.maxInputChannels);

    // PaStreamParameters layout is identical on LLP64 (Windows) and LP64: 4,4,8(format),8(latency),8(ptr).
    com.sun.jna.Memory params = new com.sun.jna.Memory(32);
    params.clear();
    params.setInt(0, d.index);
    params.setInt(4, channels);
    params.setInt(8, PA_FLOAT32);
    params.setDouble(16, framesPerBuffer > 0 ? framesPerBuffer / d.defaultSampleRate : d.defaultLowLatencySeconds);

    com.sun.jna.Memory wasapiInfo = null;
    if (wasapiExclusive && d.hostApiType == PA_WASAPI_TYPE_ID) {
      // PaWasapiStreamInfo (x64): size, hostApiType, version, flags (paWinWasapiExclusive = 1), channelMask,
      // two host-processor pointers, threadPriority, streamCategory, streamOption. PortAudio rejects a wrong size.
      wasapiInfo = new com.sun.jna.Memory(56);
      wasapiInfo.clear();
      wasapiInfo.setInt(0, 56);
      wasapiInfo.setInt(4, PA_WASAPI_TYPE_ID);
      wasapiInfo.setInt(8, 1);
      wasapiInfo.setInt(12, 1);
      params.setPointer(24, wasapiInfo);
    }

    com.sun.jna.ptr.PointerByReference ref = new com.sun.jna.ptr.PointerByReference();
    int err = pa.Pa_OpenStream(ref, params, null, d.defaultSampleRate,
      new com.sun.jna.NativeLong(framesPerBuffer), new com.sun.jna.NativeLong(0), null, null);
    if (err != 0) throw new IOException("Open failed: " + pa.Pa_GetErrorText(err) + " (" + err + ")");
    com.sun.jna.Pointer stream = ref.getValue();
    err = pa.Pa_StartStream(stream);
    if (err != 0) {
      pa.Pa_CloseStream(stream);
      throw new IOException("Start failed: " + pa.Pa_GetErrorText(err) + " (" + err + ")");
    }

    InputStream s = new InputStream();
    s.stream = stream;
    s.channels = channels;
    s.readFrames = framesPerBuffer > 0 ? framesPerBuffer : 256;
    s.requestedSampleRate = d.defaultSampleRate;
    s.exclusive = wasapiInfo != null;
    com.sun.jna.Pointer streamInfo = pa.Pa_GetStreamInfo(stream);
    if (streamInfo != null) {
      s.inputLatencyMs = streamInfo.getDouble(8) * 1000.0;
      s.sampleRate = streamInfo.getDouble(24);
    } else {
      s.sampleRate = d.defaultSampleRate;
    }
    s.buffer = new com.sun.jna.Memory((long) s.readFrames * channels * 4);
    return s;
  }

  public class InputStream {
    com.sun.jna.Pointer stream;
    com.sun.jna.Memory buffer;
    public int channels;
    public int readFrames;
    public double sampleRate;
    public double requestedSampleRate;
    public double inputLatencyMs;
    public boolean exclusive;

    // Blocks until readFrames frames arrive; fills out (readFrames * channels interleaved floats).
    // Returns 0, INPUT_OVERFLOWED (data still valid) or a negative PortAudio error code.
    public int read(float[] out) {
      int err = pa.Pa_ReadStream(stream, buffer, new com.sun.jna.NativeLong(readFrames));
      if (err == 0 || err == INPUT_OVERFLOWED) buffer.read(0, out, 0, readFrames * channels);
      return err;
    }

    public void close() {
      pa.Pa_StopStream(stream);
      pa.Pa_CloseStream(stream);
    }
  }
}
