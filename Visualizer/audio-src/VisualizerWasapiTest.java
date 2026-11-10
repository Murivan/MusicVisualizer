import java.io.File;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Optional integration test using the exported sketch and a live PortAudio input. */
public class VisualizerWasapiTest {
  private static String dataDirectory;
  static void setDataDirectory(String value) { dataDirectory = value; }

  static class TestSketch extends Visualizer {
    String parameters;

    @Override
    public String dataPath(String path) {
      return new File(dataDirectory, path).getAbsolutePath();
    }

    @Override
    public InputStream createInput(String path) {
      if (path.equals("parameters.txt") && parameters != null) {
        return new ByteArrayInputStream(parameters.getBytes(StandardCharsets.UTF_8));
      }
      return super.createInput(path);
    }
  }

  public static void main(String[] args) throws Exception {
    if (args.length < 2 || args.length > 3) throw new IllegalArgumentException("Expected data directory, device name and optional mode");
    String mode = args.length == 3 ? args[2] : "shared";
    if (!mode.equals("shared") && !mode.equals("exclusive")) throw new IllegalArgumentException("Invalid WASAPI mode");
    dataDirectory = args[0];
    TestSketch sketch = new TestSketch();
    if (!sketch.wasapiMode.equals("shared")) throw new IllegalStateException("Default mode is not shared");
    sketch.parameters = "liveInputBackend=portaudio\nwasapiMode=" + mode
        + "\naudioBufferSize=512\ncaptureBufferSize=128\n";
    sketch.loadParameters();
    if (!sketch.liveInputBackend.equals("portaudio") || !sketch.wasapiMode.equals(mode)) {
      throw new IllegalStateException("PortAudio configuration was not applied");
    }
    try (Visualizer.PortAudioCapture input = sketch.new PortAudioCapture()) {
      String[] devices = input.allDevices();
      String[] hosts = input.allHostApis();
      int[] hostTypes = input.allHostTypes();
      int selection = -1;
      for (int i = 0; i < devices.length; i++) {
        if (devices[i].toLowerCase(Locale.ROOT).contains(args[1].toLowerCase(Locale.ROOT))) {
          if (selection >= 0) throw new IllegalStateException("Device name matches multiple inputs");
          selection = i;
        }
      }
      if (selection < 0) throw new IllegalStateException("Device not found: " + args[1]);
      sketch.activeWasapi = hostTypes[selection] == 13;
      input.openAny(selection);
      boolean exclusive = (Boolean)input.call("exclusive");
      if (exclusive != (mode.equals("exclusive") && sketch.activeWasapi)) throw new IllegalStateException("Incorrect capture mode");
      Thread.sleep(2000);
      if (!input.failure().isEmpty()) throw new IllegalStateException(input.failure());
      if (input.lastBlockNanos() == 0) throw new IllegalStateException("No captured blocks");
      input.snapshot();
      for (float sample : input.samples) {
        if (!Float.isFinite(sample)) throw new IllegalStateException("Invalid audio sample");
      }
      System.out.println("Visualizer class loader captured " + hosts[selection] + " " + devices[selection]
          + "; input latency " + input.inputLatencyMs() + " ms; overflows " + input.overflows());
    }
  }
}
