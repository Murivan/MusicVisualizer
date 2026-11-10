import java.util.Locale;

/** Hardware test of the main sketch's multi-driver capture path. */
public class PortAudioInputTest {
  public static void main(String[] args) throws Exception {
    if (args.length != 4 && args.length != 6)
      throw new IllegalArgumentException("Expected data path, host API, device fragment, mode and optional capture/FFT sizes");
    VisualizerWasapiTest.TestSketch sketch = new VisualizerWasapiTest.TestSketch();
    VisualizerWasapiTest.setDataDirectory(args[0]);
    sketch.audioBufferSize = args.length == 6 ? Integer.parseInt(args[5]) : 512;
    sketch.captureBufferSize = args.length == 6 ? Integer.parseInt(args[4]) : 128;
    try (Visualizer.PortAudioCapture input = sketch.new PortAudioCapture()) {
      String[] names = input.allDevices();
      String[] hosts = input.allHostApis();
      int[] types = input.allHostTypes();
      if (names.length != hosts.length || names.length != types.length) throw new AssertionError("Mismatched device lists");
      int index = -1;
      for (int i = 0; i < names.length; i++) {
        if (hosts[i].equalsIgnoreCase(args[1])
            && names[i].toLowerCase(Locale.ROOT).contains(args[2].toLowerCase(Locale.ROOT))) {
          if (index >= 0) throw new IllegalArgumentException("Ambiguous input name");
          index = i;
        }
      }
      if (index < 0) throw new IllegalArgumentException("Input not found: " + args[1] + " " + args[2]);
      sketch.activeInputDriver = hosts[index];
      sketch.activeWasapi = types[index] == 13;
      sketch.wasapiMode = args[3];
      input.openAny(index);
      if (((Number)input.call("readFrames")).intValue() != sketch.captureBufferSize
          || input.samples.length != sketch.audioBufferSize) throw new AssertionError("Incorrect buffer sizes");
      if (((Boolean) input.call("exclusive")) != (sketch.activeWasapi && args[3].equals("exclusive"))) {
        throw new AssertionError("Wrong capture mode");
      }
      Thread.sleep(5000);
      if (!input.failure().isEmpty() || input.lastBlockNanos() == 0) throw new AssertionError(input.failure());
      input.snapshot();
      System.out.println(hosts[index] + " " + names[index] + " captured, host latency "
          + input.inputLatencyMs() + " ms, overflows " + input.overflows());
    }
  }
}
